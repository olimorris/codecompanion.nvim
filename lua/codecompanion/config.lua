local fmt = string.format

local constants = {
  LLM_ROLE = "llm",
  USER_ROLE = "user",
  SYSTEM_ROLE = "system",
}

local defaults = {
  adapters = {
    -- LLMs -------------------------------------------------------------------
    anthropic = "anthropic",
    azure_openai = "azure_openai",
    copilot = "copilot",
    deepseek = "deepseek",
    gemini = "gemini",
    githubmodels = "githubmodels",
    huggingface = "huggingface",
    ollama = "ollama",
    openai = "openai",
    xai = "xai",
    -- NON-LLMs ---------------------------------------------------------------
    non_llms = {
      jina = "jina",
    },
    -- OPTIONS ----------------------------------------------------------------
    opts = {
      allow_insecure = false, -- Allow insecure connections?
      show_defaults = true, -- Show default adapters
      proxy = nil, -- [protocol://]host[:port] e.g. socks5://127.0.0.1:9999
    },
  },
  constants = constants,
  strategies = {
    -- CHAT STRATEGY ----------------------------------------------------------
    chat = {
      adapter = "copilot",
      roles = {
        ---The header name for the LLM's messages
        ---@type string|fun(adapter: CodeCompanion.Adapter): string
        llm = function(adapter)
          return "CodeCompanion (" .. adapter.formatted_name .. ")"
        end,

        ---The header name for your messages
        ---@type string
        user = "Me",
      },
      agents = {
        ["full_stack_dev"] = {
          description = "Full Stack Developer - Can run code, edit code and modify files",
          system_prompt = "**DO NOT** make any assumptions about the dependencies that a user has installed. If you need to install any dependencies to fulfil the user's request, do so via the Command Runner tool. If the user doesn't specify a path, use their current working directory.",
          tools = {
            "cmd_runner",
            "editor",
            "files",
          },
        },
        tools = {
          ["cmd_runner"] = {
            callback = "strategies.chat.agents.tools.cmd_runner",
            description = "Run shell commands initiated by the LLM",
            opts = {
              requires_approval = true,
            },
          },
          ["editor"] = {
            callback = "strategies.chat.agents.tools.editor",
            description = "Update a buffer with the LLM's response",
          },
          ["files"] = {
            callback = "strategies.chat.agents.tools.files",
            description = "Update the file system with the LLM's response",
            opts = {
              requires_approval = true,
            },
          },
          opts = {
            auto_submit_errors = false, -- Send any errors to the LLM automatically?
            auto_submit_success = false, -- Send any successful output to the LLM automatically?
            system_prompt = [[## Tools Access and Execution Guidelines

### Overview
You now have access to specialized tools that empower you to assist users with specific tasks. These tools are available only when explicitly requested by the user.

### General Rules
- **User-Triggered:** Only use a tool when the user explicitly indicates that a specific tool should be employed (e.g., phrases like "run command" for the cmd_runner).
- **Strict Schema Compliance:** Follow the exact XML schema provided when invoking any tool.
- **XML Format:** Always wrap your responses in a markdown code block designated as XML and within the `<tools></tools>` tags.
- **Valid XML Required:** Ensure that the constructed XML is valid and well-formed.
- **Multiple Commands:**
  - If issuing commands of the same type, combine them within one `<tools></tools>` XML block with separate `<action></action>` entries.
  - If issuing commands for different tools, ensure they're wrapped in `<tool></tool>` tags within the `<tools></tools>` block.
- **No Side Effects:** Tool invocations should not alter your core tasks or the general conversation structure.]],
          },
        },
      },
      variables = {
        ["buffer"] = {
          callback = "strategies.chat.variables.buffer",
          description = "Share the current buffer with the LLM",
          opts = {
            contains_code = true,
            has_params = true,
          },
        },
        ["lsp"] = {
          callback = "strategies.chat.variables.lsp",
          description = "Share LSP information and code for the current buffer",
          opts = {
            contains_code = true,
          },
        },
        ["viewport"] = {
          callback = "strategies.chat.variables.viewport",
          description = "Share the code that you see in Neovim with the LLM",
          opts = {
            contains_code = true,
          },
        },
      },
      slash_commands = {
        ["buffer"] = {
          callback = "strategies.chat.slash_commands.buffer",
          description = "Insert open buffers",
          opts = {
            contains_code = true,
            provider = "default", -- default|telescope|mini_pick|fzf_lua
          },
        },
        ["fetch"] = {
          callback = "strategies.chat.slash_commands.fetch",
          description = "Insert URL contents",
          opts = {
            adapter = "jina",
          },
        },
        ["file"] = {
          callback = "strategies.chat.slash_commands.file",
          description = "Insert a file",
          opts = {
            contains_code = true,
            max_lines = 1000,
            provider = "default", -- default|telescope|mini_pick|fzf_lua
          },
        },
        ["help"] = {
          callback = "strategies.chat.slash_commands.help",
          description = "Insert content from help tags",
          opts = {
            contains_code = false,
            max_lines = 128, -- Maximum amount of lines to of the help file to send (NOTE: Each vimdoc line is typically 10 tokens)
            provider = "telescope", -- telescope|mini_pick|fzf_lua
          },
        },
        ["now"] = {
          callback = "strategies.chat.slash_commands.now",
          description = "Insert the current date and time",
          opts = {
            contains_code = false,
          },
        },
        ["symbols"] = {
          callback = "strategies.chat.slash_commands.symbols",
          description = "Insert symbols for a selected file",
          opts = {
            contains_code = true,
            provider = "default", -- default|telescope|mini_pick|fzf_lua
          },
        },
        ["terminal"] = {
          callback = "strategies.chat.slash_commands.terminal",
          description = "Insert terminal output",
          opts = {
            contains_code = false,
          },
        },
        ["workspace"] = {
          callback = "strategies.chat.slash_commands.workspace",
          description = "Load a workspace file",
          opts = {
            contains_code = true,
          },
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
        completion = {
          modes = {
            i = "<C-_>",
          },
          index = 1,
          callback = "keymaps.completion",
          description = "Completion Menu",
        },
        send = {
          modes = {
            n = { "<CR>", "<C-s>" },
            i = "<C-s>",
          },
          index = 2,
          callback = "keymaps.send",
          description = "Send",
        },
        regenerate = {
          modes = {
            n = "gr",
          },
          index = 3,
          callback = "keymaps.regenerate",
          description = "Regenerate the last response",
        },
        close = {
          modes = {
            n = "<C-c>",
            i = "<C-c>",
          },
          index = 4,
          callback = "keymaps.close",
          description = "Close Chat",
        },
        stop = {
          modes = {
            n = "q",
          },
          index = 5,
          callback = "keymaps.stop",
          description = "Stop Request",
        },
        clear = {
          modes = {
            n = "gx",
          },
          index = 6,
          callback = "keymaps.clear",
          description = "Clear Chat",
        },
        codeblock = {
          modes = {
            n = "gc",
          },
          index = 7,
          callback = "keymaps.codeblock",
          description = "Insert Codeblock",
        },
        yank_code = {
          modes = {
            n = "gy",
          },
          index = 8,
          callback = "keymaps.yank_code",
          description = "Yank Code",
        },
        pin = {
          modes = {
            n = "gp",
          },
          index = 9,
          callback = "keymaps.pin_reference",
          description = "Pin Reference",
        },
        watch = {
          modes = {
            n = "gw",
          },
          index = 10,
          callback = "keymaps.toggle_watch",
          description = "Watch Buffer",
        },
        next_chat = {
          modes = {
            n = "}",
          },
          index = 11,
          callback = "keymaps.next_chat",
          description = "Next Chat",
        },
        previous_chat = {
          modes = {
            n = "{",
          },
          index = 12,
          callback = "keymaps.previous_chat",
          description = "Previous Chat",
        },
        next_header = {
          modes = {
            n = "]]",
          },
          index = 13,
          callback = "keymaps.next_header",
          description = "Next Header",
        },
        previous_header = {
          modes = {
            n = "[[",
          },
          index = 14,
          callback = "keymaps.previous_header",
          description = "Previous Header",
        },
        change_adapter = {
          modes = {
            n = "ga",
          },
          index = 15,
          callback = "keymaps.change_adapter",
          description = "Change adapter",
        },
        fold_code = {
          modes = {
            n = "gf",
          },
          index = 15,
          callback = "keymaps.fold_code",
          description = "Fold code",
        },
        debug = {
          modes = {
            n = "gd",
          },
          index = 16,
          callback = "keymaps.debug",
          description = "View debug info",
        },
        system_prompt = {
          modes = {
            n = "gs",
          },
          index = 17,
          callback = "keymaps.toggle_system_prompt",
          description = "Toggle the system prompt",
        },
        auto_tool_mode = {
          modes = {
            n = "gta",
          },
          index = 18,
          callback = "keymaps.auto_tool_mode",
          description = "Toggle automatic tool mode",
        },
      },
      opts = {
        register = "+", -- The register to use for yanking code
        yank_jump_delay_ms = 400, -- Delay in milliseconds before jumping back from the yanked code
      },
    },
    -- INLINE STRATEGY --------------------------------------------------------
    inline = {
      adapter = "copilot",
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
      variables = {
        ["buffer"] = {
          callback = "strategies.inline.variables.buffer",
          description = "Share the current buffer with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["chat"] = {
          callback = "strategies.inline.variables.chat",
          description = "Share the currently open chat buffer with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["clipboard"] = {
          callback = "strategies.inline.variables.clipboard",
          description = "Share the contents of the clipboard with the LLM",
          opts = {
            contains_code = true,
          },
        },
      },
    },
    -- CMD STRATEGY -----------------------------------------------------------
    cmd = {
      adapter = "copilot",
      opts = {
        system_prompt = [[You are currently plugged in to the Neovim text editor on a user's machine. Your core task is to generate an command-line inputs that the user can run within Neovim. Below are some rules to adhere to:

- Return plain text only
- Do not wrap your response in a markdown block or backticks
- Do not use any line breaks or newlines in you response
- Do not provide any explanations
- Generate an command that is valid and can be run in Neovim
- Ensure the command is relevant to the user's request]],
      },
    },
  },
  -- PROMPT LIBRARIES ---------------------------------------------------------
  prompt_library = {
    ["Custom Prompt"] = {
      strategy = "inline",
      description = "Prompt the LLM from Neovim",
      opts = {
        index = 3,
        is_default = true,
        is_slash_cmd = false,
        user_prompt = true,
      },
      prompts = {
        {
          role = constants.SYSTEM_ROLE,
          content = function(context)
            return fmt(
              [[I want you to act as a senior %s developer. I will ask you specific questions and I want you to return raw code only (no codeblocks and no explanations). If you can't respond with code, respond with nothing]],
              context.filetype
            )
          end,
          opts = {
            visible = false,
            tag = "system_tag",
          },
        },
      },
    },
    ["Code workflow"] = {
      strategy = "workflow",
      description = "Use a workflow to guide an LLM in writing code",
      opts = {
        index = 4,
        is_default = true,
        short_name = "cw",
      },
      prompts = {
        {
          -- We can group prompts together to make a workflow
          -- This is the first prompt in the workflow
          {
            role = constants.SYSTEM_ROLE,
            content = function(context)
              return fmt(
                "You carefully provide accurate, factual, thoughtful, nuanced answers, and are brilliant at reasoning. If you think there might not be a correct answer, you say so. Always spend a few sentences explaining background context, assumptions, and step-by-step thinking BEFORE you try to answer a question. Don't be verbose in your answers, but do provide details and examples where it might help the explanation. You are an expert software engineer for the %s language",
                context.filetype
              )
            end,
            opts = {
              visible = false,
            },
          },
          {
            role = constants.USER_ROLE,
            content = "I want you to ",
            opts = {
              auto_submit = false,
            },
          },
        },
        -- This is the second group of prompts
        {
          {
            role = constants.USER_ROLE,
            content = "Great. Now let's consider your code. I'd like you to check it carefully for correctness, style, and efficiency, and give constructive criticism for how to improve it.",
            opts = {
              auto_submit = true,
            },
          },
        },
        -- This is the final group of prompts
        {
          {
            role = constants.USER_ROLE,
            content = "Thanks. Now let's revise the code based on the feedback, without additional explanations.",
            opts = {
              auto_submit = true,
            },
          },
        },
      },
    },
    ["Edit<->Test workflow"] = {
      strategy = "workflow",
      description = "Use a workflow to repeatedly edit then test code",
      opts = {
        index = 4,
        is_default = true,
        short_name = "et",
      },
      prompts = {
        {
          {
            name = "Setup Test",
            role = constants.USER_ROLE,
            opts = { auto_submit = false },
            content = function()
              -- Enable turbo mode!!!
              vim.g.codecompanion_auto_tool_mode = true

              return [[### Instructions

Your instructions here

### Steps to Follow

You are required to write code following the instructions provided above and test the correctness by running the designated test suite. Follow these steps exactly:

1. Update the code in #buffer{watch} using the @editor tool
2. Then use the @cmd_runner tool to run the test suite with `<test_cmd>` (do this after you have updated the code)
3. Make sure you trigger both tools in the same response

We'll repeat this cycle until the tests pass. Ensure no deviations from these steps.]]
            end,
          },
        },
        {
          {
            name = "Repeat On Failure",
            role = constants.USER_ROLE,
            opts = { auto_submit = true },
            -- Scope this prompt to the cmd_runner tool
            condition = function()
              return _G.codecompanion_current_tool == "cmd_runner"
            end,
            -- Repeat until the tests pass, as indicated by the testing flag
            -- which the cmd_runner tool sets on the chat buffer
            repeat_until = function(chat)
              return chat.tool_flags.testing == true
            end,
            content = "The tests have failed. Can you edit the buffer and run the test suite again?",
          },
        },
      },
    },
    ["Explain"] = {
      strategy = "chat",
      description = "Explain how code in a buffer works",
      opts = {
        index = 5,
        is_default = true,
        is_slash_cmd = false,
        modes = { "v" },
        short_name = "explain",
        auto_submit = true,
        user_prompt = false,
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = constants.SYSTEM_ROLE,
          content = [[When asked to explain code, follow these steps:

1. Identify the programming language.
2. Describe the purpose of the code and reference core concepts from the programming language.
3. Explain each function or significant block of code, including parameters and return values.
4. Highlight any specific functions or methods used and their roles.
5. Provide context on how the code fits into a larger application if applicable.]],
          opts = {
            visible = false,
          },
        },
        {
          role = constants.USER_ROLE,
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

            return fmt(
              [[Please explain this code from buffer %d:

```%s
%s
```
]],
              context.bufnr,
              context.filetype,
              code
            )
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
    ["Unit Tests"] = {
      strategy = "inline",
      description = "Generate unit tests for the selected code",
      opts = {
        index = 6,
        is_default = true,
        is_slash_cmd = false,
        modes = { "v" },
        short_name = "tests",
        auto_submit = true,
        user_prompt = false,
        placement = "new",
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = constants.SYSTEM_ROLE,
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
          role = constants.USER_ROLE,
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

            return fmt(
              [[<user_prompt>
Please generate unit tests for this code from buffer %d:

```%s
%s
```
</user_prompt>
]],
              context.bufnr,
              context.filetype,
              code
            )
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
    ["Fix code"] = {
      strategy = "chat",
      description = "Fix the selected code",
      opts = {
        index = 7,
        is_default = true,
        is_slash_cmd = false,
        modes = { "v" },
        short_name = "fix",
        auto_submit = true,
        user_prompt = false,
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = constants.SYSTEM_ROLE,
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
          role = constants.USER_ROLE,
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

            return fmt(
              [[Please fix this code from buffer %d:

```%s
%s
```
]],
              context.bufnr,
              context.filetype,
              code
            )
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
    ["Explain LSP Diagnostics"] = {
      strategy = "chat",
      description = "Explain the LSP diagnostics for the selected code",
      opts = {
        index = 9,
        is_default = true,
        is_slash_cmd = false,
        modes = { "v" },
        short_name = "lsp",
        auto_submit = true,
        user_prompt = false,
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = constants.SYSTEM_ROLE,
          content = [[You are an expert coder and helpful assistant who can help debug code diagnostics, such as warning and error messages. When appropriate, give solutions with code snippets as fenced codeblocks with a language identifier to enable syntax highlighting.]],
          opts = {
            visible = false,
          },
        },
        {
          role = constants.USER_ROLE,
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
                .. "\n  - Buffer: "
                .. context.bufnr
                .. "\n  - Severity: "
                .. diagnostic.severity
                .. "\n  - Message: "
                .. diagnostic.message
                .. "\n"
            end

            return fmt(
              [[The programming language is %s. This is a list of the diagnostic messages:

%s
]],
              context.filetype,
              concatenated_diagnostics
            )
          end,
        },
        {
          role = constants.USER_ROLE,
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(
              context.start_line,
              context.end_line,
              { show_line_numbers = true }
            )
            return fmt(
              [[
This is the code, for context:

```%s
%s
```
]],
              context.filetype,
              code
            )
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
    ["Generate a Commit Message"] = {
      strategy = "chat",
      description = "Generate a commit message",
      opts = {
        index = 10,
        is_default = true,
        is_slash_cmd = true,
        short_name = "commit",
        auto_submit = true,
      },
      prompts = {
        {
          role = constants.USER_ROLE,
          content = function()
            return fmt(
              [[You are an expert at following the Conventional Commit specification. Given the git diff listed below, please generate a commit message for me:

```diff
%s
```
]],
              vim.fn.system("git diff --no-ext-diff --staged")
            )
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
  },
  -- DISPLAY OPTIONS ----------------------------------------------------------
  display = {
    action_palette = {
      width = 95,
      height = 10,
      prompt = "Prompt ", -- Prompt used for interactive LLM calls
      provider = "default", -- default|telescope|mini_pick
      opts = {
        show_default_actions = true, -- Show the default actions in the action palette?
        show_default_prompt_library = true, -- Show the default prompt library in the action palette?
      },
    },
    chat = {
      icons = {
        pinned_buffer = " ",
        watched_buffer = "👀 ",
      },
      debug_window = {
        ---@return number|fun(): number
        width = vim.o.columns - 5,
        ---@return number|fun(): number
        height = vim.o.lines - 2,
      },
      window = {
        layout = "vertical", -- float|vertical|horizontal|buffer
        position = nil, -- left|right|top|bottom (nil will default depending on vim.opt.splitright|vim.opt.splitbelow)
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
          numberwidth = 1,
          signcolumn = "no",
          spell = false,
          wrap = true,
        },
      },
      intro_message = "Welcome to CodeCompanion ✨! Press ? for options",

      show_header_separator = false, -- Show header separators in the chat buffer? Set this to false if you're using an external markdown formatting plugin
      separator = "─", -- The separator between the different messages in the chat buffer

      show_references = true, -- Show references (from slash commands and variables) in the chat buffer?
      show_settings = false, -- Show LLM settings at the top of the chat buffer?
      show_token_count = true, -- Show the token count for each response?
      start_in_insert_mode = false, -- Open the chat buffer in insert mode?

      ---@param tokens number
      ---@param adapter CodeCompanion.Adapter
      token_count = function(tokens, adapter) -- The function to display the token count
        return " (" .. tokens .. " tokens)"
      end,
    },
    diff = {
      enabled = true,
      close_chat_at = 240, -- Close an open chat buffer if the total columns of your display are less than...
      layout = "vertical", -- vertical|horizontal split for default provider
      opts = { "internal", "filler", "closeoff", "algorithm:patience", "followwrap", "linematch:120" },
      provider = "default", -- default|mini_diff
    },
    inline = {
      -- If the inline prompt creates a new buffer, how should we display this?
      layout = "vertical", -- vertical|horizontal|buffer
    },
  },
  -- GENERAL OPTIONS ----------------------------------------------------------
  opts = {
    log_level = "ERROR", -- TRACE|DEBUG|ERROR|INFO
    language = "English", -- The language used for LLM responses

    -- If this is false then any default prompt that is marked as containing code
    -- will not be sent to the LLM. Please note that whilst I have made every
    -- effort to ensure no code leakage, using this is at your own risk
    ---@type boolean|function
    ---@return boolean
    send_code = true,

    job_start_delay = 1500, -- Delay in milliseconds between cmd tools
    submit_delay = 2000, -- Delay in milliseconds before auto-submitting the chat buffer

    ---This is the default prompt which is sent with every request in the chat
    ---strategy. It is primarily based on the GitHub Copilot Chat's prompt
    ---but with some modifications. You can choose to remove this via
    ---your own config but note that LLM results may not be as good
    ---@param opts table
    ---@return string
    system_prompt = function(opts)
      local language = opts.language or "English"
      return string.format(
        [[You are an AI programming assistant named "CodeCompanion". You are currently plugged into the Neovim text editor on a user's machine.

Your core tasks include:
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
- Keep your answers short and impersonal, especially if the user's context is outside your core tasks.
- Minimize additional prose unless clarification is needed.
- Use Markdown formatting in your answers.
- Include the programming language name at the start of each Markdown code block.
- Avoid including line numbers in code blocks.
- Avoid wrapping the whole response in triple backticks.
- Only return code that's directly relevant to the task at hand. You may omit code that isn’t necessary for the solution.
- Use actual line breaks in your responses; only use "\n" when you want a literal backslash followed by 'n'.
- All non-code text responses must be written in the %s language indicated.

When given a task:
1. Think step-by-step and, unless the user requests otherwise or the task is very simple, describe your plan in detailed pseudocode.
2. Output the final code in a single code block, ensuring that only relevant code is included.
3. End your response with a short suggestion for the next user turn that directly supports continuing the conversation.
4. Provide exactly one complete reply per conversation turn.]],
        language
      )
    end,
  },
}

local M = {
  config = vim.deepcopy(defaults),
}

---@param args? table
M.setup = function(args)
  args = args or {}
  if args.constants then
    vim.notify("codecompanion.nvim: Your config table cannot have field 'constants', vim.log.levels.ERROR")
    return
  end
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), args)
end

M.can_send_code = function()
  if type(M.config.opts.send_code) == "boolean" then
    return M.config.opts.send_code
  elseif type(M.config.opts.send_code) == "function" then
    return M.config.opts.send_code()
  end
  return false
end

return setmetatable(M, {
  __index = function(_, key)
    if key == "setup" then
      return M.setup
    end
    return rawget(M.config, key)
  end,
})
