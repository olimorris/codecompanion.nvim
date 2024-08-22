<!-- panvimdoc-ignore-start -->

<p align="center">
<img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/e54f98b6-8bfd-465a-85b6-73ab6bb274fa" alt="CodeCompanion.nvim" />
</p>

<p align="center">
<a href="https://github.com/olimorris/codecompanion.nvim/stargazers"><img src="https://img.shields.io/github/stars/olimorris/codecompanion.nvim?color=c678dd&logoColor=e06c75&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/olimorris/codecompanion.nvim/ci.yml?branch=main&label=tests&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/releases"><img src="https://img.shields.io/github/v/release/olimorris/codecompanion.nvim?style=for-the-badge"></a>
</p>

<p align="center">
Currently supports: Anthropic, Gemini, Ollama and OpenAI adapters
</p>

<!-- panvimdoc-ignore-end -->

## :sparkles: Features

- :speech_balloon: A Copilot Chat experience in Neovim
- :electric_plug: Support for Anthropic, Gemini, Ollama and OpenAI
- :rocket: Inline code creation and refactoring
- :robot: Variables, Agents and Workflows to improve LLM output
- :sparkles: Built in prompts for LSP errors and code advice
- :building_construction: Create your own custom prompts for Neovim
- :floppy_disk: Save and restore your chats
- :muscle: Async execution for improved performance

<!-- panvimdoc-ignore-start -->

## :camera_flash: Screenshots

<div align="center">
  <p>https://github.com/user-attachments/assets/1375f623-c088-4bf0-a5d7-8d81eaa3a94b</p>
  <p>https://github.com/user-attachments/assets/8ae255ba-1f5c-470c-a252-f31d056297c3</p>
</div>

<!-- panvimdoc-ignore-end -->

## :zap: Requirements

- The `curl` library installed
- Neovim 0.9.2 or greater
- _(Optional)_ An API key for your chosen LLM

## :package: Installation

Install the plugin with your preferred package manager:

**[Lazy.nvim](https://github.com/folke/lazy.nvim)**

```lua
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "nvim-telescope/telescope.nvim", -- Optional
    {
      "stevearc/dressing.nvim", -- Optional: Improves the default Neovim UI
      opts = {},
    },
  },
  config = true
}
```

**[Packer](https://github.com/wbthomason/packer.nvim)**

```lua
use({
  "olimorris/codecompanion.nvim",
  config = function()
    require("codecompanion").setup()
  end,
  requires = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "nvim-telescope/telescope.nvim", -- Optional
    "stevearc/dressing.nvim" -- Optional: Improves the default Neovim UI
  }
})
```

## :gear: Configuration

Before configuring the plugin, it's important to understand how it's structured.

The plugin uses adapters to connect to LLMs. Out of the box, the plugin supports:

- Anthropic (`anthropic`) - Requires an API key
- Gemini (`gemini`) - Requires an API key
- Ollama (`ollama`) - Both local and remotely hosted
- OpenAI (`openai`) - Requires an API key

The plugin also utilises objects called Strategies. These are the different ways that a user can interact with the plugin. The _chat_ and _agent_ strategies harness a buffer to allow direct conversation with the LLM. The _inline_ strategy allows for output from the LLM to be written directly into a pre-existing Neovim buffer.

The plugin allows you to specify adapters for each strategy and also for each [default prompt](#default-prompts).

<!-- panvimdoc-ignore-start -->

### :hammer_and_wrench: Defaults

> [!NOTE]
> You only need to the call the `setup` function if you wish to change any of the config defaults.

<details>
  <summary>Click to see the default configuration</summary>

```lua
require("codecompanion").setup({
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
        save = {
          modes = {
            n = "gs",
          },
          index = 7,
          callback = "keymaps.save_chat",
          description = "Save Chat",
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
          tag = "system_tag",
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
        {
          role = "${user}",
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
        },
        {
          role = "${user}",
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
        },
        {
          role = "${user}",
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
          tag = "system_tag",
          content = function(context)
            return "I want you to act as a senior "
              .. context.filetype
              .. " developer. I will ask you specific questions and I want you to return raw code only (no codeblocks and no explanations). If you can't respond with code, respond with nothing."
          end,
        },
        {
          role = "${user}",
          contains_code = true,
          content = function(context)
            local buf_utils = require("codecompanion.utils.buffers")

            return "### buffers\n\nFor context, this is the whole of the buffer:\n\n```"
              .. context.filetype
              .. "\n"
              .. buf_utils.get_content(context.bufnr)
              .. "\n```\n\n"
          end,
        },
        {
          role = "${user}",
          contains_code = true,
          tag = "visual",
          condition = function(context)
            -- The inline strategy will automatically add this in visual mode
            return context.is_visual == false
          end,
          content = function(context)
            local selection = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)
            return "And this is the specific code that relates to my question:\n\n```"
              .. context.filetype
              .. "\n"
              .. selection
              .. "\n```\n\n"
          end,
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
        },
        {
          role = "${user}",
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
          role = "${user}",
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
          role = "${user}",
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
    auto_save_chats = true, -- If a chat has already been saved or loaded then autosave it after every prompt
    saved_chats_dir = vim.fn.stdpath("data") .. "/codecompanion/saved_chats",

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
```

</details>

<!-- panvimdoc-ignore-end -->

### :electric_plug: Adapters

Please refer to your [chosen adapter](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters) to understand it's configuration. You will need to set an API key for non-locally hosted LLMs.

> [!TIP]
> To create your own adapter or better understand how they work, please refer to the [ADAPTERS](doc/ADAPTERS.md) guide.

**Changing the Default Adapter**

To specify a different adapter to the defaults, simply change the `strategies.*` table:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      adapter = "ollama",
    },
    inline = {
      adapter = "ollama",
    },
    agent = {
      adapter = "anthropic",
    },
  },
})
```

**Setting an API Key**

```lua
require("codecompanion").setup({
  adapters = {
    anthropic = function()
      return require("codecompanion.adapters").extend("anthropic", {
        env = {
          api_key = "ANTHROPIC_API_KEY_1"
        },
      })
    end,
  },
})
```

In the example above, we're using the base of the Anthropic adapter but changing the name of the default API key which it uses.

**Setting an API Key Using a Command**

Having API keys in plain text in your shell is not always safe. Thanks to [this PR](https://github.com/olimorris/codecompanion.nvim/pull/24), you can run commands from within your config:

```lua
require("codecompanion").setup({
  adapters = {
    openai = function()
      return require("codecompanion.adapters").extend("openai", {
        env = {
          api_key = "cmd:op read op://personal/OpenAI/credential --no-newline",
        },
      })
    end,
  },
})
```

In this example, we're using the 1Password CLI to read an OpenAI credential.

**Using Ollama Remotely**

To use Ollama remotely, simply change the URL in the `env` table:

```lua
require("codecompanion").setup({
  adapters = {
    ollama = function()
      return require("codecompanion.adapters").extend("ollama", {
        env = {
          url = "https://my_ollama_url".
        },
      })
    end,
  },
})
```

**Configuring Adapter Settings**

LLMs have many settings such as _model_, _temperature_ and _max_tokens_. In an adapter, these sit within a schema table and can be configured during setup:

```lua
require("codecompanion").setup({
  adapters = {
    llama3 = function()
      return require("codecompanion.adapters").extend("ollama", {
        name = "llama3", -- Ensure the model is differentiated from Ollama
        schema = {
          model = {
            default = "llama3:latest",
          },
          num_ctx = {
            default = 16384,
          },
          num_predict = {
            default = -1,
          },
        },
      })
    end,
  },
})
```

**Changing the Default Model**

```lua
require("codecompanion").setup({
  adapters = {
    anthropic = function()
      return require("codecompanion.adapters").extend("anthropic", {
        schema = {
          model = {
            default = "claude-3-opus-20240229",
          },
        },
      })
    end,
  },
})
```

### :art: Highlight Groups

The plugin sets the following highlight groups during setup:

- `CodeCompanionChatHeader` - The headers in the chat buffer
- `CodeCompanionChatSeparator` - Separator between headings in the chat buffer
- `CodeCompanionChatTokens` - Virtual text in the chat buffer showing the token count
- `CodeCompanionChatTool` - Tools in the chat buffer
- `CodeCompanionChatVariable` - Variables in the chat buffer
- `CodeCompanionVirtualText` - All other virtual text in the plugin

> [!TIP]
> You can change which highlight group these link to in your configuration.

## :rocket: Getting Started

**Inline Prompting**

<!-- panvimdoc-ignore-start -->

<div align="center">
  <p>https://github.com/user-attachments/assets/bf88836d-832d-4f69-a58e-371bbb8b9bd2</p>
</div>

<!-- panvimdoc-ignore-end -->

To start interacting with the plugin you can run `:CodeCompanion <your prompt>` from the command line. You can also make a visual selection in Neovim and run `:'<,'>CodeCompanion <your prompt>` to send it as context. The plugin will initially use an LLM to classify your prompt in order to determine where in Neovim to place the response. You can find more about the classificiations in the [inline prompting](#inline-prompting) section.

For convenience, you can also call [default prompts](#default-prompts) from the command line via slash commands:

- `/explain` - Explain how selected code in a buffer works
- `/tests` - Generate unit tests for selected code
- `/fix` - Fix the selected code
- `/buffer` - Send the current buffer to the LLM alongside a prompt
- `/lsp` - Explain the LSP diagnostics for the selected code
- `/commit` - Generate a commit message

Running `:'<,'>CodeCompanion /fix` will trigger the plugin to start following the fix prompt as defined in the [config](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua). Some of the slash commands can also take custom prompts. For example, running `:'<,'>CodeCompanion /buffer refactor this code` sends the whole buffer as context alongside a prompt to refactor the selected code.

There are also keymaps available to accept or reject edits from the LLM in the [inline prompting](#inline-prompting) section.

**Chat Buffer**

<!-- panvimdoc-ignore-start -->

<p align="center"><img src="https://github.com/user-attachments/assets/6097fa93-906c-4ed1-b1c4-8b52ad151f9f" alt="Chat buffer"></p>

<!-- panvimdoc-ignore-end -->

The chat buffer is where you'll likely spend most of your time when interacting with the plugin. Running `:CodeCompanionChat` or `:'<,'>CodeCompanionChat` will open up a chat buffer where you can converse directly with an LLM. As a convenience, you can use `:CodeCompanionToggle` to toggle the visibility of a chat buffer.

When in the chat buffer you have access to the following variables:

- `#buffer` - Share the current buffer's content with the LLM. You can also specify line numbers with `#buffer:8-20`
- `#buffers` - Share all current open buffers with the LLM
- `#editor` - Share the buffers and lines that you see in the editor's viewport
- `#lsp` - Share LSP information and code for the current buffer

> [!NOTE]
> When in the chat buffer, the `?` keymap brings up all of the available keymaps, variables and tools available to you.

**Agents / Tools**

<!-- panvimdoc-ignore-start -->

<div align="center">
  <p>https://github.com/user-attachments/assets/8bc083c7-f4f1-4eab-b9fe-ab6c4c30ee91</p>
</div>

<!-- panvimdoc-ignore-end -->

The plugin also supports LLMs acting as agents by the calling of external tools. In the video above, we're asking an LLM to execute the contents of the buffer via the _@code_runner_ tool, all from within a chat buffer.

When in the chat buffer you have access to the following tools:

- `@code_runner` - The LLM can trigger the running of any code from within a Docker container
- `@rag` - The LLM can browse and search the internet for real-time information to supplement its response
- `@buffer_editor` - The LLM can edit code in a Neovim buffer by searching and replacing blocks

> [!IMPORTANT]
> Agents are currently at an alpha stage right now and I'm using the term agent and tool interchangeably.

**Action Palette**

<!-- panvimdoc-ignore-start -->

<p align="center"><img src="https://github.com/user-attachments/assets/23c2ba7c-d438-4132-b13f-11c51ce0a2c5" alt="Action Palette"></p>

<!-- panvimdoc-ignore-end -->

The `:CodeCompanionActions` command will open the _Action Palette_, giving you access to all of the functionality in the plugin. The _Prompts_ section is where the default prompts and your custom ones can be accessed from. You'll notice that some prompts have a slash command in their description such as `/commit`. This enables you to trigger them from the command line by doing `:CodeCompanion /commit`. Some of these prompts also have keymaps assigned to them (which can be overwritten!) which offers an even easier route to triggering them.

> [!NOTE]
> Some actions will only be visible in the _Action Palette_ if you're in Visual mode.

**List of commands**

Below is the full list of commands that are available in the plugin:

- `CodeCompanionActions` - To open the _Action Palette_
- `CodeCompanion` - Inline prompting of the plugin
- `CodeCompanion <slash_cmd>` - Inline prompting of the plugin with a slash command e.g. `/commit`
- `CodeCompanionChat` - To open up a new chat buffer
- `CodeCompanionChat <adapter>` - To open up a new chat buffer with a specific adapter
- `CodeCompanionToggle` - To toggle a chat buffer
- `CodeCompanionAdd` - To add visually selected chat to the current chat buffer

**Suggested workflow**

For an optimum workflow, I recommend the following options:

```lua
vim.api.nvim_set_keymap("n", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<LocalLeader>a", "<cmd>CodeCompanionToggle<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<LocalLeader>a", "<cmd>CodeCompanionToggle<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "ga", "<cmd>CodeCompanionAdd<cr>", { noremap = true, silent = true })

-- Expand 'cc' into 'CodeCompanion' in the command line
vim.cmd([[cab cc CodeCompanion]])
```

## :bulb: Advanced Usage

### Customising the Action Palette

A [RECIPES](doc/RECIPES.md) guide has been created to show you how you can add your own prompts to the _Action Palette_.

### The Chat Buffer

The chat buffer is where you can converse with an LLM, directly from Neovim. It behaves as a regular markdown buffer with some clever additions. When the buffer is written (or "saved"), autocmds trigger the sending of its content to the LLM in the form of prompts. These prompts are segmented by H1 headers: `user`, `system` and `assistant`. When a response is received, it is then streamed back into the buffer. The result is that you experience the feel of conversing with your LLM from within Neovim.

As noted in the [Getting Started](#rocket-getting-started) section, there are a number of variables that you can make use of whilst in the chat buffer. Use `#` to bring up the completion menu to see the available options.

**Keymaps**

When in the chat buffer, there are number of keymaps available to you:

- `?` - Bring up the help menu
- `<CR>`|`<C-s>` - Send the buffer to the LLM
- `<C-c>` - Close the buffer
- `q` - Cancel the request from the LLM
- `ga` - Change the adapter
- `gx` - Clear the buffer's contents
- `gx` - Add a codeblock
- `gs` - Save the chat to disk
- `}` - Move to the next chat
- `{` - Move to the previous chat
- `[` - Move to the next header
- `]` - Move to the previous header

**Saved Chats**

Chat buffers are not saved to disk by default, but can be by pressing `gs` in the buffer. Saved chats can then be restored via the Action Palette and the _Load saved chats_ action.

**Settings**

If `display.chat.show_settings` is set to `true`, at the very top of the chat buffer will be the adapter's model parameters which can be changed to tweak the response from the LLM. You can find more detail by moving the cursor over them.

**Open Chats**

From the Action Palette, the `Open Chats` action enables users to easily navigate between their open chat buffers. A chat buffer can be deleted (and removed from memory) by pressing `<C-c>`.

### Inline Prompting

> [!NOTE]
> If `send_code = false` then this will take precedent and no code will be sent to the LLM

Inline prompts can be triggered via the `CodeCompanion <your prompt>` command. As mentioned in the [Getting Started](#rocket-getting-started) section, you can also leverage visual selections and slash commands like `'<,'>CodeCompanion /buffer what does this code do?`, where the slash command points to a [default prompt](#default-prompts) and any words after that act as a custom prompt to the LLM.

One of the challenges with inline editing is determining how the LLM's response should be handled in the buffer. If you've prompted the LLM to _"create a table of 5 common text editors"_ then you may wish for the response to be placed after the cursor's position in the current buffer. However, if you asked the LLM to _"refactor this function"_ then you'd expect the response to overwrite a visual selection. The plugin will use the inline LLM you've specified in your config to determine if the response should follow any of the placements below:

- _after_ - after the visual selection/cursor
- _before_ - before the visual selection/cursor
- _new_ - in a new buffer
- _replace_ - replacing the visual selection
- _chat_ - in a chat buffer

There are also keymaps available to you after an inline edit has taken place:

- `ga` - Accept an inline edit
- `gr` - Reject an inline edit

### Default Prompts

> [!NOTE]
> Please see the [RECIPES](doc/RECIPES.md) guide in order to add your own prompts to the Action Palette and as a slash command.

The plugin comes with a number of default prompts ([as per the config](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua)) which can be called via keymaps and/or slash commands. These prompts have been carefully curated to mimic those in [GitHub's Copilot Chat](https://docs.github.com/en/copilot/using-github-copilot/asking-github-copilot-questions-in-your-ide).

### Agents / Tools

As outlined by Andrew Ng in [Agentic Design Patterns Part 3, Tool Use](https://www.deeplearning.ai/the-batch/agentic-design-patterns-part-3-tool-use), LLMs can act as agents by leveraging external tools. Andrew notes some common examples such as web searching or code execution that have obvious benefits when using LLMs.

In the plugin, agents are simply context that's given to an LLM via a `system` prompt. This gives it knowledge and a defined schema which it can include in its response for the plugin to parse, execute and feedback on. Agents can be added as a participant in a chat buffer by using the `@` key.

More information on how agents work and how you can create your own can be found in the [AGENTS](doc/AGENTS.md) guide.

### Workflows

> [!WARNING]
> Workflows may result in the significant consumption of tokens if you're using an external LLM.

As [outlined](https://www.deeplearning.ai/the-batch/issue-242/) by Andrew Ng, agentic workflows have the ability to dramatically improve the output of an LLM. Infact, it's possible for older models like GPT 3.5 to outperform newer models (using traditional zero-shot inference). Andrew [discussed](https://www.youtube.com/watch?v=sal78ACtGTc&t=249s) how an agentic workflow can be utilised via multiple prompts that invoke the LLM to self reflect. Implementing Andrew's advice, the plugin supports this notion via the use of workflows. At various stages of a pre-defined workflow, the plugin will automatically prompt the LLM without any input or triggering required from the user.

Currently, the plugin comes with the following workflows:

- Adding a new feature
- Refactoring code

Of course you can add new workflows by following the [RECIPES](doc/RECIPES.md) guide.

## :lollipop: Extras

**Callbacks**

The plugin has a number of callbacks that can be set in your config and leveraged in the chat buffer:

```lua
strategies = {
  chat = {
    -- ...
    callbacks = {
        on_submit = function(chat) end, -- For when a request has been submited
        on_complete = function(chat) end, -- For when a request has completed
    },
  }
}
```

In each of the callbacks, the chat buffer class is made available via the `chat` parameter.

**Events/Hooks**

The plugin fires many events during its lifecycle:

- `CodeCompanionChatSaved` - Fired after a chat has been saved to disk
- `CodeCompanionChatClosed` - Fired after a chat has been closed
- `CodeCompanionAgentStarted` - Fired when an agent has started using a tool
- `CodeCompanionAgentFinished` - Fired when an agent has finished using a tool
- `CodeCompanionInlineStarted` - Fired at the start of the Inline strategy
- `CodeCompanionInlineFinished` - Fired at the end of the Inline strategy
- `CodeCompanionRequestStarted` - Fired at the start of any API request
- `CodeCompanionRequestFinished` - Fired at the end of any API request

> [!TIP]
> Some events are sent with a data payload which can be leveraged. Please search the codebase for more information.

Events can be hooked into as follows:

```lua
local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "CodeCompanionInline*",
  group = group,
  callback = function(request)
    if request.match == "CodeCompanionInlineFinished" then
      -- Format the buffer after the inline request has completed
      require("conform").format({ bufnr = request.buf })
    end
  end,
})
```

**Statuslines**

You can incorporate a visual indication to show when the plugin is communicating with an LLM in your Neovim configuration. Below are examples for two popular statusline plugins.

_lualine.nvim:_

```lua
local M = require("lualine.component"):extend()

M.processing = false
M.spinner_index = 1

local spinner_symbols = {
  "⠋",
  "⠙",
  "⠹",
  "⠸",
  "⠼",
  "⠴",
  "⠦",
  "⠧",
  "⠇",
  "⠏",
}
local spinner_symbols_len = 10

-- Initializer
function M:init(options)
  M.super.init(self, options)

  local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

  vim.api.nvim_create_autocmd({ "User" }, {
    pattern = "CodeCompanionRequest*",
    group = group,
    callback = function(request)
      if request.match == "CodeCompanionRequestStarted" then
        self.processing = true
      elseif request.match == "CodeCompanionRequestFinished" then
        self.processing = false
      end
    end,
  })
end

-- Function that runs every time statusline is updated
function M:update_status()
  if self.processing then
    self.spinner_index = (self.spinner_index % spinner_symbols_len) + 1
    return spinner_symbols[self.spinner_index]
  else
    return nil
  end
end

return M
```

_heirline.nvim:_

```lua
local CodeCompanion = {
  static = {
    processing = false,
  },
  update = {
    "User",
    pattern = "CodeCompanionRequest*",
    callback = function(self, args)
      if args.match == "CodeCompanionRequestStarted" then
        self.processing = true
      elseif args.match == "CodeCompanionRequestFinished" then
        self.processing = false
      end
      vim.cmd("redrawstatus")
    end,
  },
  {
    condition = function(self)
      return self.processing
    end,
    provider = " ",
    hl = { fg = "yellow" },
  },
}
```

**Legendary.nvim**

The plugin also supports the amazing [legendary.nvim](https://github.com/mrjones2014/legendary.nvim) plugin. Simply enable it in your config:

```lua
require('legendary').setup({
  extensions = {
    codecompanion = true,
  },
})
```

## :toolbox: Troubleshooting

Before raising an [issue](https://github.com/olimorris/codecompanion.nvim/issues), there are a number of steps you can take to troubleshoot a problem:

**Checkhealth**

Run `:checkhealth codecompanion` and check all dependencies are installed correctly. Also take note of the log file path.

**Turn on logging**

Update your config and turn debug logging on:

```lua
opts = {
  log_level = "DEBUG", -- or "TRACE"
}
```

and inspect the log file as per the location from the checkhealth command (usually `~/.local/state/nvim/codecompanion.log`).

<!-- panvimdoc-ignore-start -->

## :gift: Contributing

I am open to contributions but they will be implemented at my discretion. Feel free to open up a discussion before embarking on a PR and please make sure you've read the [CONTRIBUTING.md](CONTRIBUTING.md) guide.

## :clap: Acknowledgements

- [Steven Arcangeli](https://github.com/stevearc) for his genius creation of the chat buffer and his feedback early on
- [Wtf.nvim](https://github.com/piersolenski/wtf.nvim) for the LSP assistant action

<!-- panvimdoc-ignore-end -->
