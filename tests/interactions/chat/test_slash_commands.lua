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
        resume_command = require("codecompanion.interactions.chat.slash_commands.builtin.resume")
      ]])
    end,
    post_once = child.stop,
  },
})

T["Slash Commands"] = new_set()
T["Slash Commands"]["mode"] = new_set()
T["Slash Commands"]["resume"] = new_set()

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

T["Slash Commands"]["mode"]["mode command bootstraps an ACP session and refreshes chat metadata even when the picker is cancelled"] = function()
  local result = child.lua([[
      _G.ensure_acp_session_calls = 0

      local helpers = require("codecompanion.interactions.chat.helpers")
      local original_ensure_acp_session = helpers.ensure_acp_session
      helpers.ensure_acp_session = function(chat)
        _G.ensure_acp_session_calls = _G.ensure_acp_session_calls + 1
        return true
      end

      local chat = {
        metadata_updates = 0,
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
            error("set_mode should not be called when the picker is cancelled")
          end,
        },
        update_metadata = function(self)
          self.metadata_updates = self.metadata_updates + 1
        end,
      }

      local original_select = vim.ui.select
      vim.ui.select = function(choices, opts, cb)
        cb(nil)
      end

      mode_command.new({ Chat = chat }):execute()

      vim.ui.select = original_select
      helpers.ensure_acp_session = original_ensure_acp_session

      return {
        ensured = _G.ensure_acp_session_calls,
        metadata_updates = chat.metadata_updates,
      }
    ]])

  h.eq(result.ensured, 1)
  h.eq(result.metadata_updates, 1)
end

T["Slash Commands"]["resume"]["relinks the buffer and refreshes chat metadata after loading a session"] = function()
  local result = child.lua([[
      local calls = {
        link = 0,
        load_session = 0,
        restore = 0,
      }

      local helpers = require("codecompanion.interactions.chat.helpers")
      local render = require("codecompanion.interactions.chat.acp.render")
      local original_link = helpers.link_buffer_to_acp_session
      local original_restore = render.restore_session

      helpers.link_buffer_to_acp_session = function(chat)
        calls.link = calls.link + 1
        return true
      end

      render.restore_session = function(chat, updates)
        calls.restore = calls.restore + 1
        calls.update_count = #updates
      end

      local chat = {
        cycle = 1,
        metadata_updates = 0,
        acp_connection = {
          session_list = function(self, opts)
            calls.max_sessions = opts.max_sessions
            return {
              { sessionId = "test-session", title = "Saved Session" },
            }
          end,
          load_session = function(self, session_id, opts)
            calls.load_session = calls.load_session + 1
            calls.loaded_session_id = session_id
            self.session_id = session_id
            opts.on_session_update({ sessionUpdate = "agent_message_chunk" })
            return true
          end,
        },
        set_title = function(self, title)
          self.title = title
        end,
        update_metadata = function(self)
          self.metadata_updates = self.metadata_updates + 1
        end,
      }

      local original_select = vim.ui.select
      vim.ui.select = function(choices, opts, cb)
        calls.prompt = opts.prompt
        calls.choice_count = #choices
        cb(choices[1], 1)
      end

      resume_command.new({ Chat = chat, config = {} }):execute()

      vim.ui.select = original_select
      helpers.link_buffer_to_acp_session = original_link
      render.restore_session = original_restore

      return {
        link_calls = calls.link,
        load_session_calls = calls.load_session,
        restore_calls = calls.restore,
        loaded_session_id = calls.loaded_session_id,
        max_sessions = calls.max_sessions,
        prompt = calls.prompt,
        choice_count = calls.choice_count,
        update_count = calls.update_count,
        metadata_updates = chat.metadata_updates,
        title = chat.title,
      }
    ]])

  h.eq(result.link_calls, 1)
  h.eq(result.load_session_calls, 1)
  h.eq(result.restore_calls, 1)
  h.eq(result.loaded_session_id, "test-session")
  h.eq(result.max_sessions, 500)
  h.eq(result.prompt, "Resume Session")
  h.eq(result.choice_count, 1)
  h.eq(result.update_count, 1)
  h.eq(result.metadata_updates, 1)
  h.eq(result.title, "Saved Session")
end

return T
