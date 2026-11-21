local formatter = require("codecompanion.interactions.chat.acp.formatters")
local summary = require("codecompanion.interactions.chat.acp.subagents.summary")
local ui_utils = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

local CANCEL_KEY = "<C-c>"

local M = {}

---@param chat CodeCompanion.Chat
---@param subagent CodeCompanion.Chat.ACPSubagent
---@return boolean
local function can_cancel(chat, subagent)
  local connection = chat.acp_connection
  return connection ~= nil and connection.subagents:can_cancel(subagent.info.id)
end

---Check if the subagent reported its own, incoming view of a message the parent sent it
---@param subagent CodeCompanion.Chat.ACPSubagent
---@param message table
---@return boolean
local function is_reported_by_subagent(subagent, message)
  return vim.iter(subagent.transcript):any(function(item)
    return item.type == "session_message"
      and (item.senderMessageId == message.message_id or item.message_id == message.recipientMessageId)
  end)
end

---@param opts { header: string, text: string }
---@return string[]
local function format_quote(opts)
  local lines = { fmt("**%s**", opts.header) }
  for _, line in ipairs(vim.split(opts.text, "\n", { plain = true })) do
    table.insert(lines, "> " .. line)
  end
  return lines
end

---Describe the session on the other side of a message, from the subagent's point of view
---@param chat CodeCompanion.Chat
---@param opts { subagent: CodeCompanion.Chat.ACPSubagent, message: table }
---@return string
local function describe_participant(chat, opts)
  local subagent, message = opts.subagent, opts.message
  -- The RFD has the sender's own transcript hold the outgoing view, even when the recipient is unknown
  local is_outgoing = message.senderSessionId == subagent.info.id
  local other_id = message.senderSessionId
  if is_outgoing then
    other_id = message.recipientSessionId
  end
  local direction = is_outgoing and "To" or "From"

  if other_id == nil then
    return fmt("%s another session", direction)
  end
  if other_id == subagent.info.parent_id then
    return fmt("%s parent", direction)
  end
  local other = chat.subagents[other_id]
  return fmt("%s %s", direction, other and summary.get_label(other) or "another session")
end

---@param chat CodeCompanion.Chat
---@param opts { subagent: CodeCompanion.Chat.ACPSubagent, item: table }
---@return string[]
local function format_item(chat, opts)
  local subagent, item = opts.subagent, opts.item

  if item.type == "message" then
    return vim.split(item.text, "\n", { plain = true })
  end
  if item.type == "thought" then
    return vim.list_extend({ "_Thinking_" }, vim.split(item.text, "\n", { plain = true }))
  end
  if item.type == "session_message" then
    return format_quote({
      header = describe_participant(chat, { subagent = subagent, message = item }),
      text = item.text,
    })
  end
  if item.type == "parent_message" then
    local message = chat.messages_to_subagents[item.message_id]
    if not message or is_reported_by_subagent(subagent, message) then
      return {}
    end
    return format_quote({ header = "Sent by parent", text = message.text })
  end
  if item.type == "tool_call" then
    local call = subagent.tool_calls[item.id]
    local ok, message = pcall(formatter.tool_message, { tool_call = call, adapter = chat.adapter })
    return { fmt("- %s (%s)", ok and message.summary or "Tool call", call.status or "pending") }
  end
  if item.type == "subagent" then
    local nested = chat.subagents[item.id]
    return { fmt("- **Subagent** %s (%s)", summary.get_label(nested), summary.get_state(nested).description) }
  end
  return {}
end

---Format a subagent's description, state and transcript for a float
---@param chat CodeCompanion.Chat
---@param opts { subagent: CodeCompanion.Chat.ACPSubagent }
---@return { lines: string[], title: string }
function M.format(chat, opts)
  local subagent = opts.subagent
  local lines = {}

  if subagent.info.description and subagent.info.description ~= summary.get_label(subagent) then
    vim.list_extend(lines, { fmt("_%s_", subagent.info.description), "" })
  end
  table.insert(lines, fmt("**State** %s", summary.get_state(subagent).description))
  if subagent.model then
    table.insert(lines, fmt("**Model** %s", subagent.model))
  end
  if subagent.usage and subagent.usage.used then
    local size = subagent.usage.size and fmt(" of %s", subagent.usage.size) or ""
    table.insert(lines, fmt("**Tokens** %s%s", subagent.usage.used, size))
  end
  if can_cancel(chat, subagent) then
    table.insert(lines, fmt("_Press `%s` to cancel_", CANCEL_KEY))
  end
  if subagent.plan and #subagent.plan > 0 then
    vim.list_extend(lines, { "", "**Plan**" })
    for _, entry in ipairs(subagent.plan) do
      table.insert(lines, fmt("- [%s] %s", entry.status == "completed" and "x" or " ", entry.content))
    end
  end

  for _, item in ipairs(subagent.transcript) do
    local item_lines = format_item(chat, { subagent = subagent, item = item })
    if #item_lines > 0 then
      table.insert(lines, "")
      vim.list_extend(lines, item_lines)
    end
  end

  return { lines = lines, title = summary.get_label(subagent) }
end

---Redraw an open float, coalescing the many updates a streaming subagent sends
---@param chat CodeCompanion.Chat
---@param subagent CodeCompanion.Chat.ACPSubagent
---@return nil
function M.refresh(chat, subagent)
  if not subagent.float or subagent._is_refresh_scheduled then
    return
  end
  subagent._is_refresh_scheduled = true

  vim.schedule(function()
    subagent._is_refresh_scheduled = nil
    local float = subagent.float
    if not float or not api.nvim_win_is_valid(float.winnr) then
      subagent.float = nil
      return
    end

    local lines = M.format(chat, { subagent = subagent }).lines
    vim.bo[float.bufnr].modifiable = true
    api.nvim_buf_set_lines(float.bufnr, 0, -1, false, lines)
    vim.bo[float.bufnr].modifiable = false

    local height = math.min(#lines, math.floor(vim.o.lines * 0.6))
    if height > api.nvim_win_get_height(float.winnr) then
      api.nvim_win_set_height(float.winnr, height)
    end
  end)
end

---Redraw the floats of a subagent and its ancestors, which list its state
---@param chat CodeCompanion.Chat
---@param subagent? CodeCompanion.Chat.ACPSubagent
---@return nil
function M.refresh_with_ancestors(chat, subagent)
  while subagent do
    M.refresh(chat, subagent)
    subagent = chat.subagents[subagent.info.parent_id]
  end
end

---Open a float that follows the subagent's work as it happens
---@param chat CodeCompanion.Chat
---@param opts { subagent: CodeCompanion.Chat.ACPSubagent }
---@return nil
function M.open(chat, opts)
  local subagent = opts.subagent
  local details = M.format(chat, opts)
  local bufnr, winnr = ui_utils.create_hover({
    lines = details.lines,
    title = details.title,
    focus_id = "codecompanion_subagent",
  })
  subagent.float = { bufnr = bufnr, winnr = winnr }

  vim.keymap.set("n", CANCEL_KEY, function()
    local connection = chat.acp_connection
    if not (connection and connection.subagents:cancel(subagent.info.id)) then
      utils.notify("The agent doesn't allow this subagent to be cancelled", vim.log.levels.WARN)
    end
  end, { buffer = bufnr, desc = "Cancel the subagent", nowait = true, silent = true })
end

return M
