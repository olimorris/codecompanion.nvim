local Editing = require("codecompanion.interactions.chat.context_management.editing")
local h = require("tests.helpers")

local T = MiniTest.new_set()

local function user_msg(cycle, content)
  return {
    role = "user",
    content = content or "Hello",
    _meta = { cycle = cycle, id = 1 },
    opts = { visible = true },
  }
end

local function llm_msg(cycle, content)
  return {
    role = "llm",
    content = content or "Sure thing",
    _meta = { cycle = cycle, id = 2 },
    opts = { visible = true },
  }
end

local function tool_call_msg(cycle, calls)
  return {
    role = "llm",
    content = "",
    _meta = { cycle = cycle, id = 3 },
    opts = { visible = false },
    tools = { calls = calls },
  }
end

local function tool_call(id, name, args)
  return {
    id = id,
    type = "function",
    ["function"] = { name = name, arguments = args or "{}" },
  }
end

local function tool_result_msg(cycle, call_id, content)
  return {
    role = "tool",
    content = content or "result body",
    _meta = { cycle = cycle, id = math.random(1e9) },
    opts = { visible = true },
    tools = { call_id = call_id, is_error = false, type = "tool_result" },
  }
end

T["Editing"] = MiniTest.new_set()

T["Editing"]["empty input is a no-op"] = function()
  local messages, cleared = Editing.apply({}, { current_cycle = 1, keep_cycles = 3 })
  h.eq({}, messages)
  h.eq(0, cleared)
end

T["Editing"]["leaves messages alone when there are no tool results"] = function()
  local messages = { user_msg(1), llm_msg(1), user_msg(2), llm_msg(2) }
  local before = vim.deepcopy(messages)
  local _, cleared = Editing.apply(messages, { current_cycle = 5, keep_cycles = 3 })
  h.eq(before, messages)
  h.eq(0, cleared)
end

T["Editing"]["keeps tool results within the keep_cycles window"] = function()
  -- 3 cycles, keep_cycles = 3, current = 3 → cutoff = 0 → keep everything
  local messages = {
    user_msg(1),
    tool_call_msg(1, { tool_call("c1", "read_file") }),
    tool_result_msg(1, "c1", "file contents 1"),
    user_msg(2),
    tool_call_msg(2, { tool_call("c2", "read_file") }),
    tool_result_msg(2, "c2", "file contents 2"),
    user_msg(3),
    tool_call_msg(3, { tool_call("c3", "read_file") }),
    tool_result_msg(3, "c3", "file contents 3"),
  }
  local before = vim.deepcopy(messages)
  local _, cleared = Editing.apply(messages, { current_cycle = 3, keep_cycles = 3 })
  h.eq(0, cleared)
  h.eq(before, messages)
end

T["Editing"]["clears tool results outside the keep_cycles window"] = function()
  -- current = 8, keep_cycles = 3 → keep 6,7,8 / clean 1..5
  local messages = {
    tool_call_msg(1, { tool_call("c1", "read_file") }),
    tool_result_msg(1, "c1", "old result 1"),
    tool_call_msg(5, { tool_call("c5", "read_file") }),
    tool_result_msg(5, "c5", "old result 5"),
    tool_call_msg(6, { tool_call("c6", "read_file") }),
    tool_result_msg(6, "c6", "kept result 6"),
    tool_call_msg(8, { tool_call("c8", "read_file") }),
    tool_result_msg(8, "c8", "kept result 8"),
  }
  local _, cleared = Editing.apply(messages, { current_cycle = 8, keep_cycles = 3 })
  h.eq(2, cleared)
  h.eq(Editing.PLACEHOLDERS.tool_result, messages[2].content)
  h.eq(Editing.PLACEHOLDERS.tool_result, messages[4].content)
  h.eq("kept result 6", messages[6].content)
  h.eq("kept result 8", messages[8].content)
end

T["Editing"]["preserves excluded tools regardless of cycle"] = function()
  local messages = {
    tool_call_msg(1, { tool_call("c1", "memory") }),
    tool_result_msg(1, "c1", "memory output"),
    tool_call_msg(1, { tool_call("c2", "read_file") }),
    tool_result_msg(1, "c2", "file output"),
  }
  local _, cleared = Editing.apply(messages, {
    current_cycle = 8,
    keep_cycles = 3,
    exclude_tools = { "memory" },
  })
  h.eq(1, cleared)
  h.eq("memory output", messages[2].content)
  h.eq(Editing.PLACEHOLDERS.tool_result, messages[4].content)
end

T["Editing"]["never touches tool calls, only results"] = function()
  local call_msg = tool_call_msg(1, { tool_call("c1", "read_file") })
  local messages = { call_msg, tool_result_msg(1, "c1", "result") }
  local before_calls = vim.deepcopy(call_msg.tools.calls)
  Editing.apply(messages, { current_cycle = 8, keep_cycles = 3 })
  h.eq(before_calls, messages[1].tools.calls)
  h.eq("", messages[1].content)
end

T["Editing"]["leaves user/llm content untouched even when aged"] = function()
  local messages = {
    user_msg(1, "an ancient prompt"),
    llm_msg(1, "an ancient reply"),
    tool_call_msg(1, { tool_call("c1", "read_file") }),
    tool_result_msg(1, "c1", "ancient tool output"),
  }
  local _, cleared = Editing.apply(messages, { current_cycle = 10, keep_cycles = 3 })
  h.eq(1, cleared)
  h.eq("an ancient prompt", messages[1].content)
  h.eq("an ancient reply", messages[2].content)
  h.eq(Editing.PLACEHOLDERS.tool_result, messages[4].content)
end

T["Editing"]["marks edited messages and skips them on re-run"] = function()
  local messages = {
    tool_call_msg(1, { tool_call("c1", "read_file") }),
    tool_result_msg(1, "c1", "result"),
  }
  local _, first = Editing.apply(messages, { current_cycle = 8, keep_cycles = 3 })
  h.eq(1, first)
  h.is_true(messages[2]._meta.context_management.edited)

  -- Mutate to look like a re-edit attempt with the same placeholder
  local _, second = Editing.apply(messages, { current_cycle = 8, keep_cycles = 3 })
  h.eq(0, second)
end

T["Editing"]["skips tool results without a cycle (defensive)"] = function()
  local result = tool_result_msg(1, "c1", "result")
  result._meta.cycle = nil
  local messages = { tool_call_msg(1, { tool_call("c1", "read_file") }), result }
  local _, cleared = Editing.apply(messages, { current_cycle = 8, keep_cycles = 3 })
  h.eq(0, cleared)
  h.eq("result", result.content)
end

T["Editing"]["updates estimated_tokens when content is replaced"] = function()
  local messages = {
    tool_call_msg(1, { tool_call("c1", "read_file") }),
    tool_result_msg(1, "c1", string.rep("x ", 500)),
  }
  messages[2]._meta.estimated_tokens = 9999
  Editing.apply(messages, { current_cycle = 8, keep_cycles = 3 })
  h.not_eq(9999, messages[2]._meta.estimated_tokens)
end

return T
