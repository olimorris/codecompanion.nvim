local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        _G.chat = h.setup_chat_buffer()
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["ACP Render"] = new_set()

T["ACP Render"]["restores an agent reply with the buffer ready for input"] = function()
  local result = child.lua([[
    require("codecompanion.interactions.chat.acp.render").restore_session(_G.chat, {
      { update = { sessionUpdate = "user_message_chunk", content = { type = "text", text = "hello" } } },
      { update = { sessionUpdate = "agent_message_chunk", content = { type = "text", text = "hi there" } } },
    })
    -- A streamed chunk left in the queue is flushed on a timer, which locks the buffer
    vim.wait(1000, function() return _G.chat.builder._queue == nil end)

    return {
      modifiable = vim.bo[_G.chat.bufnr].modifiable,
      lines = h.get_buf_lines(_G.chat.bufnr),
    }
  ]])

  h.eq(true, result.modifiable)
  h.eq({ "## foo", "", "hello", "", "## assistant", "", "hi there", "", "## foo", "", "" }, result.lines)
end

T["ACP Render"]["restores the subagents a session started, as clearing the chat would wipe them"] = function()
  local result = child.lua([[
    local connection = { session_id = "sess_parent", chat = _G.chat }
    connection.subagents = require("codecompanion.acp.subagents").new({ connection = connection })
    _G.chat.acp_connection = connection

    local updates = {}
    connection._on_session_update = function(update, opts)
      table.insert(updates, { update = update, session_id = opts and opts.session_id })
    end
    local function replay(session_id, update)
      if not connection.subagents:handle({ session_id = session_id, update = update, is_replayed = true }) then
        table.insert(updates, { update = update })
      end
    end

    replay("sess_parent", { sessionUpdate = "user_message_chunk", content = { type = "text", text = "count files" } })
    replay("sess_parent", { sessionUpdate = "subagent_update", sessionId = "sess_child", title = "Count files" })
    replay("sess_child", { sessionUpdate = "agent_message_chunk", content = { type = "text", text = "Found 3" } })
    require("codecompanion.interactions.chat.acp.render").restore_session(_G.chat, updates)

    local subagent = _G.chat.subagents["sess_child"]
    _G.chat.acp_connection = nil
    return {
      has_line = vim.tbl_contains(h.get_buf_lines(_G.chat.bufnr), "**Subagent** Count files"),
      transcript = subagent and subagent.transcript,
    }
  ]])

  h.eq(true, result.has_line)
  h.eq({ { type = "message", text = "Found 3" } }, result.transcript)
end

return T
