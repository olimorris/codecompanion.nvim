--[[
Rex (https://www.superlogical.com/rex) is a terminal multiplexer that shows what
the programs in its panes are doing. This module reports each chat buffer and CLI
interaction as its own record, so Rex can show which one is working or waiting.

Docs: https://www.superlogical.com/rex/docs/build/program-status

Environment, set by Rex in every terminal it opens:
  REX_SESSION  Only report when this is set, so nothing is written outside Rex

Reporting, written to the terminal Neovim runs in:
  OSC 7501 ; id=<id> : state=<idle|working|blocked|done|clear> : app=<app>
    [: kind=<permission|question>] [: title=<base64>] [: msg=<base64>] ST

Each report replaces its record completely, so every report carries every key.
Clearing an id also clears every record beneath it, which is how all of
CodeCompanion's records are removed in one report when Neovim exits.
--]]

local api = vim.api

local M = {}

local CONSTANTS = {
  APP = "codecompanion",
  ID = "codecompanion",
  MAX_MESSAGE_BYTES = 2048,
  MAX_TITLE_BYTES = 192,
}

---@type table<number, { state: "idle"|"working"|"blocked"|"done", kind?: string, message?: string }>
local records = {}

---Make text safe for a report, which is single line base64 with a size limit
---@param opts { text: string, max_bytes: number }
---@return string
local function encode(opts)
  local text = opts.text:gsub("%c", " ")
  if #text > opts.max_bytes then
    -- Cut before the character that crosses the limit, so a multibyte character isn't split
    local cut = opts.max_bytes + 1
    text = text:sub(1, cut - 1 + vim.str_utf_start(text, cut))
  end
  return vim.base64.encode(text)
end

---@param bufnr number
---@return string|nil
local function get_title(bufnr)
  local chat = require("codecompanion.interactions.chat").buf_get_chat(bufnr)
  return chat and chat.title or nil
end

---@param fields string[]
---@return nil
local function send(fields)
  api.nvim_ui_send("\027]7501;" .. table.concat(fields, ":") .. "\027\\")
end

---@param bufnr number
---@return nil
local function report(bufnr)
  local record = records[bufnr]
  local fields = { "id=" .. CONSTANTS.ID .. "/" .. bufnr, "state=" .. record.state, "app=" .. CONSTANTS.APP }

  if record.kind then
    table.insert(fields, "kind=" .. record.kind)
  end
  local title = get_title(bufnr)
  if title then
    table.insert(fields, "title=" .. encode({ text = title, max_bytes = CONSTANTS.MAX_TITLE_BYTES }))
  end
  if record.message then
    table.insert(fields, "msg=" .. encode({ text = record.message, max_bytes = CONSTANTS.MAX_MESSAGE_BYTES }))
  end

  send(fields)
end

---@param args { bufnr: number, state: "idle"|"working"|"blocked"|"done", kind?: string, message?: string }
---@return nil
local function track(args)
  records[args.bufnr] = { state = args.state, kind = args.kind, message = args.message }
  report(args.bufnr)
end

---Return a blocked chat to working
---@param args { bufnr: number }
---@return nil
local function resume(args)
  local record = records[args.bufnr]
  if not record or record.state ~= "blocked" then
    return
  end
  track({ bufnr = args.bufnr, state = "working" })
end

---@param args { bufnr: number }
---@return nil
local function untrack(args)
  if not records[args.bufnr] then
    return
  end
  records[args.bufnr] = nil
  send({ "id=" .. CONSTANTS.ID .. "/" .. args.bufnr, "state=clear" })
end

---@return nil
function M.setup()
  if not vim.env.REX_SESSION or vim.env.REX_SESSION == "" then
    return
  end

  local group = api.nvim_create_augroup("codecompanion.integrations.rex", { clear = true })

  api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    desc = "Clear a chat's record in Rex when its buffer is removed",
    callback = function(args)
      untrack({ bufnr = args.buf })
    end,
  })

  api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    desc = "Clear CodeCompanion's records in Rex",
    callback = function()
      -- A done record survives Neovim exiting and would sit in Rex until dismissed
      if not vim.tbl_isempty(records) then
        records = {}
        send({ "id=" .. CONSTANTS.ID, "state=clear" })
      end
    end,
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

  on({ "CodeCompanionChatCreated", "CodeCompanionCLICreated", "CodeCompanionChatStopped" }, function(data)
    track({ bufnr = data.bufnr, state = "idle" })
  end)
  on({
    "CodeCompanionChatSubmitted",
    "CodeCompanionChatCompacting",
    "CodeCompanionCLISubmitted",
    "CodeCompanionToolsStarted",
  }, function(data)
    track({ bufnr = data.bufnr, state = "working" })
  end)
  on({ "CodeCompanionChatDone", "CodeCompanionCLIDone" }, function(data)
    track({ bufnr = data.bufnr, state = "done" })
  end)
  on({ "CodeCompanionChatClosed", "CodeCompanionCLIClosed" }, function(data)
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
  on({ "CodeCompanionCLIApprovalRequested" }, function(data)
    track({ bufnr = data.bufnr, state = "blocked", kind = "permission", message = data.message })
  end)
  on({ "CodeCompanionToolQuestionAsked" }, function(data)
    track({
      bufnr = data.bufnr,
      state = "blocked",
      kind = "question",
      message = data.header and ("Question: " .. data.header) or "Question",
    })
  end)
  on({
    "CodeCompanionToolApprovalFinished",
    "CodeCompanionCLIApprovalFinished",
    "CodeCompanionToolQuestionAnswered",
  }, function(data)
    resume({ bufnr = data.bufnr })
  end)
end

return M
