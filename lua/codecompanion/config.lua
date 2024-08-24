local utils = require("codecompanion.utils.util")

return {
  adapters = {
    anthropic = "anthropic",
    gemini = "gemini",
    ollama = "ollama",
    openai = "openai",
  },
  strategies = {
    -- CHAT STRATEGY ----------------------------------------------------------
    chat = {
      adapter = "openai",
      roles = {
        llm = "CodeCompanion", -- The markdown header content for the LLM's responses
        user = "Me", -- The markdown header for your questions
      },
      variables = {
        ["buffer"] = {
          callback = "helpers.variables.buffer",
          description = "Share the current buffer with the LLM",
          opts = {
            contains_code = true,
            has_params = true,
          },
        },
        ["buffers"] = {
          callback = "helpers.variables.buffers",
          description = "Share all current open buffers with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["editor"] = {
          callback = "helpers.variables.editor",
          description = "Share the code that you see in Neovim",
          opts = {
            contains_code = true,
          },
        },
        ["lsp"] = {
          callback = "helpers.variables.lsp",
          contains_code = true,
          description = "Share LSP information and code for the current buffer",
        },
      },
      keymaps = {
        options = {
          modes = {
            n = "?",
          },
          callback = "keymaps.options",
          description = "Options",
          hide = true,
        },
        send = {
          modes = {
            n = { "<CR>", "<C-s>" },
            i = "<C-s>",
          },
          index = 1,
          callback = "keymaps.send",
          description = "Send",
        },
        close = {
          modes = {
            n = "<C-c>",
            i = "<C-c>",
          },
          index = 2,
          callback = "keymaps.close",
          description = "Close Chat",
        },
        stop = {
          modes = {
            n = "q",
          },
          index = 3,
          callback = "keymaps.stop",
          description = "Stop Request",
        },
        clear = {
          modes = {
            n = "gx",
          },
          index = 4,
          callback = "keymaps.clear",
          description = "Clear Chat",
        },
        codeblock = {
          modes = {
            n = "gc",
          },
          index = 6,
          callback = "keymaps.codeblock",
          description = "Insert Codeblock",
        },
        next_chat = {
          modes = {
            n = "}",
          },
          index = 8,
          callback = "keymaps.next_chat",
          description = "Next Chat",
        },
        previous_chat = {
          modes = {
            n = "{",
          },
          index = 9,
          callback = "keymaps.previous_chat",
          description = "Previous Chat",
        },
        next_header = {
          modes = {
            n = "]",
          },
          index = 10,
          callback = "keymaps.next_header",
          description = "Next Header",
        },
        previous_header = {
          modes = {
            n = "[",
          },
          index = 11,
          callback = "keymaps.previous_header",
          description = "Previous Header",
        },
        change_adapter = {
          modes = {
            n = "ga",
          },
          index = 12,
          callback = "keymaps.change_adapter",
          description = "Change adapter",
        },
        debug = {
          modes = {
            n = "gd",
          },
          index = 13,
          callback = "keymaps.debug",
          description = "View debug info",
        },
      },
      callbacks = {
        on_submit = function(chat) end, -- For when a request has been submited
        on_complete = function(chat) end, -- For when a request has completed
      },
    },
    -- INLINE STRATEGY --------------------------------------------------------
    inline = {
      adapter = "openai",
      keymaps = {
        accept_change = {
          modes = {
            n = "ga",
          },
          index = 1,
          callback = "keymaps.accept_change",
          description = "Accept change",
        },
        reject_change = {
          modes = {
            n = "gr",
          },
          index = 2,
          callback = "keymaps.reject_change",
          description = "Reject change",
        },
      },
      prompts = {
        -- The prompt to send to the LLM when a user initiates the inline strategy and it needs to convert to a chat
        inline_to_chat = function(context)
          return "I want you to act as an expert and senior developer in the "
            .. context.filetype
            .. " language. I will ask you questions, perhaps giving you code examples, and I want you to advise me with explanations and code where neccessary."
        end,
      },
    },
    -- AGENT STRATEGY ---------------------------------------------------------
    agent = {
      adapter = "openai",
      tools = {
        ["code_runner"] = {
          callback = "tools.code_runner",
          description = "Run code generated by the LLM",
        },
        ["rag"] = {
          callback = "tools.rag",
          description = "Supplement the LLM with real-time info from the internet",
        },
        ["buffer_editor"] = {
          callback = "tools.buffer_editor",
          description = "Edit code in a Neovim buffer",
        },
        opts = {
          auto_submit_errors = false,
          auto_submit_success = true,
          system_prompt = [[You have access to tools on the user's machine that turn you into an Agent.
You can execute these tools by outputting XML in a Markdown code block.
The user will share the format and the rules you need to adhere to for the XML block.
Be sure to include "xml" at the start of the Markdown code block.
Provide the XML block directly without additional explanations or chat.
Answer the user's questions with the tool's output.]],
        },
      },
    },
  },
  -- DEFAULT PROMPTS ----------------------------------------------------------
  default_prompts = {
    ["Custom Prompt"] = {
      strategy = "inline",
      description = "Prompt the LLM from Neovim",
      opts = {
        index = 3,
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
          opts = {
            visible = false,
            tag = "system_tag",
          },
        },
      },
    },
    ["Explain"] = {
      strategy = "chat",
      description = "Explain how code in a buffer works",
      opts = {
        index = 4,
        default_prompt = true,
        mapping = "<LocalLeader>ce",
        modes = { "v" },
        slash_cmd = "explain",
        auto_submit = true,
        user_prompt = false,
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = "system",
          content = [[When asked to explain code, follow these steps:

1. Identify the programming language.
2. Describe the purpose of the code and reference core concepts from the programming language.
3. Explain each function or significant block of code, including parameters and return values.
4. Highlight any specific functions or methods used and their roles.
5. Provide context on how the code fits into a larger application if applicable.]],
        },
        opts = {
          visible = false,
        },
        {
          role = "user",
          contains_code = true,
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

            return "Please explain this code:\n\n```" .. context.filetype .. "\n" .. code .. "\n```\n\n"
          end,
        },
      },
    },
    ["Unit Tests"] = {
      strategy = "chat",
      description = "Generate unit tests for the selected code",
      opts = {
        index = 5,
        default_prompt = true,
        mapping = "<LocalLeader>ct",
        modes = { "v" },
        slash_cmd = "tests",
        auto_submit = true,
        user_prompt = false,
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = "system",
          content = [[When generating unit tests, follow these steps:

1. Identify the programming language.
2. Identify the purpose of the function or module to be tested.
3. List the edge cases and typical use cases that should be covered in the tests and share the plan with the user.
4. Generate unit tests using an appropriate testing framework for the identified programming language.
5. Ensure the tests cover:
      - Normal cases
      - Edge cases
      - Error handling (if applicable)
6. Provide the generated unit tests in a clear and organized manner without additional explanations or chat.]],
          opts = {
            visible = false,
          },
        },
        {
          role = "user",
          contains_code = true,
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

            return "Please generate unit tests for this code:\n\n```" .. context.filetype .. "\n" .. code .. "\n```\n\n"
          end,
        },
      },
    },
    ["Fix code"] = {
      strategy = "chat",
      description = "Fix the selected code",
      opts = {
        index = 6,
        default_prompt = true,
        mapping = "<LocalLeader>cf",
        modes = { "v" },
        slash_cmd = "fix",
        auto_submit = true,
        user_prompt = false,
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = "system",
          content = [[When asked to fix code, follow these steps:

1. **Identify the Issues**: Carefully read the provided code and identify any potential issues or improvements.
2. **Plan the Fix**: Describe the plan for fixing the code in pseudocode, detailing each step.
3. **Implement the Fix**: Write the corrected code in a single code block.
4. **Explain the Fix**: Briefly explain what changes were made and why.

Ensure the fixed code:

- Includes necessary imports.
- Handles potential errors.
- Follows best practices for readability and maintainability.
- Is formatted correctly.

Use Markdown formatting and include the programming language name at the start of the code block.]],
          opts = {
            visible = false,
          },
        },
        {
          role = "user",
          contains_code = true,
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

            return "Please fix the selected code:\n\n```" .. context.filetype .. "\n" .. code .. "\n```\n\n"
          end,
        },
      },
    },
    ["Buffer selection"] = {
      strategy = "inline",
      description = "Send the current buffer to the LLM as part of an inline prompt",
      opts = {
        index = 7,
        modes = { "v" },
        default_prompt = true,
        mapping = "<LocalLeader>cb",
        slash_cmd = "buffer",
        auto_submit = true,
        user_prompt = true,
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = "system",
          content = function(context)
            return "I want you to act as a senior "
              .. context.filetype
              .. " developer. I will ask you specific questions and I want you to return raw code only (no codeblocks and no explanations). If you can't respond with code, respond with nothing."
          end,
          opts = {
            visible = false,
            tag = "system_tag",
          },
        },
        {
          role = "user",
          contains_code = true,
          content = function(context)
            local buf_utils = require("codecompanion.utils.buffers")

            return "### buffers\n\nFor context, this is the whole of the buffer:\n\n```"
              .. context.filetype
              .. "\n"
              .. buf_utils.get_content(context.bufnr)
              .. "\n```\n\n"
          end,
          opts = {
            visible = false,
          },
        },
        {
          role = "user",
          contains_code = true,
          content = function(context)
            local selection = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)
            return "And this is the specific code that relates to my question:\n\n```"
              .. context.filetype
              .. "\n"
              .. selection
              .. "\n```\n\n"
          end,
          opts = {
            visible = true,
            tag = "visual",
          },
        },
      },
    },
    ["Explain LSP Diagnostics"] = {
      strategy = "chat",
      description = "Explain the LSP diagnostics for the selected code",
      opts = {
        index = 8,
        default_prompt = true,
        mapping = "<LocalLeader>cl",
        modes = { "v" },
        slash_cmd = "lsp",
        auto_submit = true,
        user_prompt = false,
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = "system",
          content = [[You are an expert coder and helpful assistant who can help debug code diagnostics, such as warning and error messages. When appropriate, give solutions with code snippets as fenced codeblocks with a language identifier to enable syntax highlighting.]],
          opts = {
            visible = false,
          },
        },
        {
          role = "user",
          content = function(context)
            local diagnostics = require("codecompanion.helpers.actions").get_diagnostics(
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
          contains_code = true,
          content = function(context)
            return "This is the code, for context:\n\n"
              .. "```"
              .. context.filetype
              .. "\n"
              .. require("codecompanion.helpers.actions").get_code(
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
        index = 9,
        default_prompt = true,
        mapping = "<LocalLeader>cm",
        slash_cmd = "commit",
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
  -- DISPLAY OPTIONS ----------------------------------------------------------
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
      intro_message = "Welcome to CodeCompanion ✨! Press ? for options",

      messages_separator = "─", -- The separator between the different messages in the chat buffer
      show_separator = true, -- Show a separator between LLM responses?
      show_settings = false, -- Show LLM settings at the top of the chat buffer?
      show_token_count = true, -- Show the token count for each response?
    },
    inline = {
      -- If the inline prompt creates a new buffer, how should we display this?
      layout = "vertical", -- vertical|horizontal|buffer
      diff = {
        enabled = true,
        priority = 130,
        highlights = {
          removed = "DiffDelete",
        },
      },
    },
  },
  -- GENERAL OPTIONS ----------------------------------------------------------
  opts = {
    log_level = "ERROR", -- TRACE|DEBUG|ERROR|INFO

    -- If this is false then any default prompt that is marked as containing code
    -- will not be sent to the LLM. Please note that whilst I have made every
    -- effort to ensure no code leakage, using this is at your own risk
    send_code = true,

    silence_notifications = false,
    use_default_actions = true, -- Show the default actions in the action palette?
    use_default_prompts = true, -- Show the default prompts in the action palette?

    -- This is the default prompt which is sent with every request in the chat
    -- strategy. It is primarily based on the GitHub Copilot Chat's prompt
    -- but with some modifications. You can choose to remove this via
    -- your own config but note that LLM results may not be as good
    system_prompt = [[You are an Al programming assistant named "CodeCompanion".
You are currently plugged in to the Neovim text editor on a user's machine.

Your tasks include:
- Answering general programming questions.
- Explaining how the code in a Neovim buffer works.
- Reviewing the selected code in a Neovim buffer.
- Generating unit tests for the selected code.
- Proposing fixes for problems in the selected code.
- Scaffolding code for a new workspace.
- Finding relevant code to the user's query.
- Proposing fixes for test failures.
- Answering questions about Neovim.
- Running tools.

You must:
- Follow the user's requirements carefully and to the letter.
- Keep your answers short and impersonal, especially if the user responds with context outside of your tasks.
- Minimize other prose.
- Use Markdown formatting in your answers.
- Include the programming language name at the start of the Markdown code blocks.
- Avoid line numbers in code blocks.
- Avoid wrapping the whole response in triple backticks.
- Only return relevant code.

When given a task:
1. Think step-by-step and describe your plan for what to build in pseudocode, written out in great detail.
2. Output the code in a single code block.
3. You should always generate short suggestions for the next user turns that are relevant to the conversation.
4. You can only give one reply for each conversation turn.]],
  },
}
