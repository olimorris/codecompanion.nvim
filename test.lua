
require("codecompanion.config").register_prompt("test register_prompt with references", {
  -- TODO: define a chat name to make it easier when trying to find it with `OpenChat`
  strategy = "chat",
  description = "Add some references",
  opts = {
    index = 11,
    is_default = true,
    is_slash_cmd = false,
    short_name = "ref",
    auto_submit = false,
  },
  -- These will appear at the top of the chat buffer
  references = {
    {
      type = "file",
      path = { -- This can be a string or a table of values
        "lua/codecompanion/health.lua",
        "lua/codecompanion/http.lua",
      },
    },
    {
      type = "file",
      path = "lua/codecompanion/schema.lua",
    },
    {
      type = "symbols",
      path = "lua/codecompanion/strategies/chat/init.lua",
    },
    {
      type = "url", -- This URL will even be cached for you!
      url = "https://raw.githubusercontent.com/olimorris/codecompanion.nvim/refs/heads/main/lua/codecompanion/commands.lua",
    },
  },
  prompts = {
    {
      role = "user",
      content = "I'll think of something clever to put here...",
      opts = {
        contains_code = true,
      },
    },
  },
})

-- it will be good if we can provide an api which takes in the same input type `CodeCompanion.PromptConfig`
-- Then user can write this into their config with a shortcut or custom command
-- e.g.
--
-- local myChat = require("codecompanion").chat({
--   strategy = "chat",
--   description = "Add some references",
--   opts = {
--   },
--   -- These will appear at the top of the chat buffer
--   references = {
--   },
--   prompts = {
--   },
-- })
--
-- vim.keymap.set("n", "<leader>xxxx", myChat, {})
