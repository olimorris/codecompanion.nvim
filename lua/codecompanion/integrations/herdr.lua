local log = require("codecompanion.utils.log")

local M = {}

local CONSTANTS = {
  AGENT = "codecompanion.nvim",
  SOURCE = "custom:codecompanion.nvim",
}

local herdr = nil ---@type string|nil
local last_state = nil ---@type string|nil

-- herdr discards any sequence that isn't strictly greater than the last one it
-- saw for our source, remembering across Neovim sessions. Seeding from Lua's
-- built-in time ensures that we'll be safe
local seq = os.time() * 1000

---The chat buffers mid-turn, keyed by buffer number
---@type table<string, { state: "working"|"blocked", message?: string }>
local in_flight = {}

---Store the chat buffers so we know what's listed in herdr
---@type table<number, boolean>
local open_chats = {}

---Resolve the herdr path
---@return string|nil
local function resolve_herdr()
  if vim.env.HERDR_BIN_PATH and vim.env.HERDR_BIN_PATH ~= "" then
    return vim.env.HERDR_BIN_PATH
  end

  if vim.fn.executable("herdr") == 1 then
    return "herdr"
  end

  return nil
end

---Check whether Neovim is running inside a herdr pane
---@return boolean
local function is_active()
  return vim.env.HERDR_ENV == "1" and vim.env.HERDR_PANE_ID ~= nil and herdr ~= nil
end

---Roll everything in flight up into the single state the herdr pane can display
---@return "idle"|"working"|"blocked" state
---@return string|nil message
local function aggregate()
  local is_working = false
  for _, entry in pairs(in_flight) do
    if entry.state == "blocked" then
      return "blocked", entry.message
    end
    is_working = true
  end

  return is_working and "working" or "idle", nil
end

---herdr requires the sequence to be strictly greater than the last one it saw
---@return string
local function next_seq()
  seq = seq + 1
  return string.format("%d", seq)
end

---Hand the pane back to herdr, so it no longer lists CodeCompanion as one of its agents
---@return nil
local function release()
  if not last_state then
    return
  end
  last_state = nil

  -- Carries a sequence so herdr discards any report still in flight, which would re-attach the agent
  local args = {
    herdr,
    "pane",
    "release-agent",
    vim.env.HERDR_PANE_ID,
    "--source",
    CONSTANTS.SOURCE,
    "--agent",
    CONSTANTS.AGENT,
    "--seq",
    next_seq(),
  }
  log:trace("[herdr] Releasing: %s", table.concat(args, " "))

  -- Neovim tears down its event loop as soon as this returns, so wait rather than fire and forget
  local ok, result = pcall(function()
    return vim.system(args):wait(1000)
  end)
  if not ok then
    return log:error("[herdr] Release failed to run: %s", result)
  end
  if result.code ~= 0 then
    return log:error("[herdr] Release exited with %d: %s", result.code, result.stderr or "")
  end
end

---Report the pane's state to herdr, skipping the call when nothing has changed
---@return nil
local function sync()
  -- An idle agent stays listed against the pane, so let go entirely once no chat is left to return to
  if vim.tbl_isempty(in_flight) and vim.tbl_isempty(open_chats) then
    return release()
  end

  local state, message = aggregate()
  if state == last_state then
    return
  end
  last_state = state

  local args = {
    herdr,
    "pane",
    "report-agent",
    vim.env.HERDR_PANE_ID,
    "--source",
    CONSTANTS.SOURCE,
    "--agent",
    CONSTANTS.AGENT,
    "--state",
    state,
  }
  if message then
    vim.list_extend(args, { "--message", message })
  end
  vim.list_extend(args, { "--seq", next_seq() })

  log:trace("[herdr] Reporting: %s", table.concat(args, " "))
  vim.system(args, {}, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        log:error("[herdr] Report of `%s` exited with %d: %s", state, result.code, result.stderr or "")
      end)
    end
  end)
end

---Record a chat as being mid-turn
---@param key string
---@param state "working"|"blocked"
---@param message? string
---@return nil
local function track(key, state, message)
  in_flight[key] = { state = state, message = message }
  sync()
end

---Drop a chat, moving the pane to idle once no other chat is mid-turn
---@param key string
---@return nil
local function untrack(key)
  in_flight[key] = nil
  sync()
end

---Report CodeCompanion's activity to herdr for the life of the Neovim instance
---@return nil
function M.setup()
  herdr = resolve_herdr()
  if not is_active() then
    log:trace(
      "[herdr] Not reporting: HERDR_ENV=%s HERDR_PANE_ID=%s herdr=%s",
      tostring(vim.env.HERDR_ENV),
      tostring(vim.env.HERDR_PANE_ID),
      tostring(herdr)
    )
    return
  end

  local group = vim.api.nvim_create_augroup("codecompanion.integrations.herdr", { clear = true })

  ---@param events string[]
  ---@param callback fun(data: table)
  local function on(events, callback)
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = events,
      callback = function(args)
        callback(args.data or {})
      end,
    })
  end

  -- A chat stays in flight for the whole turn, regardless of agentic loops
  on({ "CodeCompanionChatSubmitted", "CodeCompanionChatCompacting", "CodeCompanionToolsStarted" }, function(data)
    track("chat:" .. tostring(data.bufnr), "working")
  end)

  -- Opening a chat attaches onto the pane as idle, listing it in herdr
  on({ "CodeCompanionChatCreated" }, function(data)
    open_chats[data.bufnr] = true
    sync()
  end)
  on({ "CodeCompanionChatDone", "CodeCompanionChatStopped" }, function(data)
    untrack("chat:" .. tostring(data.bufnr))
  end)
  on({ "CodeCompanionChatClosed" }, function(data)
    open_chats[data.bufnr] = nil
    untrack("chat:" .. tostring(data.bufnr))
  end)

  -- Show CodeCompanion as blocked when a user needs to approve a tool
  on({ "CodeCompanionToolApprovalRequested" }, function(data)
    track("chat:" .. tostring(data.bufnr), "blocked", data.name and ("Approval needed: " .. data.name) or nil)
  end)
  on({ "CodeCompanionToolApprovalFinished" }, function(data)
    track("chat:" .. tostring(data.bufnr), "working")
  end)

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    desc = "Release CodeCompanion's authority over the herdr pane",
    callback = release,
  })
end

return M
