local log = require("codecompanion.utils.log")

local api = vim.api

local M = {}

local CONSTANTS = {
  AGENT = "codecompanion.nvim",
  SOURCE = "custom:codecompanion.nvim",
}

local herdr = nil ---@type string|nil
local last_state = nil ---@type string|nil

---herdr discards a sequence if it's not greater than the previous one
local seq = os.time() * 1000

---Enables multiple chat buffers to affect the pane's state
---@type table<string, { state: "working"|"blocked", message?: string }>
local in_flight_chats = {}

---@type table<number, boolean>
local open_chats = {}

---@return string|nil
local function resolve_herdr_path()
  if vim.env.HERDR_BIN_PATH and vim.env.HERDR_BIN_PATH ~= "" then
    return vim.env.HERDR_BIN_PATH
  end

  if vim.fn.executable("herdr") == 1 then
    return "herdr"
  end

  return nil
end

---@return boolean
local function herdr_active()
  return vim.env.HERDR_ENV == "1" and vim.env.HERDR_PANE_ID ~= nil and herdr ~= nil
end

---Aggregate every in-flight chat's state
---@return "idle"|"working"|"blocked" state
---@return string|nil message
local function aggregate_in_flight_chats()
  local is_working = false
  for _, entry in pairs(in_flight_chats) do
    if entry.state == "blocked" then
      return "blocked", entry.message
    end
    is_working = true
  end

  return is_working and "working" or "idle", nil
end

---@return string
local function next_seq()
  -- Must be greater than the previous sequence
  seq = seq + 1
  return string.format("%d", seq)
end

---Release CodeCompanion from the pane in herdr
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

---Sync CodeCompanion's status with herdr
---@return nil
local function update_herdr()
  if vim.tbl_isempty(in_flight_chats) and vim.tbl_isempty(open_chats) then
    return release()
  end

  local state, message = aggregate_in_flight_chats()
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

---Track an in-flight track with herdr
---@param key string
---@param state "working"|"blocked"
---@param message? string
---@return nil
local function track(key, state, message)
  in_flight_chats[key] = { state = state, message = message }
  update_herdr()
end

---@param key string
---@return nil
local function untrack(key)
  in_flight_chats[key] = nil
  update_herdr()
end

---@return nil
function M.setup()
  herdr = resolve_herdr_path()
  if not herdr_active() then
    log:trace(
      "[herdr] Not reporting: HERDR_ENV=%s HERDR_PANE_ID=%s herdr=%s",
      tostring(vim.env.HERDR_ENV),
      tostring(vim.env.HERDR_PANE_ID),
      tostring(herdr)
    )
    return
  end

  local group = api.nvim_create_augroup("codecompanion.integrations.herdr", { clear = true })

  ---@param events string[]
  ---@param callback fun(data: table)
  local function on(events, callback)
    api.nvim_create_autocmd("User", {
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
    update_herdr()
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

  api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    desc = "Release CodeCompanion's authority over the herdr pane",
    callback = release,
  })
end

return M
