local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        chat = h.setup_chat_buffer()
        permissions = chat.acp_permissions

        confirmed = {}
        package.loaded["codecompanion.interactions.chat.acp.request_permission"] = {
          confirm = function(_, request)
            table.insert(confirmed, request)
          end,
        }

        cancelled = {}
        function add_request(opts)
          permissions:push({
            is_pending = opts.is_pending or function() return true end,
            session_id = opts.session_id,
            tool_call = { toolCallId = opts.id },
            options = {},
            respond = function(_, is_cancelled)
              if is_cancelled then
                table.insert(cancelled, opts.id)
              end
            end,
          })
        end

        function get_confirmed_ids()
          return vim.tbl_map(function(request) return request.tool_call.toolCallId end, confirmed)
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["Permissions"] = new_set()

T["Permissions"]["asks about one request at a time"] = function()
  local result = child.lua([[
    for _, id in ipairs({ "tool_1", "tool_2", "tool_3" }) do
      add_request({ id = id })
    end
    local first = get_confirmed_ids()
    confirmed[1].respond("allow", false)
    return { first = first, after_answer = get_confirmed_ids(), queued = permissions.queue:count() }
  ]])
  h.eq(result.first, { "tool_1" })
  h.eq(result.after_answer, { "tool_1", "tool_2" })
  h.eq(result.queued, 1)
end

T["Permissions"]["SKIPS a request that was answered while it waited"] = function()
  local result = child.lua([[
    for _, id in ipairs({ "tool_1", "tool_2", "tool_3" }) do
      add_request({ id = id, is_pending = function() return id ~= "tool_2" end })
    end
    confirmed[1].respond("allow", false)
    return get_confirmed_ids()
  ]])
  h.eq(result, { "tool_1", "tool_3" })
end

T["Permissions"]["KEEPS a subagent's request when the turn is cancelled"] = function()
  local result = child.lua([[
    chat.subagents["sess_child"] = { info = { id = "sess_child" }, tool_calls = {}, transcript = {} }
    add_request({ id = "parent_1", session_id = "sess_parent" })
    add_request({ id = "child_1", session_id = "sess_child" })
    add_request({ id = "parent_2", session_id = "sess_parent" })
    permissions:cancel_turn()
    return { cancelled = cancelled, confirmed = get_confirmed_ids(), active = permissions.active }
  ]])
  h.eq(result.cancelled, { "parent_1", "parent_2" })
  h.eq(result.confirmed, { "parent_1", "child_1" })
  h.is_true(result.active)
end

T["Permissions"]["fills in a request's tool call from the ANNOUNCED one"] = function()
  local result = child.lua([[
    chat.tool_calls.acp["call_001"] = {
      toolCallId = "call_001",
      kind = "edit",
      content = { { type = "diff", path = "/tmp/file.txt", oldText = "old", newText = "new" } },
    }
    add_request({ id = "call_001" })
    return confirmed[1].tool_call.content[1].newText
  ]])
  h.eq(result, "new")
end

T["Permissions"]["looks up a subagent's request in the SUBAGENT'S tool calls"] = function()
  local result = child.lua([[
    chat.tool_calls.acp["call_001"] = { toolCallId = "call_001", title = "Parent's call" }
    chat.subagents["sess_child"] = {
      info = { id = "sess_child" },
      tool_calls = { call_001 = { toolCallId = "call_001", title = "Subagent's call" } },
      transcript = {},
    }
    add_request({ id = "call_001", session_id = "sess_child" })
    return { title = confirmed[1].tool_call.title, parent_title = chat.tool_calls.acp["call_001"].title }
  ]])
  h.eq(result, { title = "Subagent's call", parent_title = "Parent's call" })
end

return T
