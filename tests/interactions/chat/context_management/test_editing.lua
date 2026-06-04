local Editing = require("codecompanion.interactions.chat.context_management.editing")
local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set()

T["Editing"] = MiniTest.new_set()

T["Editing"]["returns empty input unchanged"] = function()
  local messages, cleared = Editing.apply({}, { current_cycle = 1, keep_cycles = 3 })
  h.eq({}, messages)
  h.eq(0, cleared)
end

T["Editing"]["leaves messages alone when there are no tool results"] = function()
  local messages = {
    { role = "user", content = "Hello", _meta = { cycle = 1, id = 1 }, opts = { visible = true } },
    { role = "llm", content = "Sure thing", _meta = { cycle = 1, id = 2 }, opts = { visible = true } },
    { role = "user", content = "Hello", _meta = { cycle = 2, id = 1 }, opts = { visible = true } },
    { role = "llm", content = "Sure thing", _meta = { cycle = 2, id = 2 }, opts = { visible = true } },
  }
  local before = vim.deepcopy(messages)
  local _, cleared = Editing.apply(messages, { current_cycle = 5, keep_cycles = 3 })
  h.eq(before, messages)
  h.eq(0, cleared)
end

T["Editing"]["keeps tool results within the keep_cycles window"] = function()
  -- 3 cycles, keep_cycles = 3, current = 3 → cutoff = 0 → keep everything
  local messages = {
    { role = "user", content = "Hello", _meta = { cycle = 1, id = 1 }, opts = { visible = true } },
    {
      role = "llm",
      content = "",
      _meta = { cycle = 1, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = "file contents 1",
      _meta = { cycle = 1, id = 10 },
      opts = { visible = true },
      tools = { call_id = "c1", is_error = false, type = "tool_result" },
    },
    { role = "user", content = "Hello", _meta = { cycle = 2, id = 1 }, opts = { visible = true } },
    {
      role = "llm",
      content = "",
      _meta = { cycle = 2, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c2", type = "function", ["function"] = { name = "read_file", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = "file contents 2",
      _meta = { cycle = 2, id = 11 },
      opts = { visible = true },
      tools = { call_id = "c2", is_error = false, type = "tool_result" },
    },
    { role = "user", content = "Hello", _meta = { cycle = 3, id = 1 }, opts = { visible = true } },
    {
      role = "llm",
      content = "",
      _meta = { cycle = 3, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c3", type = "function", ["function"] = { name = "read_file", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = "file contents 3",
      _meta = { cycle = 3, id = 12 },
      opts = { visible = true },
      tools = { call_id = "c3", is_error = false, type = "tool_result" },
    },
  }
  local before = vim.deepcopy(messages)
  local _, cleared = Editing.apply(messages, { current_cycle = 3, keep_cycles = 3 })
  h.eq(0, cleared)
  h.eq(before, messages)
end

T["Editing"]["clears tool results outside the keep_cycles window"] = function()
  -- current = 8, keep_cycles = 3 → keep 6,7,8 / clean 1..5
  local messages = {
    {
      role = "llm",
      content = "",
      _meta = { cycle = 1, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = "old result 1",
      _meta = { cycle = 1, id = 10 },
      opts = { visible = true },
      tools = { call_id = "c1", is_error = false, type = "tool_result" },
    },
    {
      role = "llm",
      content = "",
      _meta = { cycle = 5, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c5", type = "function", ["function"] = { name = "read_file", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = "old result 5",
      _meta = { cycle = 5, id = 11 },
      opts = { visible = true },
      tools = { call_id = "c5", is_error = false, type = "tool_result" },
    },
    {
      role = "llm",
      content = "",
      _meta = { cycle = 6, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c6", type = "function", ["function"] = { name = "read_file", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = "kept result 6",
      _meta = { cycle = 6, id = 12 },
      opts = { visible = true },
      tools = { call_id = "c6", is_error = false, type = "tool_result" },
    },
    {
      role = "llm",
      content = "",
      _meta = { cycle = 8, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c8", type = "function", ["function"] = { name = "read_file", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = "kept result 8",
      _meta = { cycle = 8, id = 13 },
      opts = { visible = true },
      tools = { call_id = "c8", is_error = false, type = "tool_result" },
    },
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
    {
      role = "llm",
      content = "",
      _meta = { cycle = 1, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c1", type = "function", ["function"] = { name = "memory", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = "memory output",
      _meta = { cycle = 1, id = 10 },
      opts = { visible = true },
      tools = { call_id = "c1", is_error = false, type = "tool_result" },
    },
    {
      role = "llm",
      content = "",
      _meta = { cycle = 1, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c2", type = "function", ["function"] = { name = "read_file", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = "file output",
      _meta = { cycle = 1, id = 11 },
      opts = { visible = true },
      tools = { call_id = "c2", is_error = false, type = "tool_result" },
    },
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
  local messages = {
    {
      role = "llm",
      content = "",
      _meta = { cycle = 1, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = "result",
      _meta = { cycle = 1, id = 10 },
      opts = { visible = true },
      tools = { call_id = "c1", is_error = false, type = "tool_result" },
    },
  }
  local before_calls = vim.deepcopy(messages[1].tools.calls)
  Editing.apply(messages, { current_cycle = 8, keep_cycles = 3 })
  h.eq(before_calls, messages[1].tools.calls)
  h.eq("", messages[1].content)
end

T["Editing"]["leaves user/llm content untouched even when aged"] = function()
  local messages = {
    { role = "user", content = "an ancient prompt", _meta = { cycle = 1, id = 1 }, opts = { visible = true } },
    { role = "llm", content = "an ancient reply", _meta = { cycle = 1, id = 2 }, opts = { visible = true } },
    {
      role = "llm",
      content = "",
      _meta = { cycle = 1, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = "ancient tool output",
      _meta = { cycle = 1, id = 10 },
      opts = { visible = true },
      tools = { call_id = "c1", is_error = false, type = "tool_result" },
    },
  }
  local _, cleared = Editing.apply(messages, { current_cycle = 10, keep_cycles = 3 })
  h.eq(1, cleared)
  h.eq("an ancient prompt", messages[1].content)
  h.eq("an ancient reply", messages[2].content)
  h.eq(Editing.PLACEHOLDERS.tool_result, messages[4].content)
end

T["Editing"]["marks edited messages and skips them on re-run"] = function()
  local messages = {
    {
      role = "llm",
      content = "",
      _meta = { cycle = 1, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = "result",
      _meta = { cycle = 1, id = 10 },
      opts = { visible = true },
      tools = { call_id = "c1", is_error = false, type = "tool_result" },
    },
  }
  local _, first = Editing.apply(messages, { current_cycle = 8, keep_cycles = 3 })
  h.eq(1, first)
  h.is_true(messages[2]._meta.context_management.edited)

  -- Re-run on already-edited messages skips them
  local _, second = Editing.apply(messages, { current_cycle = 8, keep_cycles = 3 })
  h.eq(0, second)
end

T["Editing"]["skips tool results without a cycle (defensive)"] = function()
  local messages = {
    {
      role = "llm",
      content = "",
      _meta = { cycle = 1, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = "result",
      _meta = { id = 10 },
      opts = { visible = true },
      tools = { call_id = "c1", is_error = false, type = "tool_result" },
    },
  }
  local _, cleared = Editing.apply(messages, { current_cycle = 8, keep_cycles = 3 })
  h.eq(0, cleared)
  h.eq("result", messages[2].content)
end

T["Editing"]["updates estimated_tokens when content is replaced"] = function()
  local messages = {
    {
      role = "llm",
      content = "",
      _meta = { cycle = 1, id = 3 },
      opts = { visible = false },
      tools = { calls = { { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } } } },
    },
    {
      role = "tool",
      content = string.rep("x ", 500),
      _meta = { cycle = 1, id = 10, estimated_tokens = 9999 },
      opts = { visible = true },
      tools = { call_id = "c1", is_error = false, type = "tool_result" },
    },
  }
  Editing.apply(messages, { current_cycle = 8, keep_cycles = 3 })
  h.not_eq(9999, messages[2]._meta.estimated_tokens)
end

T["Editing.integration"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
    end,
    post_once = child.stop,
  },
})

T["Editing.integration"]["multi-cycle chat history"] = function()
  child.lua([==[
    local Editing = require("codecompanion.interactions.chat.context_management.editing")
    local tokens = require("codecompanion.utils.tokens")
    local placeholder = Editing.PLACEHOLDERS.tool_result
    local placeholder_tokens = tokens.calculate(placeholder)
    local long_file = string.rep("file contents line\n", 100)

    _G.messages = {
    -- [1] cycle 1: user prompt
    {
      _meta = { cycle = 1, id = 101 },
      content = "Can you find lua files and do a grep search for `function`",
      opts = { visible = true },
      role = "user",
    },
    -- [2] cycle 1: llm text
    {
      _meta = { cycle = 1, id = 102 },
      content = "I'll search for those.",
      opts = { visible = true },
      role = "llm",
    },
    -- [3] cycle 1: llm fires two tool calls at once
    {
      _meta = { cycle = 1, id = 103 },
      content = "",
      opts = { visible = false },
      role = "llm",
      tools = {
        calls = {
          {
            id = "c1a",
            type = "function",
            ["function"] = { arguments = '{"pattern":"*.lua"}', name = "file_search" },
          },
          {
            id = "c1b",
            type = "function",
            ["function"] = { arguments = '{"pattern":"function"}', name = "grep_search" },
          },
        },
      },
    },
    -- [4] cycle 1: tool result for c1a (will be edited)
    {
      _meta = { cycle = 1, id = 104 },
      content = "init.lua\nutils.lua\nconfig.lua",
      opts = { visible = true },
      role = "tool",
      tools = { call_id = "c1a", is_error = false, type = "tool_result" },
    },
    -- [5] cycle 1: tool result for c1b (will be edited)
    {
      _meta = { cycle = 1, id = 105 },
      content = "init.lua:1 function setup",
      opts = { visible = true },
      role = "tool",
      tools = { call_id = "c1b", is_error = false, type = "tool_result" },
    },

    -- [6] cycle 2: user prompt
    {
      _meta = { cycle = 2, id = 201 },
      content = "Read init.lua",
      opts = { visible = true },
      role = "user",
    },
    -- [7] cycle 2: llm text
    {
      _meta = { cycle = 2, id = 202 },
      content = "Reading init.lua now.",
      opts = { visible = true },
      role = "llm",
    },
    -- [8] cycle 2: llm tool call
    {
      _meta = { cycle = 2, id = 203 },
      content = "",
      opts = { visible = false },
      role = "llm",
      tools = {
        calls = {
          {
            id = "c2",
            type = "function",
            ["function"] = { arguments = '{"path":"init.lua"}', name = "read_file" },
          },
        },
      },
    },
    -- [9] cycle 2: tool result (will be edited)
    {
      _meta = { cycle = 2, id = 204 },
      content = long_file,
      opts = { visible = true },
      role = "tool",
      tools = { call_id = "c2", is_error = false, type = "tool_result" },
    },

    -- [10] cycle 3: user prompt
    {
      _meta = { cycle = 3, id = 301 },
      content = "Remember that init.lua is the entry point",
      opts = { visible = true },
      role = "user",
    },
    -- [11] cycle 3: llm tool call to the memory tool
    {
      _meta = { cycle = 3, id = 302 },
      content = "",
      opts = { visible = false },
      role = "llm",
      tools = {
        calls = {
          {
            id = "c3",
            type = "function",
            ["function"] = { arguments = '{"note":"init is entry"}', name = "memory" },
          },
        },
      },
    },
    -- [12] cycle 3: tool result for memory (excluded, will survive)
    {
      _meta = { cycle = 3, id = 303 },
      content = "Saved: init is entry",
      opts = { visible = true },
      role = "tool",
      tools = { call_id = "c3", is_error = false, type = "tool_result" },
    },

    -- [13] cycle 4: user prompt
    {
      _meta = { cycle = 4, id = 401 },
      content = "Grep for `require`",
      opts = { visible = true },
      role = "user",
    },
    -- [14] cycle 4: llm tool call
    {
      _meta = { cycle = 4, id = 402 },
      content = "",
      opts = { visible = false },
      role = "llm",
      tools = {
        calls = {
          {
            id = "c4",
            type = "function",
            ["function"] = { arguments = '{"pattern":"require"}', name = "grep_search" },
          },
        },
      },
    },
    -- [15] cycle 4: tool result (kept by keep_cycles)
    {
      _meta = { cycle = 4, id = 403 },
      content = "matches in 12 files",
      opts = { visible = true },
      role = "tool",
      tools = { call_id = "c4", is_error = false, type = "tool_result" },
    },

    -- [16] cycle 5: user prompt
    {
      _meta = { cycle = 5, id = 501 },
      content = "What does that file do?",
      opts = { visible = true },
      role = "user",
    },
    -- [17] cycle 5: llm text only
    {
      _meta = { cycle = 5, id = 502 },
      content = "It bootstraps the plugin.",
      opts = { visible = true },
      role = "llm",
    },

    -- [18] cycle 6: user prompt
    {
      _meta = { cycle = 6, id = 601 },
      content = "Read it once more",
      opts = { visible = true },
      role = "user",
    },
    -- [19] cycle 6: llm tool call
    {
      _meta = { cycle = 6, id = 602 },
      content = "",
      opts = { visible = false },
      role = "llm",
      tools = {
        calls = {
          {
            id = "c6",
            type = "function",
            ["function"] = { arguments = '{"path":"init.lua"}', name = "read_file" },
          },
        },
      },
    },
    -- [20] cycle 6: tool result (kept by keep_cycles)
    {
      _meta = { cycle = 6, id = 603 },
      content = "fresh contents",
      opts = { visible = true },
      role = "tool",
      tools = { call_id = "c6", is_error = false, type = "tool_result" },
    },
  }

    -- Build the expected post-edit state by snapshotting input and mutating
    -- only the tool results we expect to be cleared (cycles 1-2; cycle 3's
    -- memory result is excluded; cycles 4-6 are kept by keep_cycles).
    _G.expected = vim.deepcopy(_G.messages)
    for _, idx in ipairs({ 4, 5, 9 }) do
      _G.expected[idx].content = placeholder
      _G.expected[idx]._meta.estimated_tokens = placeholder_tokens
      _G.expected[idx]._meta.context_management = { edited = true }
    end

    _G.first_cleared = select(2, Editing.apply(_G.messages, {
      current_cycle = 6,
      exclude_tools = { "memory" },
      keep_cycles = 3,
    }))

    -- Re-running on the same chat clears nothing — already-edited results are skipped
    _G.second_cleared = select(2, Editing.apply(_G.messages, {
      current_cycle = 6,
      exclude_tools = { "memory" },
      keep_cycles = 3,
    }))
  ]==])

  h.eq(3, child.lua_get("_G.first_cleared"))
  h.eq(0, child.lua_get("_G.second_cleared"))
  h.eq(child.lua_get("_G.expected"), child.lua_get("_G.messages"))
end

return T
