local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
    end,
    post_once = child.stop,
  },
})

T["check"] = MiniTest.new_set()

T["check"]["edits context when threshold is met"] = function()
  child.lua([==[
    local big_content = string.rep("some tool output content ", 200)

    -- Set up config with a low editing trigger (absolute tokens) and high compaction trigger
    require("codecompanion.config").interactions.chat.opts.context_management = {
      enabled = true,
      editing = { trigger = 10, exclude_tools = {}, keep_cycles = 1 },
      compaction = { trigger = 999999 },
    }

    local ContextManagement = require("codecompanion.interactions.chat.context_management")

    _G.chat = {
      adapter = {
        type = "http",
        name = "fake",
        schema = { model = { default = "test", choices = { test = { meta = { context_window = 100000 } } } } },
      },
      cycle = 5,
      messages = {
        {
          role = "user",
          content = "Please read the file for me",
          _meta = { cycle = 1, id = 1 },
          opts = { visible = true },
        },
        {
          role = "llm",
          content = "",
          _meta = { cycle = 1, id = 2 },
          opts = { visible = false },
          tools = {
            calls = {
              { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } },
            },
          },
        },
        {
          role = "tool",
          content = big_content,
          _meta = { cycle = 1, id = 3 },
          opts = { visible = true },
          tools = { call_id = "c1", is_error = false, type = "tool_result" },
        },
      },
      has_orphaned_tool_calls = function() return false end,
    }

    ContextManagement.check(_G.chat)
  ]==])

  local messages = child.lua_get("_G.chat.messages")

  -- The tool result from cycle 1 was edited (cycle 1 is outside keep_cycles=1 when current_cycle=5)
  local tool_result = messages[3]
  h.is_true(tool_result._meta.context_management.edited)
end

T["check"]["compacts when threshold is met"] = function()
  child.lua([==[
    package.loaded["codecompanion.interactions.background"] = {
      new = function()
        return {
          ask = function(_, _, opts)
            opts.on_done({ output = { content = "Summary" } })
          end,
        }
      end,
    }

    require("codecompanion.config").interactions.chat.opts.context_management = {
      enabled = true,
      editing = { trigger = 5, exclude_tools = {}, keep_cycles = 3 },
      compaction = { trigger = 10 },
    }

    local ContextManagement = require("codecompanion.interactions.chat.context_management")
    local tags = require("codecompanion.interactions.shared.tags")
    local big_chunk = string.rep("payload ", 3000)

    _G.chat = {
      adapter = {
        type = "http",
        name = "fake",
        schema = { model = { default = "test", choices = { test = { meta = { context_window = 100000 } } } } },
      },
      bufnr = 1,
      id = 1,
      buffer_context = {},
      cycle = 3,
      opts = {},
      ui = { display_tokens = function() end, lock_buf = function() end, render = function(self) return self end, unlock_buf = function() end },
      _clear_status = function() end,
      _last_role = "llm",
      _set_status = function() end,
      add_buf_message = function() end,
      context = { render = function() end, clear_rendered = function() end },
      context_items = {},
      dispatch = function() end,
      builder = { state = { last_role = "llm" } },
      ready_for_input = function(self) self._last_role = "user" end,
      refresh_context = function() end,
      update_metadata = function() end,
      messages = {
        {
          role = "user",
          content = big_chunk,
          _meta = { cycle = 1, id = 1, estimated_tokens = 20000 },
          opts = { visible = true },
        },
        {
          role = "llm",
          content = big_chunk,
          _meta = { cycle = 1, id = 2, estimated_tokens = 20000 },
          opts = { visible = true },
        },
      },
      has_orphaned_tool_calls = function() return false end,
    }

    _G.compact_summary_tag = tags.COMPACT_SUMMARY
    ContextManagement.check(_G.chat)
  ]==])

  local messages = child.lua_get("_G.chat.messages")
  local summary = messages[#messages]
  h.eq(child.lua_get("_G.compact_summary_tag"), summary._meta.tag)
  h.expect_match(summary.content, "Summary")
end

T["check"]["leaves messages unchanged when tool calls have no results yet"] = function()
  child.lua([==[
    require("codecompanion.config").interactions.chat.opts.context_management = {
      enabled = true,
      editing = { trigger = 1, exclude_tools = {}, keep_cycles = 1 },
      compaction = { trigger = 1 },
    }

    local ContextManagement = require("codecompanion.interactions.chat.context_management")

    _G.chat = {
      adapter = {
        type = "http",
        name = "fake",
        schema = { model = { default = "test", choices = { test = { meta = { context_window = 100 } } } } },
      },
      cycle = 5,
      messages = {
        {
          role = "llm",
          content = "",
          _meta = { cycle = 1, id = 1, estimated_tokens = 0 },
          opts = { visible = false },
          tools = {
            calls = {
              { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } },
            },
          },
        },
        {
          role = "tool",
          content = "file contents here",
          _meta = { cycle = 1, id = 2, estimated_tokens = 10 },
          opts = { visible = true },
          tools = { call_id = "c1", is_error = false, type = "tool_result" },
        },
      },
      -- Simulate orphaned tool calls
      has_orphaned_tool_calls = function() return true end,
    }

    _G.before = vim.deepcopy(_G.chat.messages)
    ContextManagement.check(_G.chat)
  ]==])

  h.eq(child.lua_get("_G.before"), child.lua_get("_G.chat.messages"))
end

T["check"]["leaves messages unchanged when a compaction is already running"] = function()
  child.lua([==[
    require("codecompanion.config").interactions.chat.opts.context_management = {
      enabled = true,
      editing = { trigger = 1, exclude_tools = {}, keep_cycles = 1 },
      compaction = { trigger = 1 },
    }

    local ContextManagement = require("codecompanion.interactions.chat.context_management")

    _G.chat = {
      adapter = {
        type = "http",
        name = "fake",
        schema = { model = { default = "test", choices = { test = { meta = { context_window = 100 } } } } },
      },
      cycle = 5,
      _compacting = true,
      messages = {
        {
          role = "llm",
          content = "",
          _meta = { cycle = 1, id = 1, estimated_tokens = 0 },
          opts = { visible = false },
          tools = {
            calls = {
              { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } },
            },
          },
        },
        {
          role = "tool",
          content = "file contents here",
          _meta = { cycle = 1, id = 2, estimated_tokens = 10 },
          opts = { visible = true },
          tools = { call_id = "c1", is_error = false, type = "tool_result" },
        },
      },
      has_orphaned_tool_calls = function() return false end,
    }

    _G.before = vim.deepcopy(_G.chat.messages)
    ContextManagement.check(_G.chat)
  ]==])

  h.eq(child.lua_get("_G.before"), child.lua_get("_G.chat.messages"))
end

T["check"]["does nothing when token count is below all thresholds"] = function()
  child.lua([==[
    require("codecompanion.config").interactions.chat.opts.context_management = {
      enabled = true,
      editing = { trigger = 999999, exclude_tools = {}, keep_cycles = 1 },
      compaction = { trigger = 999999 },
    }

    local ContextManagement = require("codecompanion.interactions.chat.context_management")

    _G.chat = {
      adapter = {
        type = "http",
        name = "fake",
        schema = { model = { default = "test", choices = { test = { meta = { context_window = 100000 } } } } },
      },
      cycle = 5,
      messages = {
        {
          role = "llm",
          content = "",
          _meta = { cycle = 1, id = 1, estimated_tokens = 0 },
          opts = { visible = false },
          tools = {
            calls = {
              { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } },
            },
          },
        },
        {
          role = "tool",
          content = "file contents here",
          _meta = { cycle = 1, id = 2, estimated_tokens = 10 },
          opts = { visible = true },
          tools = { call_id = "c1", is_error = false, type = "tool_result" },
        },
      },
      has_orphaned_tool_calls = function() return false end,
    }

    _G.before = vim.deepcopy(_G.chat.messages)
    ContextManagement.check(_G.chat)
  ]==])

  h.eq(child.lua_get("_G.before"), child.lua_get("_G.chat.messages"))
end

return T
