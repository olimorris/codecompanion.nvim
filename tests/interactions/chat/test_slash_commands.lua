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
        resume_command = require("codecompanion.interactions.chat.slash_commands.builtin.resume")
      ]])
    end,
    post_once = child.stop,
  },
})

T["Slash Commands"] = new_set()
T["Slash Commands"]["resume"] = new_set()

T["Slash Commands"]["resume"]["fires the resumed event after loading a session"] = function()
  local result = child.lua([[
      local calls = {
        event_count = 0,
        link = 0,
        load_session = 0,
        restore = 0,
      }

      vim.api.nvim_create_autocmd("User", {
        pattern = "CodeCompanionChatACPResumed",
        once = true,
        callback = function(args)
          calls.event_count = calls.event_count + 1
          calls.event = args.data
        end,
      })

      local acp_commands = require("codecompanion.interactions.chat.acp.commands")
      local render = require("codecompanion.interactions.chat.acp.render")
      local original_link = acp_commands.link_buffer_to_session
      local original_restore = render.restore_session

      acp_commands.link_buffer_to_session = function(bufnr, session_id)
        calls.link = calls.link + 1
        calls.linked_bufnr = bufnr
        calls.linked_session_id = session_id
      end

      render.restore_session = function(chat, updates)
        calls.restore = calls.restore + 1
        calls.update_count = #updates
      end

      local chat = {
        bufnr = 99,
        cycle = 1,
        id = 123,
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
      }

      local original_select = vim.ui.select
      vim.ui.select = function(choices, opts, cb)
        calls.prompt = opts.prompt
        calls.choice_count = #choices
        cb(choices[1], 1)
      end

      resume_command.new({ Chat = chat, config = {} }):execute()

      vim.ui.select = original_select
      acp_commands.link_buffer_to_session = original_link
      render.restore_session = original_restore

      return {
        link_calls = calls.link,
        linked_bufnr = calls.linked_bufnr,
        linked_session_id = calls.linked_session_id,
        load_session_calls = calls.load_session,
        restore_calls = calls.restore,
        loaded_session_id = calls.loaded_session_id,
        max_sessions = calls.max_sessions,
        prompt = calls.prompt,
        choice_count = calls.choice_count,
        update_count = calls.update_count,
        event_count = calls.event_count,
        event = calls.event,
        title = chat.title,
      }
    ]])

  h.eq(result.link_calls, 1)
  h.eq(result.linked_bufnr, 99)
  h.eq(result.linked_session_id, "test-session")
  h.eq(result.load_session_calls, 1)
  h.eq(result.restore_calls, 1)
  h.eq(result.loaded_session_id, "test-session")
  h.eq(result.max_sessions, 500)
  h.eq(result.prompt, "Resume Session")
  h.eq(result.choice_count, 1)
  h.eq(result.update_count, 1)
  h.eq(result.event_count, 1)
  h.eq(result.event, {
    bufnr = 99,
    id = 123,
    session_id = "test-session",
    title = "Saved Session",
  })
  h.eq(result.title, "Saved Session")
end

T["Slash Commands"]["resume"]["does not fire the resumed event when loading a session fails"] = function()
  local result = child.lua([[
      local calls = {
        event_count = 0,
      }

      vim.api.nvim_create_autocmd("User", {
        pattern = "CodeCompanionChatACPResumed",
        callback = function()
          calls.event_count = calls.event_count + 1
        end,
      })

      local chat = {
        cycle = 1,
        acp_connection = {
          session_list = function(self, opts)
            return {
              { sessionId = "test-session", title = "Saved Session" },
            }
          end,
          load_session = function(self, session_id, opts)
            self.session_id = session_id
            return false
          end,
        },
      }

      local original_select = vim.ui.select
      vim.ui.select = function(choices, opts, cb)
        cb(choices[1], 1)
      end

      resume_command.new({ Chat = chat, config = {} }):execute()

      vim.ui.select = original_select

      return {
        event_count = calls.event_count,
      }
    ]])

  h.eq(result.event_count, 0)
end

return T
