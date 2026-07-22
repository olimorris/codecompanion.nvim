---Convert a Chat snapshot to and from the on-disk JSON form.
---
---The schema version is pinned here. Bump `SCHEMA_VERSION` when the on-disk
---shape changes incompatibly, and add a migrator.

local M = {}

M.SCHEMA_VERSION = 1
M.UI_VERSION = 1

---Build the JSON-serializable table for a session.
---@param snapshot table A Chat snapshot (see Chat:snapshot)
---@param extra { slug: string, created_at?: string, updated_at: string }
---@return table
function M.encode(snapshot, extra)
  return {
    adapter = snapshot.adapter,
    context_items = snapshot.context_items,
    created_at = extra.created_at or extra.updated_at,
    cwd = snapshot.cwd,
    cycle = snapshot.cycle,
    id = snapshot.id,
    messages = snapshot.messages,
    schema_version = M.SCHEMA_VERSION,
    settings = snapshot.settings,
    slug = extra.slug,
    title = snapshot.title,
    ui_version = M.UI_VERSION,
    updated_at = extra.updated_at,
  }
end

---Convert a decoded JSON table into args usable by `Chat.new`.
---Runtime-only message fields (cycle, id, estimated_tokens, sent, index) are
---left for the chat constructor / backfill to recompute.
---@param data table The decoded JSON
---@return table args Suitable for passing to `Chat.new`
function M.to_chat_args(data)
  local messages = {}
  for _, msg in ipairs(data.messages or {}) do
    local entry = {
      role = msg.role,
      content = msg.content,
      reasoning = msg.reasoning,
    }
    if msg.tools then
      entry.tools = msg.tools
    end
    if msg.opts then
      entry.opts = { visible = msg.opts.visible }
    end
    if msg.context then
      entry.context = msg.context
    end
    if msg._meta then
      entry._meta = { tag = msg._meta.tag }
    end
    table.insert(messages, entry)
  end

  return {
    messages = messages,
    settings = data.settings,
    title = data.title,
  }
end

return M
