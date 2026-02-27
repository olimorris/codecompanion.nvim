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

T["ask_questions"]["asks a free text question via vim.ui.input"] = function()
  child.lua([[
    -- Mock vim.ui.input to auto-respond
    vim.ui.input = function(opts, callback)
      callback("Use TypeScript")
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
    vim.wait(1000, function()
      return #chat.messages > 1
    end, 50)
  ]])

  local last_msg = child.lua_get([[chat.messages[#chat.messages].content]])
  h.expect_contains("TypeScript", last_msg)
end

T["ask_questions"]["asks a question with options via vim.ui.select"] = function()
  child.lua([[
    -- Mock vim.ui.select to pick the first option
    vim.ui.select = function(items, opts, callback)
      callback(items[1])
    end

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
                  { label = "React" },
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
    vim.wait(1000, function()
      return #chat.messages > 1
    end, 50)
  ]])

  local last_msg = child.lua_get([[chat.messages[#chat.messages].content]])
  h.expect_contains("React", last_msg)
end

T["ask_questions"]["handles multiple questions"] = function()
  child.lua([[
    local question_count = 0
    vim.ui.input = function(opts, callback)
      question_count = question_count + 1
      if question_count == 1 then
        callback("src/")
      else
        callback("MIT")
      end
    end

    local tool = {
      {
        ["function"] = {
          name = "ask_questions",
          arguments = vim.json.encode({
            questions = {
              {
                header = "Directory",
                question = "Where should I create the files?",
              },
              {
                header = "License",
                question = "Which license?",
              },
            },
          }),
        },
      },
    }
    tools:execute(chat, tool)
    vim.wait(1000, function()
      return #chat.messages > 1
    end, 50)
  ]])

  local last_msg = child.lua_get([[chat.messages[#chat.messages].content]])
  h.expect_contains("src/", last_msg)
  h.expect_contains("MIT", last_msg)
end

return T
