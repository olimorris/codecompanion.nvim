local M = {}

local defaults = {
  api_key = "OPENAI_API_KEY",
  org_api_key = "OPENAI_ORG_KEY",
  log_level = "TRACE",
  display = {
    type = "popup",
    width = 0.8,
    height = 0.7,
  },
  actions = {
    {
      name = "Chat",
      strategy = "chat",
      description = "Open a chat buffer to converse with the Completions API",
      opts = {
        modes = { "n" },
      },
    },
    {
      name = "Code Companion",
      strategy = "author",
      description = "Prompt the Completions API to write/refactor code",
      opts = {
        model = "gpt-4-1106-preview",
        modes = { "n", "v" },
        user_input = true,
      },
      prompts = {
        [1] = {
          role = "system",
          content = [[I want you to act as a senior %s developer. I will ask you specific questions and I want you to return raw code only (no codeblocks and no explanations).
            If you can't respond with code, just say "Error - I don't know".]],
          variables = {
            "filetype",
          },
        },
      },
    },
    {
      name = "Code Advisor",
      strategy = "advisor",
      description = "Get advise on selected code",
      opts = {
        model = "gpt-4-1106-preview",
        modes = { "v" },
        user_input = true,
        send_visual_selection = true,
      },
      prompts = {
        [1] = {
          role = "system",
          content = [[I want you to act as a senior %s developer. I will ask you specific questions and I want you to advise me with explanations and code examples.
            If you can't respond, just say "Error - I don't know".]],
          variables = {
            "filetype",
          },
        },
      },
    },
    {
      name = "LSP Assistant",
      strategy = "advisor",
      description = "Get help from the Completions API to fix LSP diagnostics",
      opts = {
        model = "gpt-4-1106-preview",
        modes = { "v" },
        user_input = false, -- Prompt the user for their own input
        send_visual_selection = false, -- No need to send the visual selection as we do this in prompt 3
      },
      prompts = {
        [1] = {
          role = "system",
          content = [[You are an expert coder and helpful assistant who can help debug code diagnostics, such as warning and error messages.
            When appropriate, give solutions with code snippets as fenced codeblocks with a language identifier to enable syntax highlighting.
            If you can't respond with an answer, just say "Error - I don't know".]],
        },
        [2] = {
          role = "user",
          content = function(context)
            local diagnostics = require("openai.helpers.lsp").get_diagnostics(
              context.start_line,
              context.end_line,
              context.bufnr
            )

            local concatenated_diagnostics = ""
            for i, diagnostic in ipairs(diagnostics) do
              concatenated_diagnostics = concatenated_diagnostics
                .. i
                .. ". Issue "
                .. i
                .. "\n\t- Location: Line "
                .. diagnostic.line_number
                .. "\n\t- Severity: "
                .. diagnostic.severity
                .. "\n\t- Message: "
                .. diagnostic.message
                .. "\n"
            end

            return "The programming language is "
              .. context.filetype
              .. ".\nThis is a list of the diagnostic messages:\n"
              .. concatenated_diagnostics
          end,
        },
        [3] = {
          role = "user",
          content = function(context)
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
