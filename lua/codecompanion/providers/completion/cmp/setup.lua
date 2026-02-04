local config = require("codecompanion.config")

local cmp = require("cmp")

vim.api.nvim_create_autocmd("FileType", {
  pattern = "codecompanion",
  callback = function()
    local completion = "codecompanion.providers.completion.cmp"
    cmp.register_source("codecompanion_acp_commands", require(completion .. ".acp_commands").new(config))
    cmp.register_source("codecompanion_editor_context", require(completion .. ".editor_context").new())
    cmp.register_source("codecompanion_models", require(completion .. ".models").new(config))
    cmp.register_source("codecompanion_slash_commands", require(completion .. ".slash_commands").new(config))
    cmp.register_source("codecompanion_tools", require(completion .. ".tools").new(config))
    cmp.setup.filetype("codecompanion", {
      enabled = true,
      sources = vim.list_extend({
        { name = "codecompanion_acp_commands" },
        { name = "codecompanion_editor_context" },
        { name = "codecompanion_models" },
        { name = "codecompanion_slash_commands" },
        { name = "codecompanion_tools" },
      }, cmp.get_config().sources),
    })
    -- returning true will remove this autocmd
    -- now that the completion sources are registered
    return true
  end,
})
