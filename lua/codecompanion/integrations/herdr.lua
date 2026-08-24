--[[
herdr (https://herdr.dev) supervises terminal panes and shows which agent is
running in each one. This module reports CodeCompanion's status so that a pane
running Neovim sits alongside panes running Claude Code, Codex etc.

Docs: https://herdr.dev/docs/integrations/#integrate-your-own-agent

Environment, set by herdr inside a managed pane:
  HERDR_ENV=1        Only report when this is set, so nothing runs outside herdr
  HERDR_PANE_ID      The pane to report against
  HERDR_BIN_PATH     Path to the herdr binary, which may be absent, so fall back to PATH
  HERDR_SOCKET_PATH  Unix socket taking the same calls as newline delimited JSON-RPC,
                     via pane.report_agent, pane.report_agent_session and pane.release_agent

Reporting:
  herdr pane report-agent <pane_id> --source <source> --agent <agent>
    --state <idle|working|blocked> [--message <text>] [--seq <n>]
    [--agent-session-id <id>] [--agent-session-path <path>]
  herdr pane release-agent <pane_id> --source <source> --agent <agent> [--seq <n>]

The source must be stable and unique per integration. The CodeCompanion implementation
carries the pane id to stop two Neovim instances in different panes claiming
each other's reports.

The sequence MUST increase. herdr discards any report arriving with a sequence
lower than the last one it accepted, which is how a report still in flight
is stopped from re-attaching an agent that has already been released.
--]]

local log = require("codecompanion.utils.log")

local api = vim.api

local M = {}

local CONSTANTS = {
  AGENT = "CodeCompanion.nvim",
  SOURCE = "custom:codecompanion.nvim:" .. (vim.env.HERDR_PANE_ID or ""),
}

local herdr = nil ---@type string|nil
local last_state = nil ---@type string|nil

---herdr discards a sequence if it's not greater than the previous one
local seq = os.time() * 1000

---Enables multiple chat buffers to affect the pane's state
---@type table<number, { state: "working"|"blocked", message?: string }>
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

---Checks any open chat buffers and removes them if they no longer exist
---@return nil
local function validate_chat_buffers()
  for bufnr in pairs(open_chats) do
    if not api.nvim_buf_is_loaded(bufnr) then
      open_chats[bufnr] = nil
    end
  end
  for bufnr in pairs(in_flight_chats) do
    if not api.nvim_buf_is_loaded(bufnr) then
      in_flight_chats[bufnr] = nil
    end
  end
end

---Sync CodeCompanion's status with herdr
---@return nil
local function update_herdr()
  validate_chat_buffers()

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
        log:debug("[herdr] Report of `%s` exited with %d: %s", state, result.code, result.stderr or "")
      end)
    end
  end)
end

---Track an in-flight chat with herdr
---@param args { bufnr: number, state: "working"|"blocked", message?: string }
---@return nil
local function track(args)
  in_flight_chats[args.bufnr] = { state = args.state, message = args.message }
  update_herdr()
end

---Return a chat to working
---@param args { bufnr: number }
---@return nil
local function resume(args)
  if not in_flight_chats[args.bufnr] then
    return
  end
  track({ bufnr = args.bufnr, state = "working" })
end

---@param args { bufnr: number }
---@return nil
local function untrack(args)
  in_flight_chats[args.bufnr] = nil
  update_herdr()
end

---Set the environment for ACP adapters
---@return table<string, string>
function M.acp_env()
  -- Ensure that any ACP agents spawned by CodeCompanion don't steal the herdr pane
  return { HERDR_ENV = "", HERDR_PANE_ID = "" }
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

  api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    desc = "Update herdr when a chat buffer is removed",
    callback = function()
      if vim.tbl_isempty(in_flight_chats) and vim.tbl_isempty(open_chats) then
        return
      end
      vim.schedule(update_herdr)
    end,
  })

  api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    desc = "Release CodeCompanion's authority over the herdr pane",
    callback = release,
  })

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

  on({ "CodeCompanionChatSubmitted", "CodeCompanionChatCompacting", "CodeCompanionToolsStarted" }, function(data)
    track({ bufnr = data.bufnr, state = "working" })
  end)

  on({ "CodeCompanionChatCreated" }, function(data)
    open_chats[data.bufnr] = true
    update_herdr()
  end)
  on({ "CodeCompanionChatDone", "CodeCompanionChatStopped" }, function(data)
    untrack({ bufnr = data.bufnr })
  end)
  on({ "CodeCompanionChatClosed" }, function(data)
    open_chats[data.bufnr] = nil
    untrack({ bufnr = data.bufnr })
  end)

  on({ "CodeCompanionToolApprovalRequested" }, function(data)
    track({ bufnr = data.bufnr, state = "blocked", message = data.name and ("Approval needed: " .. data.name) or nil })
  end)
  on({ "CodeCompanionToolApprovalFinished" }, function(data)
    resume({ bufnr = data.bufnr })
  end)

  on({ "CodeCompanionToolQuestionAsked" }, function(data)
    track({
      bufnr = data.bufnr,
      state = "blocked",
      message = data.header and ("Question: " .. data.header) or "Question",
    })
  end)
  on({ "CodeCompanionToolQuestionAnswered" }, function(data)
    resume({ bufnr = data.bufnr })
  end)
end

return M
