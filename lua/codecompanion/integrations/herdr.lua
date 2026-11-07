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

The Herdr app (herdr-core) sets HC_TERMINAL_ID in every terminal instead, and
reads a program's status from an OSC 7501 sequence written to the terminal:
  ESC ]7501;state=<idle|working|done|blocked>[:kind=<permission|question>]:app=<app> ESC \
  ESC ]7501;state=clear ESC \

`done` marks a finished turn until the user looks at the pane, when the app turns it into `idle`.

The app names an agent after its terminal title (OSC 2), as the 7501 `title` field isn't accepted.
--]]

local log = require("codecompanion.utils.log")

local api = vim.api

local M = {}

local CONSTANTS = {
  AGENT = "CodeCompanion.nvim",
  APP = "codecompanion",
  SOURCE = "custom:codecompanion.nvim:" .. (vim.env.HERDR_PANE_ID or ""),
}

---@alias CodeCompanion.Herdr.Status { state: "idle"|"working"|"blocked", message?: string, kind?: "permission"|"question" }

local herdr = nil ---@type string|nil
local last_status = nil ---@type CodeCompanion.Herdr.Status|nil

---@type { report: fun(opts: { status: CodeCompanion.Herdr.Status, previous_state?: string }), release: fun(), retitle?: fun() }|nil
local reporter = nil

local last_active_bufnr = nil ---@type number|nil
local last_title = nil ---@type string|nil

---herdr discards a sequence if it's not greater than the previous one
local seq = os.time() * 1000

---Enables multiple chat buffers to affect the pane's state
---@type table<number, CodeCompanion.Herdr.Status>
local in_flight_chats = {}

---@type table<number, boolean>
local open_chats = {}

---@type table<number, string>
local chat_titles = {}

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

---Aggregate every in-flight chat's state
---@return CodeCompanion.Herdr.Status
local function aggregate_in_flight_chats()
  local is_working = false
  for _, entry in pairs(in_flight_chats) do
    if entry.state == "blocked" then
      return entry
    end
    is_working = true
  end

  return { state = is_working and "working" or "idle" }
end

---@return string
local function next_seq()
  -- Must be greater than the previous sequence
  seq = seq + 1
  return string.format("%d", seq)
end

---@param opts { status: CodeCompanion.Herdr.Status }
---@return nil
local function report_with_cli(opts)
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
    opts.status.state,
  }
  if opts.status.message then
    vim.list_extend(args, { "--message", opts.status.message })
  end
  vim.list_extend(args, { "--seq", next_seq() })

  log:trace("[herdr] Reporting: %s", table.concat(args, " "))
  vim.system(args, {}, function(result)
    if result.code ~= 0 then
      vim.schedule(function()
        log:debug("[herdr] Report of `%s` exited with %d: %s", opts.status.state, result.code, result.stderr or "")
      end)
    end
  end)
end

---@return nil
local function release_with_cli()
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

---@param fields string[]
---@return nil
local function send_osc(fields)
  local payload = table.concat(fields, ":")
  log:trace("[herdr] Reporting: %s", payload)

  -- The TUI runs in a separate process, so the sequence must go through the UI rather than stdout
  local ok, err = pcall(api.nvim_ui_send, "\027]7501;" .. payload .. "\027\\")
  if not ok then
    log:error("[herdr] Report of `%s` failed: %s", payload, err)
  end
end

---@param opts { status: CodeCompanion.Herdr.Status, previous_state?: string }
---@return nil
local function report_with_osc(opts)
  local state = opts.status.state ---@type string
  if state == "idle" and opts.previous_state and opts.previous_state ~= "idle" then
    state = "done"
  end

  local fields = { "state=" .. state }
  if opts.status.kind then
    table.insert(fields, "kind=" .. opts.status.kind)
  end
  table.insert(fields, "app=" .. CONSTANTS.APP)
  send_osc(fields)
end

---@param title string
---@return nil
local function send_title(title)
  title = title:gsub("%c", " ")
  if title == last_title then
    return
  end
  last_title = title

  local ok, err = pcall(api.nvim_ui_send, "\027]2;" .. title .. "\027\\")
  if not ok then
    log:error("[herdr] Setting the title failed: %s", err)
  end
end

---Name the pane after the most recently active chat, else the branch Neovim is on
---@return nil
local function update_title()
  -- Neovim rewrites the terminal title itself when 'title' is on
  if vim.o.title then
    return
  end

  if chat_titles[last_active_bufnr] then
    return send_title(chat_titles[last_active_bufnr])
  end

  local ok, err = pcall(vim.system, { "git", "branch", "--show-current" }, { text = true }, function(result)
    local branch = result.code == 0 and vim.trim(result.stdout or "") or ""
    vim.schedule(function()
      -- A chat may have been titled or closed while git ran
      if not last_status or chat_titles[last_active_bufnr] then
        return
      end
      send_title(branch ~= "" and string.format("CodeCompanion [%s]", branch) or "CodeCompanion")
    end)
  end)
  if not ok then
    log:debug("[herdr] Couldn't read the branch for the title: %s", err)
    send_title("CodeCompanion")
  end
end

---@return nil
local function release_with_osc()
  send_osc({ "state=clear" })
  if last_title then
    send_title("")
  end
end

---Pick how to report to herdr, or nil when Neovim isn't running inside it
---@return table|nil
local function resolve_reporter()
  herdr = resolve_herdr_path()

  -- A herdr pane inside the Herdr app inherits HC_TERMINAL_ID, but only the inner herdr sees the sequence
  if vim.env.HERDR_ENV == "1" and vim.env.HERDR_PANE_ID ~= nil and herdr ~= nil then
    return { report = report_with_cli, release = release_with_cli }
  end

  if vim.env.HC_TERMINAL_ID and vim.env.HC_TERMINAL_ID ~= "" then
    return { report = report_with_osc, release = release_with_osc, retitle = update_title }
  end

  return nil
end

---Release CodeCompanion from the pane in herdr
---@return nil
local function release()
  if not last_status then
    return
  end
  last_status = nil
  reporter.release()
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
  for bufnr in pairs(chat_titles) do
    if not api.nvim_buf_is_loaded(bufnr) then
      chat_titles[bufnr] = nil
    end
  end
  if last_active_bufnr and not (in_flight_chats[last_active_bufnr] or open_chats[last_active_bufnr]) then
    last_active_bufnr = next(in_flight_chats) or next(open_chats)
  end
end

---Sync CodeCompanion's status with herdr
---@return nil
local function update_herdr()
  validate_chat_buffers()

  if vim.tbl_isempty(in_flight_chats) and vim.tbl_isempty(open_chats) then
    return release()
  end

  -- A blocked pane can change what it is waiting on so make sure we capture this
  local status = aggregate_in_flight_chats()
  if not vim.deep_equal(status, last_status) then
    local previous_state = last_status and last_status.state
    last_status = status
    reporter.report({ status = status, previous_state = previous_state })
  end

  if reporter.retitle then
    reporter.retitle()
  end
end

---Track an in-flight chat with herdr
---@param args { bufnr: number, state: "working"|"blocked", message?: string, kind?: "permission"|"question" }
---@return nil
local function track(args)
  in_flight_chats[args.bufnr] = { state = args.state, message = args.message, kind = args.kind }
  last_active_bufnr = args.bufnr
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

---Environment for the agents that CodeCompanion spawns
---@return table<string, string>
function M.agent_env()
  -- Empty so a spawned agent can't report against Neovim's pane
  -- NOTE: HERDR_ENV is the guard any hooks check first
  -- HC_TERMINAL_ID would make hc type notes about the agent's own `hc run` terminals into Neovim
  return { HERDR_ENV = "", HERDR_PANE_ID = "", HC_TERMINAL_ID = "" }
end

---@return nil
function M.setup()
  reporter = resolve_reporter()
  if not reporter then
    log:trace(
      "[herdr] Not reporting: HERDR_ENV=%s HERDR_PANE_ID=%s herdr=%s HC_TERMINAL_ID=%s",
      tostring(vim.env.HERDR_ENV),
      tostring(vim.env.HERDR_PANE_ID),
      tostring(herdr),
      tostring(vim.env.HC_TERMINAL_ID)
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

  on({
    "CodeCompanionChatSubmitted",
    "CodeCompanionChatCompacting",
    "CodeCompanionCLISubmitted",
    "CodeCompanionToolsStarted",
  }, function(data)
    track({ bufnr = data.bufnr, state = "working" })
  end)

  on({ "CodeCompanionChatCreated", "CodeCompanionCLICreated" }, function(data)
    open_chats[data.bufnr] = true
    last_active_bufnr = data.bufnr
    update_herdr()
  end)
  on({ "CodeCompanionChatTitle" }, function(data)
    chat_titles[data.bufnr] = data.title
    if open_chats[data.bufnr] or in_flight_chats[data.bufnr] then
      update_herdr()
    end
  end)
  on({ "CodeCompanionChatDone", "CodeCompanionChatStopped", "CodeCompanionCLIDone" }, function(data)
    untrack({ bufnr = data.bufnr })
  end)
  on({ "CodeCompanionChatClosed", "CodeCompanionCLIClosed" }, function(data)
    open_chats[data.bufnr] = nil
    chat_titles[data.bufnr] = nil
    untrack({ bufnr = data.bufnr })
  end)

  on({ "CodeCompanionToolApprovalRequested" }, function(data)
    track({
      bufnr = data.bufnr,
      state = "blocked",
      kind = "permission",
      message = data.name and ("Approval needed: " .. data.name) or nil,
    })
  end)
  on({ "CodeCompanionToolApprovalFinished" }, function(data)
    resume({ bufnr = data.bufnr })
  end)

  on({ "CodeCompanionCLIApprovalRequested" }, function(data)
    track({ bufnr = data.bufnr, state = "blocked", kind = "permission", message = data.message })
  end)
  on({ "CodeCompanionCLIApprovalFinished" }, function(data)
    resume({ bufnr = data.bufnr })
  end)

  on({ "CodeCompanionToolQuestionAsked" }, function(data)
    track({
      bufnr = data.bufnr,
      state = "blocked",
      kind = "question",
      message = data.header and ("Question: " .. data.header) or "Question",
    })
  end)
  on({ "CodeCompanionToolQuestionAnswered" }, function(data)
    resume({ bufnr = data.bufnr })
  end)
end

return M
