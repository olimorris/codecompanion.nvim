local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        chat, tools = h.setup_chat_buffer()

        -- The chat buffer binds its own keys (e.g. gc, gs), so only match the
        -- question prompt's mappings via their desc prefix
        function _G.wait_for_keymap(lhs, previous)
          local found
          vim.wait(2000, function()
            for _, map in ipairs(vim.api.nvim_buf_get_keymap(chat.bufnr, 'n')) do
              if map.lhs == lhs
                and map.callback
                and map.callback ~= previous
                and map.desc
                and map.desc:find('CodeCompanion question', 1, true) == 1
              then
                found = map.callback
                return true
              end
            end
            return false
          end, 20)
          assert(found, 'Expected question keymap `' .. lhs .. '` to be set on the chat buffer')
          return found
        end

        function _G.press(lhs, previous)
          local callback = _G.wait_for_keymap(lhs, previous)
          callback()
          return callback
        end

        function _G.wait_for_tool_output()
          vim.wait(2000, function()
            return #chat.messages > 1
          end, 20)
        end

        function _G.buffer_text()
          return table.concat(vim.api.nvim_buf_get_lines(chat.bufnr, 0, -1, false), '\n')
        end
      ]])
    end,
    post_case = function()
      child.lua([[
        h.teardown_chat_buffer()
      ]])
    end,
    post_once = child.stop,
  },
})

T["ask_questions"] = new_set()

T["ask_questions"]["answers a free text question"] = function()
  child.lua([[
    vim.ui.input = function(opts, callback)
      callback('Use TypeScript')
    end

    local tool = {
      {
        ["function"] = {
          name = "ask_questions",
          arguments = vim.json.encode({
            questions = {
              {
                header = "Language",
                question = "Which language should I use?",
              },
            },
          }),
        },
      },
    }
    tools:execute(chat, tool)

    _G.press('gc')
    _G.wait_for_tool_output()
  ]])

  local output = child.lua_get([[chat.messages[#chat.messages].content]])
  h.expect_contains("TypeScript", output)

  local buffer = child.lua_get([[_G.buffer_text()]])
  h.expect_contains("Which language should I use?", buffer)
  h.expect_contains("You answered: Use TypeScript", buffer)
end

T["ask_questions"]["answers a single select question with a keymap"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "ask_questions",
          arguments = vim.json.encode({
            questions = {
              {
                header = "Framework",
                question = "Which framework?",
                options = {
                  { label = "React", description = "Most popular" },
                  { label = "Vue" },
                  { label = "Svelte" },
                },
              },
            },
          }),
        },
      },
    }
    tools:execute(chat, tool)

    _G.press('g1')
    _G.wait_for_tool_output()
  ]])

  local output = child.lua_get([[chat.messages[#chat.messages].content]])
  h.expect_contains("React", output)

  local buffer = child.lua_get([[_G.buffer_text()]])
  h.expect_contains("`g1` - React - Most popular", buffer)
  h.expect_contains("`g2` - Vue", buffer)

  -- The chat's own gc and gs keymaps are restored after the question is answered
  local gc_desc = child.lua_get([[
    (function()
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(chat.bufnr, 'n')) do
        if map.lhs == 'gc' then
          return map.desc
        end
      end
    end)()
  ]])
  h.eq("Insert an empty codeblock", gc_desc)
end

T["ask_questions"]["asks multiple questions in sequence"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "ask_questions",
          arguments = vim.json.encode({
            questions = {
              {
                header = "Directory",
                question = "Where should I create the files?",
                options = {
                  { label = "src/" },
                  { label = "lua/" },
                },
              },
              {
                header = "License",
                question = "Which license?",
                options = {
                  { label = "MIT" },
                  { label = "Apache" },
                },
              },
            },
          }),
        },
      },
    }
    tools:execute(chat, tool)

    local first_question = _G.press('g1')
    _G.press('g1', first_question)
    _G.wait_for_tool_output()
  ]])

  local output = child.lua_get([[chat.messages[#chat.messages].content]])
  h.expect_contains("src/", output)
  h.expect_contains("MIT", output)
end

T["ask_questions"]["answers a multi select question"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "ask_questions",
          arguments = vim.json.encode({
            questions = {
              {
                header = "Modules",
                question = "Which modules should own this logic?",
                multiSelect = true,
                options = {
                  { label = "queue" },
                  { label = "orchestrator" },
                  { label = "runner" },
                },
              },
            },
          }),
        },
      },
    }
    tools:execute(chat, tool)

    _G.press('g1') -- include queue
    _G.press('g2') -- exclude orchestrator
    _G.press('g1') -- include runner
    _G.wait_for_tool_output()
  ]])

  local output = child.lua_get([[chat.messages[#chat.messages].content]])
  h.expect_contains("queue", output)
  h.expect_contains("runner", output)
  h.eq(nil, string.match(output, "orchestrator"))

  local buffer = child.lua_get([[_G.buffer_text()]])
  h.eq(nil, string.match(buffer, "Include '"))
end

T["ask_questions"]["records a skipped question as no answer"] = function()
  child.lua([[
    local tool = {
      {
        ["function"] = {
          name = "ask_questions",
          arguments = vim.json.encode({
            questions = {
              {
                header = "Directory",
                question = "Where should I create the files?",
                options = {
                  { label = "src/" },
                },
              },
            },
          }),
        },
      },
    }
    tools:execute(chat, tool)

    _G.press('gs')
    _G.wait_for_tool_output()
  ]])

  local output = child.lua_get([[chat.messages[#chat.messages].content]])
  h.expect_contains("No answer provided", output)

  local buffer = child.lua_get([[_G.buffer_text()]])
  h.expect_contains("You skipped this question", buffer)
end

return T
