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

T["Compaction"] = MiniTest.new_set()

T["Compaction"]["replaces the chat with placeholders and a tagged summary"] = function()
  child.lua([==[
    -- Stub the Background module so the LLM call resolves synchronously with mock content
    package.loaded["codecompanion.interactions.background"] = {
      new = function()
        return {
          ask = function(_, _, opts)
            opts.on_done({ output = { content = "Mock summary content" } })
          end,
        }
      end,
    }

    local Compaction = require("codecompanion.interactions.chat.context_management.compaction")
    local tags = require("codecompanion.interactions.shared.tags")
    local file_body = string.rep("file body line\n", 800)

    _G.chat.messages = {
      -- System prompt passes through
      {
        role = "system",
        content = "system prompt",
        opts = { visible = false },
        _meta = { cycle = 1, tag = tags.SYSTEM_PROMPT_FROM_CONFIG },
      },
      -- Project rules passes through
      {
        role = "user",
        content = "Project rules",
        opts = { visible = true },
        _meta = { cycle = 1, tag = tags.RULES },
      },
      -- File replaced with placeholder (path interpolated)
      {
        role = "user",
        content = file_body,
        context = { id = "<file>lua/foo.lua</file>", path = "lua/foo.lua" },
        opts = { visible = true },
        _meta = { cycle = 1, tag = tags.FILE },
      },
      -- Buffer replaced with placeholder (path interpolated)
      {
        role = "user",
        content = file_body,
        context = { id = "<buf>lua/bar.lua</buf>", path = "lua/bar.lua" },
        opts = { visible = true },
        _meta = { cycle = 1, tag = tags.BUFFER },
      },
      -- User prompt dropped and summarised
      {
        role = "user",
        content = "Tell me about the file",
        opts = { visible = true },
        _meta = { cycle = 1 },
      },
      -- LLM reply dropped and summarised
      {
        role = "llm",
        content = "It contains 800 repeated lines",
        opts = { visible = true },
        _meta = { cycle = 1 },
      },
    }

    -- NOTE: min_token_savings is set low so this test can run
    Compaction.compact(_G.chat, { min_token_savings = 1 })

    _G.compact_summary_tag = tags.COMPACT_SUMMARY
  ]==])

  local messages = child.lua_get("_G.chat.messages")

  -- 4 retained messages + 1 summary message
  h.eq(5, #messages)

  -- system + rules preserved
  h.eq("system prompt", messages[1].content)
  h.eq("Project rules", messages[2].content)

  -- file + buffer swapped for placeholders with their paths interpolated, marked compacted
  h.expect_match(messages[3].content, "File content for `lua/foo%.lua` cleared")
  h.is_true(messages[3]._meta.context_management.compacted)
  h.expect_match(messages[4].content, "Buffer content for `lua/bar%.lua` cleared")
  h.is_true(messages[4]._meta.context_management.compacted)

  -- Summary is appended to the chat buffer as text
  local content = child.lua_get([[vim.api.nvim_buf_get_lines(0, 0, -1, true)]])
  h.eq(content[1], "## foo")
  h.eq(content[3], "Below is a summary of a previous conversation:")

  h.eq(false, child.lua_get("_G.chat._compacting"))
end

T["Compaction"]["re-run drops the stale summary, keeps compacted placeholders, and resummarises"] = function()
  child.lua([==[
    package.loaded["codecompanion.interactions.background"] = {
      new = function()
        return {
          ask = function(_, _, opts)
            opts.on_done({ output = { content = "Second summary" } })
          end,
        }
      end,
    }

    local Compaction = require("codecompanion.interactions.chat.context_management.compaction")
    local tags = require("codecompanion.interactions.shared.tags")
    local big_chunk = string.rep("payload ", 3000)

    _G.chat.messages = {
      -- System prompt passes through
      {
        role = "system",
        content = "system prompt",
        opts = { visible = false },
        _meta = { cycle = 1, tag = tags.SYSTEM_PROMPT_FROM_CONFIG },
      },
      -- Previous compaction's placeholder passes through verbatim
      {
        role = "user",
        content = "<important>File content for `lua/keep.lua` cleared during compaction. Re-read the file if you need it.</important>",
        opts = { visible = true },
        _meta = { cycle = 1, tag = tags.FILE, context_management = { compacted = true } },
      },
      -- Stale summary dropped, replaced by new one
      {
        role = "user",
        content = "OLD SUMMARY",
        opts = { visible = true },
        _meta = { cycle = 1, tag = tags.COMPACT_SUMMARY },
      },
      -- New user prompt dropped and summarised
      {
        role = "user",
        content = big_chunk,
        opts = { visible = true },
        _meta = { cycle = 1 },
      },
      -- New LLM reply dropped and summarised
      {
        role = "llm",
        content = big_chunk,
        opts = { visible = true },
        _meta = { cycle = 1 },
      },
    }

    Compaction.compact(_G.chat, { min_token_savings = 1 })

    _G.compact_summary_tag = tags.COMPACT_SUMMARY
  ]==])

  local messages = child.lua_get("_G.chat.messages")

  -- system + retained placeholder + new summary
  h.eq(3, #messages)
  h.eq("system prompt", messages[1].content)
  h.expect_match(messages[2].content, "File content for `lua/keep%.lua` cleared")
  h.is_true(messages[2]._meta.context_management.compacted)
  h.expect_match(messages[3].content, "Second summary")
end

T["Compaction"]["skips when estimated savings fall below min_token_savings"] = function()
  child.lua([==[
    _G.ask_called = false
    package.loaded["codecompanion.interactions.background"] = {
      new = function()
        return {
          ask = function() _G.ask_called = true end,
        }
      end,
    }

    local Compaction = require("codecompanion.interactions.chat.context_management.compaction")

    _G.chat.messages = {
      {
        role = "user",
        content = "hi",
        opts = { visible = true },
        _meta = { cycle = 1 },
      },
      {
        role = "llm",
        content = "hello",
        opts = { visible = true },
        _meta = { cycle = 1 },
      },
    }

    _G.before = vim.deepcopy(_G.chat.messages)
    Compaction.compact(_G.chat)
  ]==])

  -- Threshold short-circuits the call, Background.ask never reached
  h.eq(false, child.lua_get("_G.ask_called"))
  h.eq(child.lua_get("_G.before"), child.lua_get("_G.chat.messages"))
end

T["Compaction"]["leaves messages untouched when the LLM call errors"] = function()
  child.lua([==[
    package.loaded["codecompanion.interactions.background"] = {
      new = function()
        return {
          ask = function(_, _, opts)
            opts.on_error("boom")
          end,
        }
      end,
    }

    local Compaction = require("codecompanion.interactions.chat.context_management.compaction")
    local big_chunk = string.rep("payload ", 3000)

    _G.chat.messages = {
      {
        role = "user",
        content = big_chunk,
        opts = { visible = true },
        _meta = { cycle = 1 },
      },
      {
        role = "llm",
        content = big_chunk,
        opts = { visible = true },
        _meta = { cycle = 1 },
      },
    }

    _G.before = vim.deepcopy(_G.chat.messages)
    Compaction.compact(_G.chat, { min_token_savings = 1 })
  ]==])

  h.eq(child.lua_get("_G.before"), child.lua_get("_G.chat.messages"))
  h.eq(false, child.lua_get("_G.chat._compacting"))
end

T["Compaction"]["fallback_to_chat_adapter retries on the chat adapter"] = function()
  child.lua([==[
    -- First ask errors on the primary adapter, second succeeds on the chat adapter fallback
    _G.call_count = 0
    _G.adapters_used = {}
    package.loaded["codecompanion.interactions.background"] = {
      new = function(args)
        return {
          ask = function(_, _, opts)
            _G.call_count = _G.call_count + 1
            table.insert(_G.adapters_used, args.adapter)
            if _G.call_count == 1 then
              opts.on_error("primary failure")
            else
              opts.on_done({ output = { content = "fallback summary" } })
            end
          end,
        }
      end,
    }

    local Compaction = require("codecompanion.interactions.chat.context_management.compaction")
    local big_chunk = string.rep("payload ", 3000)

    _G.chat_adapter = _G.chat.adapter
    _G.override_adapter = { name = "override", type = "http" }

    _G.chat.messages = {
      {
        role = "user",
        content = big_chunk,
        opts = { visible = true },
        _meta = { cycle = 1 },
      },
      {
        role = "llm",
        content = big_chunk,
        opts = { visible = true },
        _meta = { cycle = 1 },
      },
    }

    Compaction.compact(_G.chat, {
      adapter = _G.override_adapter,
      fallback_to_chat_adapter = true,
    })
  ]==])

  h.eq(2, child.lua_get("_G.call_count"))
  h.eq(child.lua_get("_G.override_adapter.name"), child.lua_get("_G.adapters_used[1].name"))
  h.eq(child.lua_get("_G.chat_adapter.name"), child.lua_get("_G.adapters_used[2].name"))

  local messages = child.lua_get("_G.chat.messages")
  h.expect_match(messages[#messages].content, "fallback summary")
end

T["Compaction"]["lock prevents concurrent runs"] = function()
  child.lua([==[
    _G.ask_called = false
    package.loaded["codecompanion.interactions.background"] = {
      new = function()
        return {
          ask = function() _G.ask_called = true end,
        }
      end,
    }

    local Compaction = require("codecompanion.interactions.chat.context_management.compaction")
    local big_chunk = string.rep("payload ", 3000)

    -- A compaction is already in flight
    _G.chat._compacting = true
    _G.chat.messages = {
      {
        role = "user",
        content = big_chunk,
        opts = { visible = true },
        _meta = { cycle = 1 },
      },
      {
        role = "llm",
        content = big_chunk,
        opts = { visible = true },
        _meta = { cycle = 1 },
      },
    }

    Compaction.compact(_G.chat)
  ]==])

  h.eq(false, child.lua_get("_G.ask_called"))
  h.is_true(child.lua_get("_G.chat._compacting"))
end

T["Compaction"]["renders the compacted chat buffer correctly"] = function()
  child.lua([==[
    package.loaded["codecompanion.interactions.background"] = {
      new = function()
        return {
          ask = function(_, _, opts)
            opts.on_done({ output = { content = "The user asked about context management.\nWe discussed editing and compaction." } })
          end,
        }
      end,
    }

    local tags = require("codecompanion.interactions.shared.tags")
    local big_result = string.rep("Tool output with function signatures and variable names. ", 100)

    -- Build a multi-cycle conversation with tool calls

    -- Chat context
    _G.chat.context:add({
      id = "<buf>foo.lua</buf>",
      path = "foo.lua",
      source = "test",
    })
    _G.chat.context:add({
      id = "<buf>bar.lua</buf>",
      path = "bar.lua",
      source = "test",
    })

    -- Cycle 1
    table.insert(_G.chat.messages, {
      role = "user",
      content = "Read the config file",
      _meta = { cycle = 1, id = 201 },
      opts = { visible = true },
    })
    table.insert(_G.chat.messages, {
      role = "llm",
      content = "",
      _meta = { cycle = 1, id = 202 },
      opts = { visible = false },
      tools = { calls = { { id = "c1", type = "function", ["function"] = { name = "read_file", arguments = '{"path":"config.lua"}' } } } },
    })
    table.insert(_G.chat.messages, {
      role = "tool",
      content = big_result,
      _meta = { cycle = 1, id = 203 },
      opts = { visible = true },
      tools = { call_id = "c1", is_error = false, type = "tool_result" },
    })
    table.insert(_G.chat.messages, {
      role = "llm",
      content = "I've read the config file.",
      _meta = { cycle = 1, id = 204 },
      opts = { visible = true },
    })

    -- Cycle 2
    table.insert(_G.chat.messages, {
      role = "user",
      content = "Read the helpers file too",
      _meta = { cycle = 2, id = 301 },
      opts = { visible = true },
    })
    table.insert(_G.chat.messages, {
      role = "llm",
      content = "",
      _meta = { cycle = 2, id = 302 },
      opts = { visible = false },
      tools = { calls = { { id = "c2", type = "function", ["function"] = { name = "read_file", arguments = '{"path":"helpers.lua"}' } } } },
    })
    table.insert(_G.chat.messages, {
      role = "tool",
      content = big_result,
      _meta = { cycle = 2, id = 303 },
      opts = { visible = true },
      tools = { call_id = "c2", is_error = false, type = "tool_result" },
    })
    table.insert(_G.chat.messages, {
      role = "llm",
      content = "I've read the helpers file.",
      _meta = { cycle = 2, id = 304 },
      opts = { visible = true },
    })

    _G.chat.cycle = 3

    -- Render a prior user/LLM exchange to the chat buffer (mirroring real usage where
    -- compaction is triggered after an LLM turn). Without this the buffer would be
    -- empty and the role-change detection in `add_buf_message` would have nothing
    -- to compare against — masking bugs where the summary lands under the LLM header.
    _G.chat:add_buf_message({ role = "user", content = "Read the config file" })
    _G.chat:add_buf_message({ role = "llm", content = "I've read the config file." })

    local Compaction = require("codecompanion.interactions.chat.context_management.compaction")
    Compaction.compact(_G.chat, { min_token_savings = 1 })
  ]==])

  MiniTest.expect.reference_screenshot(child.get_screenshot())
end

T["Compaction"]["locks the buffer and shows a status while the request is in flight"] = function()
  child.lua([==[
    -- Background that captures the call without resolving — leaves compaction mid-flight
    package.loaded["codecompanion.interactions.background"] = {
      new = function()
        return {
          ask = function() end,
        }
      end,
    }

    _G.chat:add_buf_message({ role = "user", content = "Hi" })
    _G.chat:add_buf_message({ role = "llm", content = "Hello there." })

    _G.chat.messages = {
      { role = "user", content = string.rep("payload ", 3000), _meta = { cycle = 1 }, opts = { visible = true } },
      { role = "llm", content = string.rep("payload ", 3000), _meta = { cycle = 1 }, opts = { visible = true } },
    }

    local Compaction = require("codecompanion.interactions.chat.context_management.compaction")
    Compaction.compact(_G.chat, { min_token_savings = 1 })
  ]==])

  h.is_true(child.lua_get("_G.chat._compacting"))
  h.eq(false, child.lua_get("vim.bo[_G.chat.bufnr].modifiable"))
  h.is_true(child.lua_get("_G.chat._status.compacting == true"))
  MiniTest.expect.reference_screenshot(child.get_screenshot())
end

T["Compaction"]["unlocks the buffer and clears the status after the LLM responds"] = function()
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

    _G.chat:add_buf_message({ role = "user", content = "Hi" })
    _G.chat:add_buf_message({ role = "llm", content = "Hello there." })

    _G.chat.messages = {
      { role = "user", content = string.rep("payload ", 3000), _meta = { cycle = 1 }, opts = { visible = true } },
      { role = "llm", content = string.rep("payload ", 3000), _meta = { cycle = 1 }, opts = { visible = true } },
    }

    local Compaction = require("codecompanion.interactions.chat.context_management.compaction")
    Compaction.compact(_G.chat, { min_token_savings = 1 })
  ]==])

  h.eq(false, child.lua_get("_G.chat._compacting"))
  h.is_true(child.lua_get("vim.bo[_G.chat.bufnr].modifiable"))
  h.eq(vim.NIL, child.lua_get("_G.chat._status.compacting"))
end

return T
