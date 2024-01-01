local M = {}

local defaults = {
  api_key = "OPENAI_API_KEY",
  org_api_key = "OPENAI_ORG_KEY",
  log_level = "TRACE",
  display = {
    type = "popup",
    width = 0.8,
    height = 0.8,
  },
  commands = {
    {
      name = "Chat",
      strategy = "chat",
      description = "Open a chat buffer to converse with the OpenAI Completions API",
      opts = {
        modes = { "n" },
      },
    },
    {
      name = "Code Companion",
      strategy = "author",
      description = "Prompt the OpenAI assistant to write/refactor some code",
      opts = {
        model = "gpt-4-1106-preview",
        modes = { "n", "v" },
        user_input = true,
      },
      prompts = {
        [1] = {
          role = "system",
          message = [[I want you to act as a senior %s developer. I will ask you specific questions and I want you to return raw code only (no codeblocks and no explanations)]],
          variables = {
            "filetype",
          },
        },
      },
    },
    {
      name = "LSP Assistant",
      strategy = "advisor",
      description = "Get help from the OpenAI Completions API to fix LSP diagnostics",
      opts = {
        model = "gpt-4-1106-preview",
        modes = { "v" },
        user_input = false,
      },
      prompts = {
        [1] = {
          role = "system",
          message = [[
            You are an expert coder and helpful assistant who can help debug code diagnostics, such as warning and error messages.
            When appropriate, give solutions with code snippets as fenced codeblocks with a language identifier to enable syntax highlighting
          ]],
        },
        [2] = {
          role = "user",
          message = function(context)
            local formatted_diagnostics = require("openai.helpers.lsp").get_diagnostics(context)

            return "The programming language is "
              .. context.filetype
              .. ".\nThis is a list of the diagnostic messages:\n"
              .. formatted_diagnostics
          end,
        },
        [3] = {
          role = "user",
          message = function(context)
            return "This is the code, for context:\n"
              .. require("openai.helpers.code").get_code(context.start_line, context.end_line)
          end,
        },
      },
    },
  },
}

M.setup = function(opts)
  M.config = vim.tbl_deep_extend("force", {}, defaults, opts or {})

  M.INFO_NS = vim.api.nvim_create_namespace("OpenAI-info")
  M.ERROR_NS = vim.api.nvim_create_namespace("OpenAI-error")

  local log = require("openai.utils.log")
  log.set_root(log.new({
    handlers = {
      {
        type = "echo",
        level = vim.log.levels.WARN,
      },
      {
        type = "file",
        filename = "openai.log",
        level = vim.log.levels[M.config.log_level],
      },
    },
  }))

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
