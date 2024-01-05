local M = {}

local defaults = {
  api_key = "OPENAI_API_KEY",
  org_api_key = "OPENAI_ORG_KEY",
  log_level = "TRACE",
  conversations = {
    auto_save = true,
    save_dir = vim.fn.stdpath("data") .. "/codecompanion/conversations",
  },
  actions = {
    {
      name = "Chat",
      strategy = "chat",
      description = "Open a new chat buffer to converse with the Completions API",
      opts = {
        modes = { "n" },
      },
    },
    {
      name = "Chat with selection",
      strategy = "chat",
      description = "Paste your selected text into a new chat buffer",
      opts = {
        modes = { "v" },
      },
      prompts = {
        {
          role = "system",
          content = function(context)
            return "I want you to act as a senior "
              .. context.filetype
              .. " developer. I will give you specific code examples and ask you questions. I want you to advise me with explanations and code examples."
          end,
        },
        {
          role = "user",
          content = function(context)
            local text =
              require("codecompanion.helpers.code").get_code(context.start_line, context.end_line)

            return "I have the following code:\n\n```"
              .. context.filetype
              .. "\n"
              .. text
              .. "\n```\n\n"
          end,
        },
      },
    },
    {
      name = "Code Author",
      strategy = "author",
      description = "Get the Completions API to write/refactor code for you",
      opts = {
        model = "gpt-4-1106-preview",
        modes = { "n", "v" },
        user_input = true,
        send_visual_selection = true,
      },
      prompts = {
        {
          role = "system",
          content = [[I want you to act as a senior %s developer. I will ask you specific questions and I want you to return raw code only (no codeblocks and no explanations). If you can't respond with code, just say "Error - I don't know".]],
          variables = {
            "filetype",
          },
        },
      },
    },
    {
      name = "Code Advisor",
      strategy = "advisor",
      description = "Get advice on the code you've selected",
      opts = {
        model = "gpt-4-1106-preview",
        modes = { "v" },
        user_input = true,
        send_visual_selection = true,
        display = {
          type = "popup",
        },
      },
      prompts = {
        {
          role = "system",
          content = [[I want you to act as a senior %s developer. I will ask you specific questions and I want you to advise me with explanations and code examples. If you can't respond, just say "Error - I don't know".]],
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
        display = {
          type = "popup",
          width = 0.8,
          height = 0.7,
        },
      },
      prompts = {
        {
          role = "system",
          content = [[You are an expert coder and helpful assistant who can help debug code diagnostics, such as warning and error messages. When appropriate, give solutions with code snippets as fenced codeblocks with a language identifier to enable syntax highlighting. If you can't respond with an answer, just say "Error - I don't know".]],
        },
        {
          role = "user",
          content = function(context)
            local diagnostics = require("codecompanion.helpers.lsp").get_diagnostics(
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
                .. "\n  - Location: Line "
                .. diagnostic.line_number
                .. "\n  - Severity: "
                .. diagnostic.severity
                .. "\n  - Message: "
                .. diagnostic.message
                .. "\n"
            end

            return "The programming language is "
              .. context.filetype
              .. ". This is a list of the diagnostic messages:\n\n"
              .. concatenated_diagnostics
          end,
        },
        {
          role = "user",
          content = function(context)
            return "This is the code, for context:\n\n"
              .. "```"
              .. context.filetype
              .. "\n"
              .. require("codecompanion.helpers.code").get_code(
                context.start_line,
                context.end_line,
                { show_line_numbers = true }
              )
              .. "\n```\n\n"
          end,
        },
      },
    },
    {
      name = "Load Conversations",
      strategy = "conversations",
      description = "Load your previous Chat conversations",
    },
  },
}

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
