local h = require("tests.helpers")

local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        _G.chat = h.setup_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["apply"] = MiniTest.new_set()

T["apply"]["edits aged tool results when the editing threshold is met"] = function()
  child.lua([==[
    require("codecompanion.config").interactions.chat.opts.context_management = {
      enabled = true,
      editing = { trigger = 10, exclude_tools = {}, keep_cycles = 1 },
      compaction = { trigger = 999999 },
    }

    _G.chat.cycle = 5
    _G.chat.messages = {
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
        content = string.rep("some tool output content ", 200),
        _meta = { cycle = 1, id = 3 },
        opts = { visible = true },
        tools = { call_id = "c1", is_error = false, type = "tool_result" },
      },
    }

    require("codecompanion.interactions.chat.context_management").apply(_G.chat)
  ]==])

  local messages = child.lua_get("_G.chat.messages")
  h.is_true(messages[3]._meta.context_management.edited)
end

T["apply"]["compacts when the compaction threshold is met"] = function()
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
      compaction = { trigger = 10, min_token_savings = 1 },
    }

    local big_chunk = string.rep("payload ", 3000)
    _G.chat.cycle = 3
    _G.chat.messages = {
      {
        role = "user",
        content = big_chunk,
        _meta = { cycle = 1, id = 1 },
        opts = { visible = true },
      },
      {
        role = "llm",
        content = big_chunk,
        _meta = { cycle = 1, id = 2 },
        opts = { visible = true },
      },
    }

    _G.compact_summary_tag = require("codecompanion.interactions.shared.tags").COMPACT_SUMMARY
    require("codecompanion.interactions.chat.context_management").apply(_G.chat)
  ]==])

  local messages = child.lua_get("_G.chat.messages")
  local summary = messages[#messages]
  h.eq(child.lua_get("_G.compact_summary_tag"), summary._meta.tag)
  h.expect_match(summary.content, "Summary")
end

T["apply"]["skips when the chat is mid-tool-loop"] = function()
  child.lua([==[
    require("codecompanion.config").interactions.chat.opts.context_management = {
      enabled = true,
      editing = { trigger = 1, exclude_tools = {}, keep_cycles = 1 },
      compaction = { trigger = 999999 },
    }

    _G.chat.cycle = 5
    _G.chat.messages = {
      {
        role = "llm",
        content = "",
        _meta = { cycle = 1, id = 1 },
        opts = { visible = false },
        tools = {
          calls = {
            { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } },
          },
        },
      },
      -- No matching tool result — orphaned tool call
    }

    _G.before = vim.deepcopy(_G.chat.messages)
    require("codecompanion.interactions.chat.context_management").apply(_G.chat)
  ]==])

  h.eq(child.lua_get("_G.before"), child.lua_get("_G.chat.messages"))
end

T["apply"]["skips when a compaction is already running"] = function()
  child.lua([==[
    require("codecompanion.config").interactions.chat.opts.context_management = {
      enabled = true,
      editing = { trigger = 1, exclude_tools = {}, keep_cycles = 1 },
      compaction = { trigger = 1 },
    }

    _G.chat._compacting = true
    _G.chat.cycle = 5
    _G.chat.messages = {
      {
        role = "llm",
        content = "",
        _meta = { cycle = 1, id = 1 },
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
        _meta = { cycle = 1, id = 2 },
        opts = { visible = true },
        tools = { call_id = "c1", is_error = false, type = "tool_result" },
      },
    }

    _G.before = vim.deepcopy(_G.chat.messages)
    require("codecompanion.interactions.chat.context_management").apply(_G.chat)
  ]==])

  h.eq(child.lua_get("_G.before"), child.lua_get("_G.chat.messages"))
end

T["apply"]["skips when the model compacts its own context server-side"] = function()
  child.lua([==[
    require("codecompanion.config").interactions.chat.opts.context_management = {
      enabled = true,
      editing = { trigger = 1, exclude_tools = {}, keep_cycles = 1 },
      compaction = { trigger = 1, min_token_savings = 1 },
    }

    _G.chat.adapter.schema.model.choices = {
      ["gpt-3.5-turbo"] = { opts = { can_manage_context = true } },
    }

    _G.chat.cycle = 5
    _G.chat.messages = {
      {
        role = "llm",
        content = "",
        _meta = { cycle = 1, id = 1 },
        opts = { visible = false },
        tools = {
          calls = {
            { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } },
          },
        },
      },
      {
        role = "tool",
        content = string.rep("some tool output content ", 200),
        _meta = { cycle = 1, id = 2 },
        opts = { visible = true },
        tools = { call_id = "c1", is_error = false, type = "tool_result" },
      },
    }

    _G.before = vim.deepcopy(_G.chat.messages)
    require("codecompanion.interactions.chat.context_management").apply(_G.chat)
  ]==])

  h.eq(child.lua_get("_G.before"), child.lua_get("_G.chat.messages"))
end

T["apply"]["runs when a server-side compacting model has compaction turned off"] = function()
  child.lua([==[
    require("codecompanion.config").interactions.chat.opts.context_management = {
      enabled = true,
      editing = { trigger = 10, exclude_tools = {}, keep_cycles = 1 },
      compaction = { trigger = 999999 },
    }

    _G.chat.adapter.opts.compaction = false
    _G.chat.adapter.schema.model.choices = {
      ["gpt-3.5-turbo"] = { opts = { can_manage_context = true } },
    }

    _G.chat.cycle = 5
    _G.chat.messages = {
      {
        role = "llm",
        content = "",
        _meta = { cycle = 1, id = 1 },
        opts = { visible = false },
        tools = {
          calls = {
            { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = "{}" } },
          },
        },
      },
      {
        role = "tool",
        content = string.rep("some tool output content ", 200),
        _meta = { cycle = 1, id = 2 },
        opts = { visible = true },
        tools = { call_id = "c1", is_error = false, type = "tool_result" },
      },
    }

    require("codecompanion.interactions.chat.context_management").apply(_G.chat)
  ]==])

  local messages = child.lua_get("_G.chat.messages")
  h.is_true(messages[2]._meta.context_management.edited)
end

T["apply"]["reports the turn as handled only while a summary request is in flight"] = function()
  child.lua([==[
    package.loaded["codecompanion.interactions.background"] = {
      new = function()
        return { ask = function() end }
      end,
    }

    require("codecompanion.config").interactions.chat.opts.context_management = {
      enabled = true,
      editing = { trigger = 999999, exclude_tools = {}, keep_cycles = 3 },
      compaction = { trigger = 10, min_token_savings = 1 },
    }

    local big_chunk = string.rep("payload ", 3000)
    _G.chat.cycle = 3
    _G.chat.messages = {
      { role = "user", content = big_chunk, _meta = { cycle = 1, id = 1 }, opts = { visible = true } },
      { role = "llm", content = big_chunk, _meta = { cycle = 1, id = 2 }, opts = { visible = true } },
    }

    _G.handled = require("codecompanion.interactions.chat.context_management").apply(_G.chat)

    -- The savings are now far below the threshold, so nothing is started
    _G.chat._compacting = false
    require("codecompanion.config").interactions.chat.opts.context_management.compaction.min_token_savings = 999999
    _G.skipped = require("codecompanion.interactions.chat.context_management").apply(_G.chat)
  ]==])

  h.eq(true, child.lua_get("_G.handled"))
  h.eq(false, child.lua_get("_G.skipped"))
end

T["apply"]["ends the turn when the summary request fails"] = function()
  child.lua([==[
    package.loaded["codecompanion.interactions.background"] = {
      new = function()
        return {
          ask = function(_, _, opts)
            opts.on_error("summary adapter exploded")
          end,
        }
      end,
    }

    require("codecompanion.config").interactions.chat.opts.context_management = {
      enabled = true,
      editing = { trigger = 999999, exclude_tools = {}, keep_cycles = 3 },
      compaction = { trigger = 10, min_token_savings = 1 },
    }

    _G.chat_done = false
    vim.api.nvim_create_autocmd("User", {
      pattern = "CodeCompanionChatDone",
      callback = function() _G.chat_done = true end,
    })

    local big_chunk = string.rep("payload ", 3000)
    _G.chat.cycle = 3
    _G.chat.messages = {
      { role = "user", content = big_chunk, _meta = { cycle = 1, id = 1 }, opts = { visible = true } },
      { role = "llm", content = big_chunk, _meta = { cycle = 1, id = 2 }, opts = { visible = true } },
    }

    require("codecompanion.interactions.chat.context_management").apply(_G.chat)
  ]==])

  h.is_true(child.lua_get("_G.chat_done"))
  h.eq(false, child.lua_get("_G.chat._compacting"))
end

T["apply"]["does nothing when the token count is below all thresholds"] = function()
  child.lua([==[
    require("codecompanion.config").interactions.chat.opts.context_management = {
      enabled = true,
      editing = { trigger = 999999, exclude_tools = {}, keep_cycles = 1 },
      compaction = { trigger = 999999 },
    }

    _G.chat.cycle = 5
    _G.chat.messages = {
      {
        role = "llm",
        content = "",
        _meta = { cycle = 1, id = 1 },
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
        _meta = { cycle = 1, id = 2 },
        opts = { visible = true },
        tools = { call_id = "c1", is_error = false, type = "tool_result" },
      },
    }

    _G.before = vim.deepcopy(_G.chat.messages)
    require("codecompanion.interactions.chat.context_management").apply(_G.chat)
  ]==])

  h.eq(child.lua_get("_G.before"), child.lua_get("_G.chat.messages"))
end

T["auto submit"] = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.lua([==[
        _G.summarised = false
        package.loaded["codecompanion.interactions.background"] = {
          new = function()
            return {
              ask = function(_, _, opts)
                _G.summarised = true
                opts.on_done({ output = { content = "Summary" } })
              end,
            }
          end,
        }

        require("codecompanion.config").interactions.chat.opts.context_management = {
          enabled = true,
          editing = { trigger = 999999, exclude_tools = {}, keep_cycles = 3 },
          compaction = { trigger = 10, min_token_savings = 1 },
        }

        local big_chunk = string.rep("payload ", 3000)
        _G.chat.cycle = 3
        _G.chat.messages = {
          { role = "user", content = big_chunk, _meta = { cycle = 1, id = 1 }, opts = { visible = true } },
          { role = "llm", content = big_chunk, _meta = { cycle = 1, id = 2 }, opts = { visible = true } },
        }
      ]==])
    end,
  },
})

T["auto submit"]["compacts when a tool loop pushes the chat over the threshold"] = function()
  child.lua([[_G.chat:submit({ auto_submit = true })]])

  h.is_true(child.lua_get("_G.summarised"))
end

T["auto submit"]["DOES NOT compact when compaction itself resubmits"] = function()
  child.lua([[_G.chat:submit({ auto_submit = true, after_compaction = true })]])

  h.eq(false, child.lua_get("_G.summarised"))
end

return T
