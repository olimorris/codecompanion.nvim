local float = require("codecompanion.interactions.chat.acp.subagents.float")
local summary = require("codecompanion.interactions.chat.acp.subagents.summary")
local transcript = require("codecompanion.interactions.chat.acp.subagents.transcript")

local fmt = string.format

---@class CodeCompanion.Chat.ACPSubagent
---@field disconnected? boolean
---@field float? { bufnr: number, winnr: number }
---@field info { additionalDirectories?: string[], capabilities?: { cancel?: table }, cwd?: string, description?: string, id: string, parent_id: string, state?: { error?: table, state: string, stopReason?: string }, title?: string }
---@field model? string
---@field order number When the subagent was announced, relative to the chat's others
---@field plan? table[] The subagent's latest plan entries
---@field tool_calls table<string, table> The subagent's tool calls by their ID
---@field transcript table[] Messages, tool calls and nested subagents, in the order they arrived
---@field ui? { icon_id?: number, line_number?: number, status?: string, summary?: string }
---@field usage? { size?: number, used?: number }
---@field _is_refresh_scheduled? boolean

local M = {}

---Record a subagent the agent announced or patched, showing a line in the chat for a top-level one
---@param chat CodeCompanion.Chat
---@param opts { subagent: table }
---@return nil
function M.update(chat, opts)
  local info = vim.deepcopy(opts.subagent)
  local subagent = chat.subagents[info.id]

  if not subagent then
    subagent = { info = info, transcript = {}, tool_calls = {}, order = vim.tbl_count(chat.subagents) + 1 }
    chat.subagents[info.id] = subagent
  end
  subagent.info = info
  subagent.disconnected = nil
  float.refresh_with_ancestors(chat, subagent)

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

  summary.render(chat, subagent)
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
    float.refresh(chat, subagent)
    if not chat.subagents[subagent.info.parent_id] then
      summary.render(chat, subagent)
    end
  end
end

---Record an update from a subagent's session, or a message the chat's own session sent to a subagent
---@param chat CodeCompanion.Chat
---@param opts { session_id: string, update: table }
---@return nil
function M.handle_session_update(chat, opts)
  local subagent = chat.subagents[opts.session_id]
  if not subagent then
    local recipient = transcript.apply_parent_message(chat, { update = opts.update })
    if recipient then
      float.refresh(chat, recipient)
    end
    return
  end
  if not transcript.apply(subagent, { update = opts.update }) then
    return
  end

  float.refresh_with_ancestors(chat, subagent)
  if opts.update.sessionUpdate == "config_option_update" and not chat.subagents[subagent.info.parent_id] then
    summary.render(chat, subagent)
  end
end

---Show a cancelled subagent's unfinished tool calls as cancelled, ahead of the agent reporting each one
---@param chat CodeCompanion.Chat
---@param opts { session_id: string }
---@return nil
function M.cancel(chat, opts)
  local subagent = chat.subagents[opts.session_id]
  if not subagent then
    return
  end
  transcript.cancel_tool_calls(subagent)
  float.refresh(chat, subagent)
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
    local name = string.rep("  ", entry.depth) .. summary.get_label(subagent)
    if subagent.model then
      name = fmt("%s (%s)", name, subagent.model)
    end
    return {
      callback = function()
        -- The picker hands focus back to the chat as it closes, which would close a float opened straight away
        vim.schedule(function()
          float.open(chat, { subagent = subagent })
        end)
      end,
      description = summary.get_state(subagent).description,
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
