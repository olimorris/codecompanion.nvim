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
        subagents = require("codecompanion.interactions.chat.acp.subagents")
        float = require("codecompanion.interactions.chat.acp.subagents.float")

        function update(fields)
          subagents.update(chat, {
            subagent = vim.tbl_extend("force", { id = "sess_child", parent_id = "sess_parent" }, fields or {}),
          })
        end

        function count_lines(pattern)
          local count = 0
          for _, line in ipairs(vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false)) do
            if line:find(pattern, 1, true) then
              count = count + 1
            end
          end
          return count
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["Subagents"] = new_set()

T["Subagents"]["shows a top-level subagent as one line that updates in place"] = function()
  local result = child.lua([[
    update({ title = "Test investigator", state = { state = "running" } })
    update({ title = "Test investigator", state = { state = "idle", stopReason = "end_turn" } })
    return { lines = count_lines("**Subagent** Test investigator"), status = chat.subagents["sess_child"].ui.status }
  ]])
  h.eq(result.lines, 1)
  h.eq(result.status, "completed")
end

T["Subagents"]["DOES NOT show a NESTED subagent in the chat"] = function()
  local result = child.lua([[
    update({ title = "Coordinator" })
    subagents.update(chat, { subagent = { id = "sess_worker", parent_id = "sess_child", title = "Worker" } })
    return { lines = count_lines("Worker"), transcript = chat.subagents["sess_child"].transcript }
  ]])
  h.eq(result.lines, 0)
  h.eq(result.transcript, { { type = "subagent", id = "sess_worker" } })
end

T["Subagents"]["formats the transcript for the float"] = function()
  local result = child.lua([[
    update({ title = "Test investigator", description = "Investigates failing tests", state = { state = "running" } })
    local function session_update(update)
      subagents.handle_session_update(chat, { session_id = "sess_child", update = update })
    end
    session_update({
      sessionUpdate = "session_message",
      messageId = "msg_1",
      senderSessionId = "sess_parent",
      content = { { type = "text", text = "Find out why the tests fail" } },
    })
    session_update({ sessionUpdate = "agent_message_chunk", content = { type = "text", text = "Looking " } })
    session_update({ sessionUpdate = "agent_message_chunk", content = { type = "text", text = "now" } })
    session_update({
      sessionUpdate = "tool_call",
      toolCallId = "call_001",
      title = "Run the tests",
      kind = "execute",
      status = "in_progress",
    })
    session_update({ sessionUpdate = "tool_call_update", toolCallId = "call_001", status = "completed" })
    return float.format(chat, { subagent = chat.subagents["sess_child"] })
  ]])
  h.eq(result.title, "Test investigator")
  h.eq(result.lines[1], "_Investigates failing tests_")
  h.eq(result.lines[3], "**State** running")
  h.eq(result.lines[5], "**From parent**")
  h.eq(result.lines[6], "> Find out why the tests fail")
  h.eq(result.lines[8], "Looking now")
  h.expect_contains("(completed)", result.lines[10])
  h.eq(#result.lines, 10)
end

T["Subagents"]["DOES NOT present a running subagent as running after a disconnect"] = function()
  local result = child.lua([[
    update({ title = "Test investigator", state = { state = "running" } })
    subagents.invalidate(chat, { is_disconnected = true })
    return {
      status = chat.subagents["sess_child"].ui.status,
      state = float.format(chat, { subagent = chat.subagents["sess_child"] }).lines[1],
    }
  ]])
  h.eq(result.status, "pending")
  h.eq(result.state, "**State** Disconnected")
end

T["Subagents"]["shows the subagent's model on its line"] = function()
  local result = child.lua([[
    update({ title = "Count files", state = { state = "running" } })
    subagents.handle_session_update(chat, {
      session_id = "sess_child",
      update = {
        sessionUpdate = "config_option_update",
        configOptions = {
          {
            id = "model",
            category = "model",
            type = "select",
            currentValue = "haiku",
            options = { { value = "haiku", name = "Haiku 5.5" }, { value = "opus", name = "Opus 5.5" } },
          },
        },
      },
    })
    return count_lines("**Subagent** _(Haiku 5.5)_ Count files")
  ]])
  h.eq(result, 1)
end

T["Subagents"]["updates an open float as the subagent works"] = function()
  local result = child.lua([[
    update({ title = "Test investigator", state = { state = "running" } })
    float.open(chat, { subagent = chat.subagents["sess_child"] })
    subagents.handle_session_update(chat, {
      session_id = "sess_child",
      update = { sessionUpdate = "agent_message_chunk", content = { type = "text", text = "Still looking" } },
    })
    local bufnr = chat.subagents["sess_child"].float.bufnr
    vim.wait(1000, function()
      return vim.tbl_contains(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "Still looking")
    end)
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  ]])
  h.eq(result[#result], "Still looking")
end

T["Subagents"]["shows a message the subagent SENT as outgoing"] = function()
  local result = child.lua([[
    update({ title = "Test investigator" })
    subagents.handle_session_update(chat, {
      session_id = "sess_child",
      update = {
        sessionUpdate = "session_message",
        messageId = "msg_1",
        senderSessionId = "sess_child",
        content = { { type = "text", text = "Done" } },
      },
    })
    return float.format(chat, { subagent = chat.subagents["sess_child"] }).lines
  ]])
  h.eq(result[#result - 1], "**To another session**")
end

T["Subagents"]["marks unfinished tool calls as cancelled when the subagent is CANCELLED"] = function()
  local result = child.lua([[
    update({ title = "Test investigator", state = { state = "running" } })
    for id, status in pairs({ call_001 = "completed", call_002 = "in_progress" }) do
      subagents.handle_session_update(chat, {
        session_id = "sess_child",
        update = { sessionUpdate = "tool_call", toolCallId = id, title = "Run the tests", status = status },
      })
    end
    subagents.cancel(chat, { session_id = "sess_child" })
    local calls = chat.subagents["sess_child"].tool_calls
    return { completed = calls.call_001.status, unfinished = calls.call_002.status }
  ]])
  h.eq(result, { completed = "completed", unfinished = "cancelled" })
end

T["Subagents"]["shows a subagent's work state as unconfirmed once invalidated"] = function()
  local result = child.lua([[
    update({ title = "Test investigator", state = { state = "running" } })
    subagents.invalidate(chat)
    return {
      status = chat.subagents["sess_child"].ui.status,
      state = float.format(chat, { subagent = chat.subagents["sess_child"] }).lines[1],
    }
  ]])
  h.eq(result.status, "pending")
  h.eq(result.state, "**State** Unconfirmed")
end

T["Subagents"]["formats thoughts, plan and token usage for the float"] = function()
  local result = child.lua([[
    update({ title = "Test investigator", state = { state = "running" } })
    local function session_update(update)
      subagents.handle_session_update(chat, { session_id = "sess_child", update = update })
    end
    session_update({ sessionUpdate = "agent_thought_chunk", content = { type = "text", text = "Checking CI" } })
    session_update({
      sessionUpdate = "plan",
      entries = {
        { content = "Reproduce the failure", priority = "high", status = "completed" },
        { content = "Fix the test", priority = "high", status = "pending" },
      },
    })
    session_update({ sessionUpdate = "usage_update", used = 1200, size = 200000 })
    return float.format(chat, { subagent = chat.subagents["sess_child"] }).lines
  ]])
  h.eq(result, {
    "**State** running",
    "**Tokens** 1200 of 200000",
    "",
    "**Plan**",
    "- [x] Reproduce the failure",
    "- [ ] Fix the test",
    "",
    "_Thinking_",
    "Checking CI",
  })
end

T["Subagents"]["opens the subagent a tool call REFERENCES"] = function()
  local result = child.lua([[
    update({ title = "Test investigator", state = { state = "running" } })
    chat.tool_calls.acp["call_spawn"] = {
      toolCallId = "call_spawn",
      kind = "other",
      content = { { type = "session", sessionId = "sess_child" } },
    }
    require("codecompanion.interactions.chat.ui.tool_calls").open(chat, { call_id = "call_spawn" })
    return chat.subagents["sess_child"].float ~= nil
  ]])
  h.is_true(result)
end

T["Subagents"]["shows the parent's message in the float"] = function()
  local result = child.lua([[
    update({ title = "Test investigator" })
    subagents.handle_session_update(chat, {
      session_id = "sess_parent",
      update = { sessionUpdate = "session_message", messageId = "msg_to_child", recipientSessionId = "sess_child" },
    })
    subagents.handle_session_update(chat, {
      session_id = "sess_parent",
      update = { sessionUpdate = "session_message_chunk", messageId = "msg_to_child", content = { type = "text", text = "Check Windows" } },
    })
    return float.format(chat, { subagent = chat.subagents["sess_child"] }).lines
  ]])
  h.eq(result[#result - 1], "**Sent by parent**")
  h.eq(result[#result], "> Check Windows")
end

T["Subagents"]["DOES NOT repeat a parent's message the subagent REPORTED"] = function()
  local result = child.lua([[
    update({ title = "Test investigator" })
    subagents.handle_session_update(chat, {
      session_id = "sess_parent",
      update = {
        sessionUpdate = "session_message",
        messageId = "msg_to_child",
        recipientSessionId = "sess_child",
        content = { { type = "text", text = "Check Windows" } },
      },
    })
    subagents.handle_session_update(chat, {
      session_id = "sess_child",
      update = {
        sessionUpdate = "session_message",
        messageId = "msg_from_parent",
        senderSessionId = "sess_parent",
        senderMessageId = "msg_to_child",
        content = { { type = "text", text = "Check Windows" } },
      },
    })
    return float.format(chat, { subagent = chat.subagents["sess_child"] }).lines
  ]])
  h.eq(
    vim.tbl_filter(function(line)
      return line == "> Check Windows"
    end, result),
    { "> Check Windows" }
  )
  h.eq(result[#result - 1], "**From parent**")
end

T["Subagents"]["fires FileEdited for a subagent's FINISHED edit"] = function()
  local result = child.lua([[
    local edited = {}
    vim.api.nvim_create_autocmd("User", {
      pattern = "CodeCompanionFileEdited",
      callback = function(args) table.insert(edited, args.data.path) end,
    })
    update({ title = "Editor", state = { state = "running" } })
    local function session_update(update)
      subagents.handle_session_update(chat, { session_id = "sess_child", update = update })
    end
    session_update({
      sessionUpdate = "tool_call",
      toolCallId = "call_001",
      kind = "edit",
      status = "in_progress",
      locations = { { path = "/tmp/file.lua" } },
    })
    local before = #edited
    session_update({ sessionUpdate = "tool_call_update", toolCallId = "call_001", status = "completed" })
    return { before = before, edited = edited }
  ]])
  h.eq(result, { before = 0, edited = { "/tmp/file.lua" } })
end

return T
