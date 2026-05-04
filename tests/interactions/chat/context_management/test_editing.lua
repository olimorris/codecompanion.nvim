local Editing = require("codecompanion.interactions.chat.context_management.editing")
local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()
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

T["Editing"]["returns empty input unchanged"] = function()
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

    _G.first_cleared = select(2, Editing.apply(_G.messages, {
      current_cycle = 6,
      exclude_tools = { "memory" },
      keep_cycles = 3,
    }))

    _G.expected = {
    -- [1] unchanged
    {
      _meta = { cycle = 1, id = 101 },
      content = "Can you find lua files and do a grep search for `function`",
      opts = { visible = true },
      role = "user",
    },
    -- [2] unchanged
    {
      _meta = { cycle = 1, id = 102 },
      content = "I'll search for those.",
      opts = { visible = true },
      role = "llm",
    },
    -- [3] tool calls survive intact
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
    -- [4] EDITED
    {
      _meta = {
        context_management = { edited = true },
        cycle = 1,
        estimated_tokens = placeholder_tokens,
        id = 104,
      },
      content = placeholder,
      opts = { visible = true },
      role = "tool",
      tools = { call_id = "c1a", is_error = false, type = "tool_result" },
    },
    -- [5] EDITED
    {
      _meta = {
        context_management = { edited = true },
        cycle = 1,
        estimated_tokens = placeholder_tokens,
        id = 105,
      },
      content = placeholder,
      opts = { visible = true },
      role = "tool",
      tools = { call_id = "c1b", is_error = false, type = "tool_result" },
    },

    -- [6] unchanged
    {
      _meta = { cycle = 2, id = 201 },
      content = "Read init.lua",
      opts = { visible = true },
      role = "user",
    },
    -- [7] unchanged
    {
      _meta = { cycle = 2, id = 202 },
      content = "Reading init.lua now.",
      opts = { visible = true },
      role = "llm",
    },
    -- [8] tool calls survive intact
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
    -- [9] EDITED
    {
      _meta = {
        context_management = { edited = true },
        cycle = 2,
        estimated_tokens = placeholder_tokens,
        id = 204,
      },
      content = placeholder,
      opts = { visible = true },
      role = "tool",
      tools = { call_id = "c2", is_error = false, type = "tool_result" },
    },

    -- [10] unchanged
    {
      _meta = { cycle = 3, id = 301 },
      content = "Remember that init.lua is the entry point",
      opts = { visible = true },
      role = "user",
    },
    -- [11] tool calls survive intact
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
    -- [12] memory tool is excluded — preserved despite cycle 3 being aged out
    {
      _meta = { cycle = 3, id = 303 },
      content = "Saved: init is entry",
      opts = { visible = true },
      role = "tool",
      tools = { call_id = "c3", is_error = false, type = "tool_result" },
    },

    -- [13] unchanged (cycle 4 kept by keep_cycles)
    {
      _meta = { cycle = 4, id = 401 },
      content = "Grep for `require`",
      opts = { visible = true },
      role = "user",
    },
    -- [14] tool calls survive intact
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
    -- [15] kept by keep_cycles
    {
      _meta = { cycle = 4, id = 403 },
      content = "matches in 12 files",
      opts = { visible = true },
      role = "tool",
      tools = { call_id = "c4", is_error = false, type = "tool_result" },
    },

    -- [16] unchanged
    {
      _meta = { cycle = 5, id = 501 },
      content = "What does that file do?",
      opts = { visible = true },
      role = "user",
    },
    -- [17] unchanged
    {
      _meta = { cycle = 5, id = 502 },
      content = "It bootstraps the plugin.",
      opts = { visible = true },
      role = "llm",
    },

    -- [18] unchanged (most recent)
    {
      _meta = { cycle = 6, id = 601 },
      content = "Read it once more",
      opts = { visible = true },
      role = "user",
    },
    -- [19] tool calls survive intact
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
    -- [20] kept by keep_cycles
    {
      _meta = { cycle = 6, id = 603 },
      content = "fresh contents",
      opts = { visible = true },
      role = "tool",
      tools = { call_id = "c6", is_error = false, type = "tool_result" },
    },
  }

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
