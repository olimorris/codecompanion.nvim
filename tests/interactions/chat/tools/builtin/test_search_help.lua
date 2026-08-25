local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require("tests.helpers")
        chat, tools = h.setup_chat_buffer()

        function _G.execute_search_help(arguments)
          local message_count = #chat.messages
          tools:execute(chat, {
            {
              ["function"] = {
                name = "search_help",
                arguments = vim.json.encode(arguments),
              },
            },
          })
          assert(vim.wait(2000, function()
            return #chat.messages > message_count
          end), "search_help did not produce output")

          return chat.messages[#chat.messages].content
        end
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

local function execute(arguments)
  return child.lua_get([[_G.execute_search_help(...)]], { arguments })
end

T["outline lists the chapters of the help file"] = function()
  local output = execute({ command = "outline" })

  h.expect_contains("Configuration", output)
  h.expect_contains("codecompanion-usage-chat-buffer", output)
end

T["outline scoped to a section lists its subsections"] = function()
  local output = execute({ command = "outline", section = "Usage > SLASH COMMANDS", max_level = 4 })

  h.expect_contains("/BUFFER", output)
  h.expect_contains("/SYMBOLS", output)
end

T["read returns a section verbatim when addressed by tag"] = function()
  local output = execute({ command = "read", section = "codecompanion-integrations-herdr" })

  h.expect_contains("HERDR", output)
  h.expect_contains("Integrations > HERDR", output)
end

T["read returns a section when addressed by a trailing heading path"] = function()
  local output = execute({ command = "read", section = "Integrations > HERDR" })

  h.expect_contains("codecompanion-integrations-herdr", output)
end

T["read excludes the chapter rule belonging to the next section"] = function()
  local output = execute({ command = "read", section = "codecompanion-integrations-herdr" })

  h.expect_not_contains("======", output)
end

T["read lists subsections instead of returning an oversized section"] = function()
  local output = execute({ command = "read", section = "Configuration > CHAT BUFFER" })

  h.expect_contains("Subsections:", output)
  h.expect_contains("Configuration > CHAT BUFFER > KEYMAPS", output)
end

T["read asks for disambiguation when a heading is not unique"] = function()
  local output = execute({ command = "read", section = "KEYMAPS" })

  h.expect_contains("matches", output)
  h.expect_contains("Usage > CHAT BUFFER > KEYMAPS", output)
end

T["search groups hits under the section containing them"] = function()
  local output = execute({ command = "search", query = "pertab" })

  h.expect_contains("Usage > QUICKLY ACCESSING A CHAT BUFFER", output)
  h.expect_contains("4337: ", output)
end

T["search matches literally rather than as a pattern by default"] = function()
  local output = execute({ command = "search", query = "adapter = {" })

  h.expect_contains("adapter = {", output)
  h.expect_contains("Configuration > CHAT BUFFER > CHANGING ADAPTER", output)
end

T["search treats the query as a pattern when regex is set"] = function()
  local output = execute({ command = "search", query = "codecompanion%.adapters", regex = true })

  h.expect_contains("codecompanion.adapters", output)
  h.expect_not_contains("No matches", output)
end

T["search reports when nothing matches"] = function()
  local output = execute({ command = "search", query = "zzzznotinthedocszzzz" })

  h.expect_contains("No matches", output)
end

return T
