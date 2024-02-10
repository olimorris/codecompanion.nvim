local M = {}

local defaults = {
  api_key = "OPENAI_API_KEY",
  org_api_key = "OPENAI_ORG_KEY",
  base_url = "https://api.openai.com",
  ai_settings = {
    advisor = {
      model = "gpt-4-0125-preview",
      temperature = 1,
      top_p = 1,
      stop = nil,
      max_tokens = nil,
      presence_penalty = 0,
      frequency_penalty = 0,
      logit_bias = nil,
      user = nil,
    },
    inline = {
      model = "gpt-3.5-turbo-0125",
      temperature = 1,
      top_p = 1,
      stop = nil,
      max_tokens = nil,
      presence_penalty = 0,
      frequency_penalty = 0,
      logit_bias = nil,
      user = nil,
    },
    chat = {
      model = "gpt-4-0125-preview",
      temperature = 1,
      top_p = 1,
      stop = nil,
      max_tokens = nil,
      presence_penalty = 0,
      frequency_penalty = 0,
      logit_bias = nil,
      user = nil,
    },
  },
  saved_chats = {
    save_dir = vim.fn.stdpath("data") .. "/codecompanion/saved_chats",
  },
  display = {
    action_palette = {
      width = 95,
      height = 10,
    },
    advisor = {
      stream = true,
    },
    chat = {
      type = "float",
      show_settings = false,
      show_token_count = true,
      buf_options = {
        buflisted = false,
      },
      float_options = {
        border = "single",
        max_height = 0,
        max_width = 0,
        padding = 1,
      },
      win_options = {
        cursorcolumn = false,
        cursorline = false,
        foldcolumn = "0",
        linebreak = true,
        list = false,
        signcolumn = "no",
        spell = false,
        wrap = true,
      },
    },
  },
  keymaps = {
    ["<C-s>"] = "keymaps.save",
    ["<C-c>"] = "keymaps.close",
    ["q"] = "keymaps.cancel_request",
    ["gc"] = "keymaps.clear",
    ["ga"] = "keymaps.codeblock",
    ["gs"] = "keymaps.save_chat",
    ["]"] = "keymaps.next",
    ["["] = "keymaps.previous",
  },
  intro_message = "Welcome to CodeCompanion ✨! Save the buffer to send a message to OpenAI...",
  log_level = "ERROR",
  send_code = true,
  silence_notifications = false,
  use_default_actions = true,
}

---@param opts nil|table
M.setup = function(opts)
  M.options = vim.tbl_deep_extend("force", {}, defaults, opts or {})

  M.INFO_NS = vim.api.nvim_create_namespace("CodeCompanion-info")
  M.ERROR_NS = vim.api.nvim_create_namespace("CodeCompanion-error")

  local log = require("codecompanion.utils.log")
  log.set_root(log.new({
    handlers = {
      {
        type = "echo",
        level = vim.log.levels.WARN,
      },
      {
        type = "file",
        filename = "codecompanion.log",
        level = vim.log.levels[M.options.log_level],
      },
    },
  }))

  vim.treesitter.language.register("markdown", "codecompanion")

  local diagnostic_config = {
    underline = false,
    virtual_text = {
      severity = { min = vim.diagnostic.severity.INFO },
    },
    signs = false,
  }
  vim.diagnostic.config(diagnostic_config, M.INFO_NS)
  vim.diagnostic.config(diagnostic_config, M.ERROR_NS)
end

return M
