-- Test script for context management (editing + compaction)
-- NOTE: GENERATED ENTIRELY BY CLAUDE CODE FOR TESTING PURPOSES ONLY
--
-- Usage: Open Neovim with CodeCompanion loaded, then run:
--   :luafile tests/scripts/context_management.lua
-- Or:
--   :source %
--
-- What it does:
--   1. Lowers editing/compaction thresholds so they trigger on small conversations
--   2. Creates a chat pre-loaded with several cycles of tool-heavy messages
--   3. Auto-submits a final prompt so the LLM responds and Chat:done() fires
--   4. When done() runs, check() evaluates thresholds and should trigger editing
--      (or compaction if the total is high enough)
--
-- What to look for:
--   - :CodeCompanionLog should show "[Context Management] Edited N tool result(s)"
--   - Tool results from early cycles should have their content replaced with the
--     editing placeholder
--   - If compaction triggers, the buffer locks, a "Compacting..." status appears,
--     and messages are replaced with a summary
--
-- Adjust the thresholds below to test different scenarios.

local config = require("codecompanion.config")
local tags = require("codecompanion.interactions.shared.tags")

-- Lower thresholds (absolute token counts) so they trigger easily
config.interactions.chat.opts.context_management.editing.trigger = 200
config.interactions.chat.opts.context_management.compaction.trigger = 10000
config.interactions.chat.opts.context_management.compaction.min_token_savings = 100
config.interactions.chat.opts.context_management.editing.keep_cycles = 1

local big_result = string.rep(
  "This is a detailed tool output with information about the codebase including function signatures, variable names, control flow patterns and architectural decisions. ",
  200
)

local file_content = string.rep(
  "local M = {} function M.setup(opts) opts = opts or {} end return M -- config module with adapter settings, tool groups, and display options\n",
  30
)

local file_context_id = "<file>lua/codecompanion/config.lua</file>"
local buffer_context_id = "<buf>lua/codecompanion/init.lua</buf>"

local messages = {
  -- File shared via /file slash command (should survive compaction as a placeholder)
  {
    role = "user",
    content = '<attachment filepath="lua/codecompanion/config.lua">' .. file_content .. "</attachment>",
    context = { id = file_context_id, path = "lua/codecompanion/config.lua" },
    _meta = { cycle = 1, id = 100, tag = tags.FILE },
    opts = { visible = false },
  },
  -- Buffer shared via /buffer slash command (should also survive compaction)
  {
    role = "user",
    content = '<attachment filepath="lua/codecompanion/init.lua">'
      .. string.rep("local codecompanion = {}\n", 20)
      .. "</attachment>",
    context = { id = buffer_context_id, path = "lua/codecompanion/init.lua" },
    _meta = { cycle = 1, id = 99, tag = tags.BUFFER },
    opts = { visible = false },
  },

  -- Cycle 1: user asks, LLM calls read_file, tool returns large result, LLM responds
  {
    role = "user",
    content = "Can you read the main config file for me?",
    _meta = { cycle = 1, id = 101 },
    opts = { visible = true },
  },
  {
    role = "llm",
    content = "",
    _meta = { cycle = 1, id = 102 },
    opts = { visible = false },
    tools = {
      calls = {
        {
          id = "call_1a",
          type = "function",
          ["function"] = { name = "read_file", arguments = '{"path":"config.lua"}' },
        },
      },
    },
  },
  {
    role = "tool",
    content = big_result,
    _meta = { cycle = 1, id = 103 },
    opts = { visible = true },
    tools = { call_id = "call_1a", is_error = false, type = "tool_result" },
  },
  {
    role = "llm",
    content = "I've read the config file. It contains the main configuration for the plugin including adapter settings, tool groups, and display options.",
    _meta = { cycle = 1, id = 104 },
    opts = { visible = true },
  },

  -- Cycle 2: user asks, LLM calls grep_search + read_file, both return results, LLM responds
  {
    role = "user",
    content = "Now find all references to context_management and read the helpers file",
    _meta = { cycle = 2, id = 201 },
    opts = { visible = true },
  },
  {
    role = "llm",
    content = "",
    _meta = { cycle = 2, id = 202 },
    opts = { visible = false },
    tools = {
      calls = {
        {
          id = "call_2a",
          type = "function",
          ["function"] = { name = "grep_search", arguments = '{"pattern":"context_management"}' },
        },
        {
          id = "call_2b",
          type = "function",
          ["function"] = { name = "read_file", arguments = '{"path":"helpers/init.lua"}' },
        },
      },
    },
  },
  {
    role = "tool",
    content = big_result,
    _meta = { cycle = 2, id = 203 },
    opts = { visible = true },
    tools = { call_id = "call_2a", is_error = false, type = "tool_result" },
  },
  {
    role = "tool",
    content = big_result,
    _meta = { cycle = 2, id = 204 },
    opts = { visible = true },
    tools = { call_id = "call_2b", is_error = false, type = "tool_result" },
  },
  {
    role = "llm",
    content = "I found several references to context_management across the codebase. The helpers file contains the trigger_context_management function which calculates token thresholds.",
    _meta = { cycle = 2, id = 205 },
    opts = { visible = true },
  },

  -- Cycle 3: another round of tool usage
  {
    role = "user",
    content = "Read the compaction module too",
    _meta = { cycle = 3, id = 301 },
    opts = { visible = true },
  },
  {
    role = "llm",
    content = "",
    _meta = { cycle = 3, id = 302 },
    opts = { visible = false },
    tools = {
      calls = {
        {
          id = "call_3a",
          type = "function",
          ["function"] = { name = "read_file", arguments = '{"path":"compaction.lua"}' },
        },
      },
    },
  },
  {
    role = "tool",
    content = big_result,
    _meta = { cycle = 3, id = 303 },
    opts = { visible = true },
    tools = { call_id = "call_3a", is_error = false, type = "tool_result" },
  },
  {
    role = "llm",
    content = "The compaction module handles summarising conversation history when the context window gets too full. It uses an LLM call to generate a summary.",
    _meta = { cycle = 3, id = 304 },
    opts = { visible = true },
  },

  -- Cycle 4: more tools
  {
    role = "user",
    content = "And the editing module",
    _meta = { cycle = 4, id = 401 },
    opts = { visible = true },
  },
  {
    role = "llm",
    content = "",
    _meta = { cycle = 4, id = 402 },
    opts = { visible = false },
    tools = {
      calls = {
        {
          id = "call_4a",
          type = "function",
          ["function"] = { name = "read_file", arguments = '{"path":"editing.lua"}' },
        },
      },
    },
  },
  {
    role = "tool",
    content = big_result,
    _meta = { cycle = 4, id = 403 },
    opts = { visible = true },
    tools = { call_id = "call_4a", is_error = false, type = "tool_result" },
  },
  {
    role = "llm",
    content = "The editing module replaces aged tool results with a placeholder to save context. It preserves the most recent N cycles.",
    _meta = { cycle = 4, id = 404 },
    opts = { visible = true },
  },
}

-- Open the chat with pre-loaded messages and auto-submit a final prompt.
-- When the LLM responds, done() fires, check() runs, and context management should trigger.
--
-- The on_created callback populates context_items to match the file/buffer messages above.
-- After compaction, check that:
--   - context_items still contains both the file and buffer entries
--   - file/buffer messages are retained with placeholders (not dropped)
--   - the context block re-renders in the buffer
require("codecompanion").chat({
  auto_submit = false,
  callbacks = {
    on_created = {
      function(chat)
        chat.context:add({
          id = file_context_id,
          path = "lua/codecompanion/config.lua",
          source = "codecompanion.interactions.chat.slash_commands.file",
          opts = { visible = true },
        })
        chat.context:add({
          id = buffer_context_id,
          path = "lua/codecompanion/init.lua",
          source = "codecompanion.interactions.chat.slash_commands.buffer",
          opts = { visible = true },
        })
      end,
    },
  },
  messages = messages,
  user_prompt = "Great, now give me a brief summary of what you've learned about context management in this codebase.",
})
