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

    _G.chat = {
      adapter = { type = "http", name = "fake" },
      buffer_context = {},
      cycle = 7,
      opts = {},
      ui = { render = function(self) return self end },
      messages = {
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
        -- File replaced with placeholder
        {
          role = "user",
          content = file_body,
          opts = { visible = true },
          _meta = { cycle = 1, tag = tags.FILE },
        },
        -- Buffer replaced with placeholder
        {
          role = "user",
          content = file_body,
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
      },
    }

    -- NOTE: min_token_savings is set low so this test can run
    Compaction.compact(_G.chat, { min_token_savings = 1 })

    _G.placeholder_file = Compaction.PLACEHOLDERS.file
    _G.placeholder_buffer = Compaction.PLACEHOLDERS.buffer
    _G.compact_summary_tag = tags.COMPACT_SUMMARY
  ]==])

  local messages = child.lua_get("_G.chat.messages")

  -- 4 retained messages + 1 new summary
  h.eq(5, #messages)

  -- system + rules preserved
  h.eq("system prompt", messages[1].content)
  h.eq("Project rules", messages[2].content)

  -- file + buffer swapped for placeholders, marked compacted
  h.eq(child.lua_get("_G.placeholder_file"), messages[3].content)
  h.is_true(messages[3]._meta.context_management.compacted)
  h.eq(child.lua_get("_G.placeholder_buffer"), messages[4].content)
  h.is_true(messages[4]._meta.context_management.compacted)

  -- Summary appended at the end with the right tag
  local summary = messages[5]
  h.eq(child.lua_get("_G.compact_summary_tag"), summary._meta.tag)
  h.eq("user", summary.role)
  h.expect_match(summary.content, "Mock summary content")

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

    _G.chat = {
      adapter = { type = "http", name = "fake" },
      buffer_context = {},
      cycle = 9,
      opts = {},
      ui = { render = function(self) return self end },
      messages = {
        -- System prompt passes through
        {
          role = "system",
          content = "system prompt",
          opts = { visible = false },
          _meta = { cycle = 1, tag = tags.SYSTEM_PROMPT_FROM_CONFIG },
        },
        -- Previous compaction's placeholder passes through
        {
          role = "user",
          content = Compaction.PLACEHOLDERS.file,
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
      },
    }

    Compaction.compact(_G.chat)

    _G.placeholder_file = Compaction.PLACEHOLDERS.file
    _G.compact_summary_tag = tags.COMPACT_SUMMARY
  ]==])

  local messages = child.lua_get("_G.chat.messages")

  -- system + retained placeholder + new summary
  h.eq(3, #messages)
  h.eq("system prompt", messages[1].content)
  h.eq(child.lua_get("_G.placeholder_file"), messages[2].content)
  h.is_true(messages[2]._meta.context_management.compacted)
  h.eq(child.lua_get("_G.compact_summary_tag"), messages[3]._meta.tag)
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

    _G.chat = {
      adapter = { type = "http", name = "fake" },
      buffer_context = {},
      cycle = 1,
      opts = {},
      ui = { render = function(self) return self end },
      messages = {
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
      },
    }

    _G.before = vim.deepcopy(_G.chat.messages)
    Compaction.compact(_G.chat)
  ]==])

  -- Threshold short-circuits the call, Background.ask never reached
  h.eq(false, child.lua_get("_G.ask_called"))
  h.eq(child.lua_get("_G.before"), child.lua_get("_G.chat.messages"))
end

T["Compaction"]["respects a min_token_savings override"] = function()
  child.lua([==[
    _G.ask_called = false
    package.loaded["codecompanion.interactions.background"] = {
      new = function()
        return {
          ask = function(_, _, opts)
            _G.ask_called = true
            opts.on_done({ output = { content = "summary" } })
          end,
        }
      end,
    }

    local Compaction = require("codecompanion.interactions.chat.context_management.compaction")
    local tags = require("codecompanion.interactions.shared.tags")

    _G.chat = {
      adapter = { type = "http", name = "fake" },
      buffer_context = {},
      cycle = 1,
      opts = {},
      ui = { render = function(self) return self end },
      messages = {
        {
          role = "user",
          content = "a small chat",
          opts = { visible = true },
          _meta = { cycle = 1 },
        },
        {
          role = "llm",
          content = "a small response",
          opts = { visible = true },
          _meta = { cycle = 1 },
        },
      },
    }

    -- min_token_savings of 1 bypasses the default threshold
    Compaction.compact(_G.chat, { min_token_savings = 1 })

    _G.compact_summary_tag = tags.COMPACT_SUMMARY
  ]==])

  h.is_true(child.lua_get("_G.ask_called"))
  local messages = child.lua_get("_G.chat.messages")
  h.eq(child.lua_get("_G.compact_summary_tag"), messages[#messages]._meta.tag)
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

    _G.chat = {
      adapter = { type = "http", name = "fake" },
      buffer_context = {},
      cycle = 1,
      opts = {},
      ui = { render = function(self) return self end },
      messages = {
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
      },
    }

    _G.before = vim.deepcopy(_G.chat.messages)
    Compaction.compact(_G.chat)
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

    _G.chat_adapter = { type = "http", name = "chat" }
    _G.override_adapter = { type = "http", name = "override" }

    _G.chat = {
      adapter = _G.chat_adapter,
      buffer_context = {},
      cycle = 1,
      opts = {},
      ui = { render = function(self) return self end },
      messages = {
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
      },
    }

    Compaction.compact(_G.chat, {
      adapter = _G.override_adapter,
      fallback_to_chat_adapter = true,
    })
  ]==])

  h.eq(2, child.lua_get("_G.call_count"))
  h.eq(child.lua_get("_G.override_adapter"), child.lua_get("_G.adapters_used[1]"))
  h.eq(child.lua_get("_G.chat_adapter"), child.lua_get("_G.adapters_used[2]"))

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

    _G.chat = {
      adapter = { type = "http", name = "fake" },
      buffer_context = {},
      cycle = 1,
      opts = {},
      ui = { render = function(self) return self end },
      -- A compaction is already in flight
      _compacting = true,
      messages = {
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
      },
    }

    Compaction.compact(_G.chat)
  ]==])

  h.eq(false, child.lua_get("_G.ask_called"))
  h.is_true(child.lua_get("_G.chat._compacting"))
end

return T
