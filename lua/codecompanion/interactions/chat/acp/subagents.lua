local acp = require("codecompanion.acp")
local formatter = require("codecompanion.interactions.chat.acp.formatters")
local handler = require("codecompanion.interactions.chat.acp.handler")
local prompt_builder = require("codecompanion.acp.prompt_builder")
local tool_calls = require("codecompanion.interactions.chat.ui.tool_calls")
local ui_utils = require("codecompanion.utils.ui")
local utils = require("codecompanion.utils")

local api = vim.api
local fmt = string.format

local CANCEL_KEY = "<C-c>"
local FAILED_STOP_REASONS = { error = true, refusal = true, cancelled = true }
local MESSAGE_FIELDS = { "senderSessionId", "recipientSessionId", "senderMessageId", "recipientMessageId" }

---@class CodeCompanion.Chat.ACPSubagent
---@field disconnected? boolean
---@field float? { bufnr: number, winnr: number }
---@field info { additionalDirectories?: string[], capabilities?: { cancel?: table }, cwd?: string, description?: string, id: string, parent_id: string, state?: { error?: table, state: string, stopReason?: string }, title?: string }
---@field model? string
---@field plan? table[] The subagent's latest plan entries
---@field usage? { used?: number, size?: number }
---@field order number When the subagent was announced, relative to the chat's others
---@field tool_calls table<string, table> The subagent's tool calls by their ID
---@field transcript table[] Messages, tool calls and nested subagents, in the order they arrived
---@field ui? { icon_id?: number, line_number?: number, status?: string, summary?: string }
---@field _is_refresh_scheduled? boolean

local M = {}

---Read a subagent's work state as a tool call status, and as a description for its float
---@param subagent CodeCompanion.Chat.ACPSubagent
---@return { status: string, description: string }
local function get_state(subagent)
  if subagent.disconnected then
    return { status = "pending", description = "Disconnected" }
  end
  local state = subagent.info.state
  if type(state) ~= "table" then
    return { status = "pending", description = "Unconfirmed" }
  end

  local parts = { state.state }
  if type(state.stopReason) == "string" then
    table.insert(parts, fmt("(%s)", state.stopReason))
  end
  if type(state.error) == "table" and state.error.message then
    table.insert(parts, fmt("- %s", state.error.message))
  end

  local status = "pending"
  if state.state == "running" then
    status = "in_progress"
  elseif state.state == "idle" then
    status = FAILED_STOP_REASONS[state.stopReason] and "failed" or "completed"
  end
  return { status = status, description = table.concat(parts, " ") }
end

---@param subagent CodeCompanion.Chat.ACPSubagent
---@return string
function M.get_label(subagent)
  return subagent.info.title or subagent.info.description or "Subagent"
end

---Write the subagent's summary line, or rewrite it when its title or state changed
---@param chat CodeCompanion.Chat
---@param subagent CodeCompanion.Chat.ACPSubagent
---@return nil
local function render_line(chat, subagent)
  local summary =
    tool_calls.format_summary({ kind = "subagent", detail = M.get_label(subagent), tag = subagent.model }).text
  local status = get_state(subagent).status

  local ui = subagent.ui
  if ui and ui.summary == summary and ui.status == status then
    return
  end

  if ui and ui.line_number then
    local ok, update = pcall(tool_calls.update, chat, {
      icon_id = ui.icon_id,
      line_number = ui.line_number,
      status = status,
      summary = summary,
    })
    if ok and update.is_updated then
      ui.icon_id = update.icon_id or ui.icon_id
      ui.summary = summary
      ui.status = status
      return
    end
  end

  subagent.ui = tool_calls.write(chat, { call_id = subagent.info.id, status = status, summary = summary })
  subagent.ui.summary = summary
  subagent.ui.status = status
end

---@param chat CodeCompanion.Chat
---@param subagent CodeCompanion.Chat.ACPSubagent
---@return boolean
local function can_cancel(chat, subagent)
  local connection = chat.acp_connection
  return connection ~= nil and connection:can_cancel_subagent(subagent.info.id)
end

---Show a cancelled subagent's unfinished tool calls as cancelled, ahead of the agent reporting each one
---@param subagent CodeCompanion.Chat.ACPSubagent
---@return nil
local function cancel_tool_calls(subagent)
  for _, call in pairs(subagent.tool_calls) do
    if call.status ~= "completed" and call.status ~= "failed" then
      call.status = "cancelled"
    end
  end
end

---Redraw an open float, coalescing the many updates a streaming subagent sends
---@param chat CodeCompanion.Chat
---@param subagent CodeCompanion.Chat.ACPSubagent
---@return nil
local function refresh_float(chat, subagent)
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
local function refresh_floats(chat, subagent)
  while subagent do
    refresh_float(chat, subagent)
    subagent = chat.subagents[subagent.info.parent_id]
  end
end

---Record a subagent the agent announced or patched, showing a line in the chat for a top-level one
---@param chat CodeCompanion.Chat
---@param opts { subagent: table }
---@return nil
function M.update(chat, opts)
  local info = opts.subagent
  local subagent = chat.subagents[info.id]

  if not subagent then
    subagent = { info = info, transcript = {}, tool_calls = {}, order = vim.tbl_count(chat.subagents) + 1 }
    chat.subagents[info.id] = subagent
  end
  subagent.info = info
  subagent.disconnected = nil
  if type(info.state) == "table" and info.state.state == "idle" and info.state.stopReason == "cancelled" then
    cancel_tool_calls(subagent)
  end
  refresh_floats(chat, subagent)

  local parent = chat.subagents[info.parent_id]
  if parent then
    local is_listed = vim.iter(parent.transcript):any(function(item)
      return item.type == "subagent" and item.id == info.id
    end)
    if not is_listed then
      table.insert(parent.transcript, { type = "subagent", id = info.id })
    end
    return
  end

  render_line(chat, subagent)
end

---Stop presenting any subagent's work state as current, after a session load or once the agent's process has gone
---@param chat CodeCompanion.Chat
---@param opts? { is_disconnected?: boolean }
---@return nil
function M.invalidate(chat, opts)
  opts = opts or {}
  for _, subagent in pairs(chat.subagents) do
    subagent.info.state = nil
    subagent.disconnected = opts.is_disconnected or nil
    refresh_float(chat, subagent)
    if not chat.subagents[subagent.info.parent_id] then
      render_line(chat, subagent)
    end
  end
end

---@param content any
---@return string
local function join_text(content)
  local blocks = vim.islist(content) and content or { content }
  local texts = {}
  for _, block in ipairs(blocks) do
    local text = type(block) == "table" and prompt_builder.extract_text(block)
    if text and text ~= "" then
      table.insert(texts, text)
    end
  end
  return table.concat(texts, "")
end

---@param subagent CodeCompanion.Chat.ACPSubagent
---@param message_id string
---@return table
local function find_or_add_message(subagent, message_id)
  local message = vim.iter(subagent.transcript):find(function(item)
    return item.type == "session_message" and item.message_id == message_id
  end)
  if not message then
    message = { type = "session_message", message_id = message_id, text = "" }
    table.insert(subagent.transcript, message)
  end
  return message
end

---Append streamed text to the transcript, extending the last entry when it's of the same type
---@param subagent CodeCompanion.Chat.ACPSubagent
---@param opts { type: "message"|"thought", content: any }
---@return nil
local function append_text(subagent, opts)
  local text = join_text(opts.content)
  local last = subagent.transcript[#subagent.transcript]
  if last and last.type == opts.type then
    last.text = last.text .. text
  else
    table.insert(subagent.transcript, { type = opts.type, text = text })
  end
end

---Apply a `session_message` upsert or a `session_message_chunk` to a stored message
---@param message table
---@param opts { update: table }
---@return nil
local function apply_message_update(message, opts)
  local update = opts.update
  if update.sessionUpdate == "session_message_chunk" then
    message.text = message.text .. join_text(update.content)
    return
  end

  acp.patch({ record = message, update = update, fields = MESSAGE_FIELDS })
  if update.content == vim.NIL then
    message.text = ""
  elseif update.content ~= nil then
    message.text = join_text(update.content)
  end
end

local SESSION_UPDATES = {
  agent_message_chunk = function(subagent, update)
    append_text(subagent, { type = "message", content = update.content })
  end,
  agent_thought_chunk = function(subagent, update)
    append_text(subagent, { type = "thought", content = update.content })
  end,
  plan = function(subagent, update)
    subagent.plan = update.entries
  end,
  usage_update = function(subagent, update)
    subagent.usage = { used = update.used, size = update.size }
  end,
  tool_call = function(subagent, update)
    local id = update.toolCallId
    if not subagent.tool_calls[id] then
      table.insert(subagent.transcript, { type = "tool_call", id = id })
    end
    subagent.tool_calls[id] = handler.merge_tool_call({ existing = subagent.tool_calls[id], incoming = update })
  end,
  session_message = function(subagent, update)
    apply_message_update(find_or_add_message(subagent, update.messageId), { update = update })
  end,
  config_option_update = function(subagent, update)
    local option = vim.iter(update.configOptions or {}):find(function(item)
      return item.category == "model"
    end)
    if not option then
      subagent.model = nil
      return
    end
    local selected = vim.iter(acp.flatten_config_options(option.options or {})):find(function(item)
      return item.value == option.currentValue
    end)
    subagent.model = selected and selected.name or option.currentValue
  end,
}
SESSION_UPDATES.tool_call_update = SESSION_UPDATES.tool_call
SESSION_UPDATES.session_message_chunk = SESSION_UPDATES.session_message

---Record an update from a subagent's own session, for its transcript
---@param chat CodeCompanion.Chat
---@param opts { session_id: string, update: table }
---@return nil
function M.handle_session_update(chat, opts)
  local subagent = chat.subagents[opts.session_id]
  local apply_update = SESSION_UPDATES[opts.update.sessionUpdate]
  if not subagent or not apply_update then
    return
  end

  apply_update(subagent, opts.update)
  refresh_floats(chat, subagent)
  if opts.update.sessionUpdate == "config_option_update" and not chat.subagents[subagent.info.parent_id] then
    render_line(chat, subagent)
  end
end

---Record the ACP session's message to one of its subagents, for that subagent's float
---@param chat CodeCompanion.Chat
---@param opts { update: table }
---@return nil
function M.handle_parent_message(chat, opts)
  local update = opts.update
  local message = chat.messages_to_subagents[update.messageId] or { message_id = update.messageId, text = "" }
  chat.messages_to_subagents[update.messageId] = message
  apply_message_update(message, { update = update })

  -- A message can stream before the agent names its recipient, so it joins a transcript once that's known
  local recipient = chat.subagents[message.recipientSessionId]
  if not recipient then
    return
  end
  if not message.is_listed then
    message.is_listed = true
    table.insert(recipient.transcript, { type = "parent_message", message_id = message.message_id })
  end
  refresh_float(chat, recipient)
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
  return fmt("%s %s", direction, other and M.get_label(other) or "another session")
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
    return { fmt("- **Subagent** %s (%s)", M.get_label(nested), get_state(nested).description) }
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

  if subagent.info.description and subagent.info.description ~= M.get_label(subagent) then
    vim.list_extend(lines, { fmt("_%s_", subagent.info.description), "" })
  end
  table.insert(lines, fmt("**State** %s", get_state(subagent).description))
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

  return { lines = lines, title = M.get_label(subagent) }
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
    if not (connection and connection:cancel_subagent(subagent.info.id)) then
      return utils.notify("The agent doesn't allow this subagent to be cancelled", vim.log.levels.WARN)
    end
    cancel_tool_calls(subagent)
    refresh_float(chat, subagent)
  end, { buffer = bufnr, desc = "Cancel the subagent", nowait = true, silent = true })
end

---List the chat's subagents in the order they were announced, each followed by the subagents it started
---@param chat CodeCompanion.Chat
---@return { subagent: CodeCompanion.Chat.ACPSubagent, depth: number }[]
function M.list(chat)
  local listed = {}

  local function add(subagent, depth)
    table.insert(listed, { subagent = subagent, depth = depth })
    for _, item in ipairs(subagent.transcript) do
      if item.type == "subagent" and chat.subagents[item.id] then
        add(chat.subagents[item.id], depth + 1)
      end
    end
  end

  local top_level = vim.tbl_filter(function(subagent)
    return not chat.subagents[subagent.info.parent_id]
  end, vim.tbl_values(chat.subagents))
  table.sort(top_level, function(a, b)
    return a.order < b.order
  end)
  for _, subagent in ipairs(top_level) do
    add(subagent, 0)
  end

  return listed
end

---Pick one of the chat's subagents and open its float
---@param chat CodeCompanion.Chat
---@return nil
function M.pick(chat)
  local items = vim.tbl_map(function(entry)
    local subagent = entry.subagent
    local name = string.rep("  ", entry.depth) .. M.get_label(subagent)
    if subagent.model then
      name = fmt("%s (%s)", name, subagent.model)
    end
    return {
      callback = function()
        -- The picker hands focus back to the chat as it closes, which would close a float opened straight away
        vim.schedule(function()
          M.open(chat, { subagent = subagent })
        end)
      end,
      description = get_state(subagent).description,
      name = name,
    }
  end, M.list(chat))

  require("codecompanion.action_palette").launch_picker(items, {
    columns = { "name", "description" },
    context = require("codecompanion.utils.context").get(chat.bufnr),
    title = "Subagents",
  })
end

return M
