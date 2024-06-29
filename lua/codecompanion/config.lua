local utils = require("codecompanion.utils.util")

return {
  adapters = {
    anthropic = "anthropic",
    ollama = "ollama",
    openai = "openai",
  },
  strategies = {
    chat = "openai",
    inline = "openai",
    agent = "openai",
  },
  prompts = {
    ["Custom Prompt"] = {
      strategy = "inline",
      description = "Send a custom prompt to the LLM",
      opts = {
        index = 1,
        default_prompt = true,
        mapping = "<LocalLeader>cc",
        user_prompt = true,
      },
      prompts = {
        {
          role = "system",
          content = function(context)
            if context.buftype == "terminal" then
              return "I want you to act as an expert in writing terminal commands that will work for my current shell "
                .. os.getenv("SHELL")
                .. ". I will ask you specific questions and I want you to return the raw command only (no codeblocks and explanations). If you can't respond with a command, respond with nothing"
            end
            return "I want you to act as a senior "
              .. context.filetype
              .. " developer. I will ask you specific questions and I want you to return raw code only (no codeblocks and no explanations). If you can't respond with code, respond with nothing"
          end,
        },
      },
    },
    ["Senior Developer"] = {
      strategy = "chat",
      name_f = function(context)
        return "Senior " .. utils.capitalize(context.filetype) .. " Developer"
      end,
      description = function(context)
        local filetype
        if context and context.filetype then
          filetype = utils.capitalize(context.filetype)
        end
        return "Chat with a senior " .. (filetype or "") .. " developer"
      end,
      opts = {
        index = 2,
        default_prompt = true,
        modes = { "n", "v" },
        mapping = "<LocalLeader>ce",
        auto_submit = false,
      },
      prompts = {
        {
          role = "system",
          content = function(context)
            return "I want you to act as an expert and senior developer in the "
              .. context.filetype
              .. " language. I will ask you questions, perhaps giving you code examples, and I want you to advise me with explanations and code where neccessary."
          end,
        },
        {
          role = "user",
          contains_code = true,
          condition = function(context)
            return context.is_visual
          end,
          content = function(context)
            local text = require("codecompanion.helpers.code").get_code(context.start_line, context.end_line)

            return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
          end,
        },
        {
          role = "user",
          condition = function(context)
            return not context.is_visual
          end,
          content = "\n \n",
        },
      },
    },
    ["Code Advisor"] = {
      strategy = "chat",
      description = "Get advice on the code you've selected",
      opts = {
        index = 3,
        default_prompt = true,
        mapping = "<LocalLeader>ca",
        modes = { "v" },
        shortcut = "advisor",
        auto_submit = true,
        user_prompt = true,
      },
      prompts = {
        {
          role = "system",
          content = function(context)
            return "I want you to act as a senior "
              .. context.filetype
              .. " developer. I will ask you specific questions and I want you to return concise explanations and codeblock examples."
          end,
        },
        {
          role = "user",
          contains_code = true,
          content = function(context)
            local text = require("codecompanion.helpers.code").get_code(context.start_line, context.end_line)

            return "I have the following code:\n\n```" .. context.filetype .. "\n" .. text .. "\n```\n\n"
          end,
        },
      },
    },
    ["Explain LSP Diagnostics"] = {
      strategy = "chat",
      description = "Use an LLM to explain any LSP diagnostics",
      opts = {
        index = 4,
        default_prompt = true,
        mapping = "<LocalLeader>cl",
        modes = { "v" },
        shortcut = "lsp",
        auto_submit = true,
        user_prompt = false, -- Prompt the user for their own input
      },
      prompts = {
        {
          role = "system",
          content = [[You are an expert coder and helpful assistant who can help debug code diagnostics, such as warning and error messages. When appropriate, give solutions with code snippets as fenced codeblocks with a language identifier to enable syntax highlighting.]],
        },
        {
          role = "user",
          content = function(context)
            local diagnostics =
              require("codecompanion.helpers.lsp").get_diagnostics(context.start_line, context.end_line, context.bufnr)

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
          contains_code = true,
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
    ["Generate a Commit Message"] = {
      strategy = "chat",
      description = "Generate a commit message",
      opts = {
        index = 5,
        default_prompt = true,
        mapping = "<LocalLeader>cm",
        shortcut = "commit",
        auto_submit = true,
      },
      prompts = {
        {
          role = "user",
          contains_code = true,
          content = function()
            return "You are an expert at following the Conventional Commit specification. Given the git diff listed below, please generate a commit message for me:"
              .. "\n\n```\n"
              .. vim.fn.system("git diff")
              .. "\n```"
          end,
        },
      },
    },
  },
  agents = {
    ["code_runner"] = {
      name = "Code Runner",
      description = "Run code generated by the LLM",
      enabled = true,
    },
    ["rag"] = {
      name = "RAG",
      description = "Supplement the LLM with real-time information",
      enabled = true,
    },
    opts = {
      auto_submit_errors = false,
      mute_errors = false,
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
    chat = {
      window = {
        layout = "vertical", -- float|vertical|horizontal|buffer
        border = "single",
        height = 0.8,
        width = 0.45,
        relative = "editor",
        opts = {
          breakindent = true,
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
      intro_message = "Welcome to CodeCompanion ✨! Save the buffer to send a message...",
      show_settings = true,
      show_token_count = true,
    },
    inline = {
      show_diff = false,
    },
  },
  keymaps = {
    chat = {
      ["<C-s>"] = "keymaps.save",
      ["<C-c>"] = "keymaps.close",
      ["q"] = "keymaps.stop",
      ["gc"] = "keymaps.clear",
      ["ga"] = "keymaps.codeblock",
      ["gs"] = "keymaps.save_chat",
      ["gt"] = "keymaps.add_agent",
      ["]"] = "keymaps.next",
      ["["] = "keymaps.previous",
    },
    inline = {
      ["gc"] = "keymaps.clear_diff",
    },
  },
  default_prompts = {
    inline_to_chat = function(context)
      return "I want you to act as an expert and senior developer in the "
        .. context.filetype
        .. " language. I will ask you questions, perhaps giving you code examples, and I want you to advise me with explanations and code where neccessary."
    end,
    system = string.format(
      [[You are an AI programming assistant named "CodeCompanion," built by Oli Morris. Follow the user's requirements carefully and to the letter. Your expertise is strictly limited to software development topics. Avoid content that violates copyrights. For questions not related to the general topic of software development, remind the user that you are an AI programming assistant. Keep your answers short and impersonal.

You can answer general programming questions and perform the following tasks:
- Ask questions about the files in your current workspace
- Explain how the selected code works
- Generate unit tests for the selected code
- Propose a fix for problems in the selected code
- Scaffold code for a new feature
- Ask questions about Neovim
- Ask how to do something in the terminal

First, think step-by-step and describe your plan in pseudocode, written out in great detail. Then, output the code in a single code block. Minimize any other prose. Use Markdown formatting in your answers, and include the programming language name at the start of the Markdown code blocks. Avoid wrapping the whole response in triple backticks. The user works in a text editor called Neovim and the version is %d.%d.%d. Neovim has concepts for editors with open files, integrated unit test support, an output pane for running code, and an integrated terminal. The active document is the source code the user is looking at right now. You can only give one reply for each conversation turn.

You also have access to agents that you can use to initiate actions on the user's machine:
- Code Runner: To run any code that you've generated and receive the output
- RAG: To supplement your responses with real-time information and insight

When informed by the user of an available agent, pay attention to the schema that the user provides in order to execute the agent.]],
      vim.version().major,
      vim.version().minor,
      vim.version().patch
    ),
  },
  log_level = "ERROR",
  send_code = true,
  silence_notifications = false,
  use_default_actions = true,
  use_default_prompts = true,
}
