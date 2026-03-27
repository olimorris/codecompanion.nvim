local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        h.setup_plugin()
        mode_command = require("codecompanion.interactions.chat.slash_commands.builtin.mode")
      ]])
    end,
    post_once = child.stop,
  },
})

T["Slash Commands"] = new_set()
T["Slash Commands"]["mode"] = new_set()

T["Slash Commands"]["mode"]["ensures an ACP session before listing modes"] = function()
  local result = child.lua([[
    _G.ensure_acp_session_calls = 0

    local helpers = require("codecompanion.interactions.chat.helpers")
    local original_ensure_acp_session = helpers.ensure_acp_session
    helpers.ensure_acp_session = function(chat)
      _G.ensure_acp_session_calls = _G.ensure_acp_session_calls + 1
      return true
    end

    local prompts = {}

    local chat = {
      acp_connection = {
        session_id = "test-session",
        _modes = { currentModeId = "ask" },
        get_modes = function(self)
          return {
            currentModeId = "ask",
            availableModes = {
              { id = "ask", name = "Ask" },
              { id = "code", name = "Code" },
            },
          }
        end,
        set_mode = function(self, mode_id)
          self._modes.currentModeId = mode_id
          return true
        end,
      },
    }

    local original_select = vim.ui.select
    vim.ui.select = function(choices, opts, cb)
      prompts.prompt = opts.prompt
      prompts.count = #choices
    end

    mode_command.new({ Chat = chat }):execute()

    vim.ui.select = original_select
    helpers.ensure_acp_session = original_ensure_acp_session

    return {
      ensured = _G.ensure_acp_session_calls,
      prompt = prompts.prompt,
      choice_count = prompts.count,
    }
  ]])

  h.eq(result.ensured, 1)
  h.eq(result.prompt, "Select Session Mode")
  h.eq(result.choice_count, 2)
end

return T
