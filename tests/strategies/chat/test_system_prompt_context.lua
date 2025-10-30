local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        _G.h = require('tests.helpers')
        _G.chat, _ = h.setup_chat_buffer({
          display = {
            chat = {
            },
          },
        })
        ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["System prompt"] = new_set()

T["System prompt"]["can load static components"] = function()
  ---@type CodeCompanion.SystemPrompt.Context
  local context = child.lua([[
    return _G.chat:make_system_prompt_ctx()
  ]])
  h.eq(vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch, context.nvim_version)
end

T["System prompt"]["can load dynamic components"] = function()
  local context_os = child.lua([[
    return _G.chat:make_system_prompt_ctx().os
  ]])

  local machine = vim.uv.os_uname().sysname
  if machine == "Darwin" then
    machine = "Mac"
  end
  if machine:find("Windows") then
    machine = "Windows"
  end
  h.eq(machine, context_os)
end

return T
