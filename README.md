<!-- panvimdoc-ignore-start -->

<p align="center">
<img src="https://github.com/user-attachments/assets/e31dc9dc-4ec8-4459-8c7b-db673c556f84" alt="CodeCompanion.nvim" />
</p>

<p align="center">
<a href="https://github.com/olimorris/codecompanion.nvim/stargazers"><img src="https://img.shields.io/github/stars/olimorris/codecompanion.nvim?color=c678dd&logoColor=e06c75&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/olimorris/codecompanion.nvim/ci.yml?branch=main&label=tests&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/releases"><img src="https://img.shields.io/github/v/release/olimorris/codecompanion.nvim?style=for-the-badge"></a>
</p>

<p align="center">
Currently supports: Anthropic, Copilot, Gemini, Ollama and OpenAI adapters<br><br>
New features are always announced <a href="https://github.com/olimorris/codecompanion.nvim/discussions/categories/announcements">here</a>
</p>

## :purple_heart: Sponsors

Thank you to the following people:

<p align="center">
<!-- coffee --><a href="https://github.com/bassamsdata"><img src="https://github.com/bassamsdata.png" width="60px" alt="Bassam Data" /></a><a href="https://github.com/ivo-toby"><img src="https://github.com/ivo-toby.png" width="60px" alt="Ivo Toby" /></a><a href="https://github.com/KTSCode"><img src="https://github.com/KTSCode.png" width="60px" alt="KTS Code" /></a><!-- coffee --><!-- sponsors --><a href="https://github.com/mtmr0x"><img src="https:&#x2F;&#x2F;avatars.githubusercontent.com&#x2F;u&#x2F;5414299?u&#x3D;b60f401c665a5aecd45bf4a5c79f7fced0e85b6d&amp;v&#x3D;4" width="60px" alt="Matheus Marsiglio" /></a><a href="https://github.com/unicell"><img src="https:&#x2F;&#x2F;avatars.githubusercontent.com&#x2F;u&#x2F;35352?u&#x3D;1de708f9084ea3ea710294a38694414af4c6ed53&amp;v&#x3D;4" width="60px" alt="Qiu Yu" /></a><a href="https://github.com/zhming0"><img src="https:&#x2F;&#x2F;avatars.githubusercontent.com&#x2F;u&#x2F;1054703?u&#x3D;b173a2c1afc61fa25d9343704659630406e3dea7&amp;v&#x3D;4" width="60px" alt="Zhiming Guo" /></a><!-- sponsors -->
</p>

<!-- panvimdoc-ignore-end -->

## :sparkles: Features

- :speech_balloon: [Copilot Chat](https://github.com/features/copilot) meets [Zed AI](https://zed.dev/blog/zed-ai), in Neovim
- :electric_plug: Support for Anthropic, Copilot, Gemini, Ollama and OpenAI LLMs
- :rocket: Inline transformations, code creation and refactoring
- :robot: Variables, slash commands, agents and workflows to improve LLM output
- :sparkles: Built in prompts for common tasks like advice on LSP errors and code explanations
- :building_construction: Ability to create your own custom prompts, variables and slash commands
- :muscle: Async execution for fast performance

<!-- panvimdoc-ignore-start -->

## :camera_flash: Screenshots

<div align="center">
  <p>https://github.com/user-attachments/assets/17462e02-07c7-44fc-b208-9b68ccbadcf2</p>
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
    "hrsh7th/nvim-cmp", -- Optional: For using slash commands and variables in the chat buffer
    "nvim-telescope/telescope.nvim", -- Optional: For working with files with slash commands
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
    "hrsh7th/nvim-cmp", -- Optional: For using slash commands and variables in the chat buffer
    "nvim-telescope/telescope.nvim", -- Optional: For working with files with slash commands
    "stevearc/dressing.nvim" -- Optional: Improves the default Neovim UI
  }
})
```

**[vim-plug](https://github.com/junegunn/vim-plug)**

```vim
call plug#begin()

Plug "nvim-lua/plenary.nvim"
Plug "nvim-treesitter/nvim-treesitter"
Plug "hrsh7th/nvim-cmp", " Optional: For using slash commands and variables in the chat buffer
Plug "nvim-telescope/telescope.nvim", " Optional: For working with files with slash commands
Plug "stevearc/dressing.nvim" " Optional: Improves the default Neovim UI
Plug "olimorris/codecompanion.nvim"

call plug#end()

lua << EOF
  require("codecompanion").setup()
EOF
```

## :rocket: Quickstart

> [!NOTE]
> Okay, okay...it's not quite a quickstart as you'll need to configure an [adapter](#gear-configuration) first.

**Chat Buffer**

<!-- panvimdoc-ignore-start -->

<p align="center">
  <img src="https://github.com/user-attachments/assets/53f1b204-bda3-4286-81c4-ba7f353fc1d0" alt="Chat buffer">
</p>

<!-- panvimdoc-ignore-end -->

Run `:CodeCompanionChat` to open the chat buffer. Type your prompt and press `<CR>`. Toggle the chat buffer with `:CodeCompanionToggle`.

You can add context from your code base by using _variables_ and _slash commands_ in the chat buffer.

_Variables_, accessed via `#`, contain data about the present state of Neovim:

- `#buffer` - Share the current buffer's code. You can also specify line numbers with `#buffer:8-20`
- `#editor` - Share the buffers and lines that you see in the Neovim viewport
- `#lsp` - Share LSP information and code for the current buffer

_Slash commands_, accessed via `/`, run commands to add code to the chat buffer:

- `/buffer` - Share a specific buffer
- `/file` - Share a file from your repo

_Tools_, accessed via `@`, allow the LLM to function as an agent and carry out actions:

- `@buffer_editor` - The LLM will edit code in a Neovim buffer by searching and replacing blocks
- `@code_runner` - The LLM will run code for you in a Docker container
- `@rag` - The LLM will browse and search the internet for real-time information to supplement its response

> [!TIP]
> Press `?` in the chat buffer to reveal the keymaps and optons that are available to you.

**Inline Assistant**

<!-- panvimdoc-ignore-start -->

<p align="center">
  <img src="https://github.com/user-attachments/assets/1890a33a-bcda-4c6b-a1c4-849f2eaf97ef" alt="Inline Assistant">
</p>

<!-- panvimdoc-ignore-end -->

Run `:CodeCompanion <your prompt>` to call the inline assistant. The assistant will evaluate the prompt and either write some code (in the current buffer) or open a chat buffer. You can also make a visual selection and call the assistant.

The assistant has knowledge of your last conversation from a chat buffer. A prompt such as `:CodeCompanion add the new function here` will see the assistant add a code block directly into the current buffer.

For convenience, you can call [default prompts](#clipboard-default-prompts) via the assistant such as `:'<,'>CodeCompanion /buffer what does this file do?`. The available default prompts are:

- `/buffer` - Send the current buffer to the LLM alongside a prompt
- `/commit` - Generate a commit message
- `/explain` - Explain how selected code in a buffer works
- `/fix` - Fix the selected code
- `/lsp` - Explain the LSP diagnostics for the selected code
- `/tests` - Generate unit tests for selected code

There are keymaps available to accept or reject edits from the LLM in the [inline assistant](#pencil2-inline-assistant) section.

**Action Palette**

<!-- panvimdoc-ignore-start -->

<p align="center">
  <img src="https://github.com/user-attachments/assets/0d427d6d-aa5f-405c-ba14-583830251740" alt="Action Palette">
</p>

<!-- panvimdoc-ignore-end -->

Run `:CodeCompanionActions` to open the action palette, which gives you access to all of the functionality in the plugin. This is where core actions and the [default prompts](#clipboard-default-prompts) are listed.

> [!NOTE]
> Some actions will only be visible in if you're in _Visual mode_.

**List of commands**

Below is a list of all commands in the plugin:

- `CodeCompanion` - Open the inline assistant
- `CodeCompanion <your prompt>` - Prompt the inline assistant
- `CodeCompanion /<slash_cmd>` - Prompt the inline assistant with a slash command e.g. `/commit`
- `CodeCompanionChat` - Open a chat buffer
- `CodeCompanionChat <adapter>` - Open a chat buffer with a specific adapter
- `CodeCompanionToggle` - Toggle a chat buffer
- `CodeCompanionActions` - Open the _Action Palette_
- `CodeCompanionAdd` - Add visually selected chat to the current chat buffer

**Suggested workflow**

For an optimum workflow, I recommend the following keymaps:

```lua
vim.api.nvim_set_keymap("n", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<LocalLeader>a", "<cmd>CodeCompanionToggle<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<LocalLeader>a", "<cmd>CodeCompanionToggle<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "ga", "<cmd>CodeCompanionAdd<cr>", { noremap = true, silent = true })

-- Expand 'cc' into 'CodeCompanion' in the command line
vim.cmd([[cab cc CodeCompanion]])
```

## :gear: Configuration

Before configuring the plugin, it's important to understand how it's structured.

The plugin uses adapters to connect to LLMs. Out of the box, the plugin supports:

- Anthropic (`anthropic`) - Requires an API key and supports [prompt caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
- Copilot (`copilot`) - Requires a token which is created via `:Copilot setup` in [Copilot.vim](https://github.com/github/copilot.vim)
- Gemini (`gemini`) - Requires an API key
- Ollama (`ollama`) - Both local and remotely hosted
- OpenAI (`openai`) - Requires an API key

The plugin also utilises objects called Strategies. These are the different ways that a user can interact with the plugin. The _chat_ and _agent_ strategies harness a buffer to allow direct conversation with the LLM. The _inline_ strategy allows for output from the LLM to be written directly into a pre-existing Neovim buffer.

The plugin allows you to specify adapters for each strategy and also for each [default prompt](#clipboard-default-prompts).

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
    copilot = "copilot",
    gemini = "gemini",
    ollama = "ollama",
    openai = "openai",
    opts = {
      allow_insecure = false, -- Allow insecure connections?
      proxy = nil, -- [protocol://]host[:port] e.g. socks5://127.0.0.1:9999
    },
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
        ["editor"] = {
          callback = "helpers.variables.editor",
          description = "Share the code that you see in Neovim with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["lsp"] = {
          callback = "helpers.variables.lsp",
          description = "Share LSP information and code for the current buffer",
          opts = {
            contains_code = true,
          },
        },
      },
      slash_commands = {
        ["buffer"] = {
          callback = "helpers.slash_commands.buffer",
          description = "Share a loaded buffer's contents with the LLM",
          opts = {
            contains_code = true,
            provider = "default", -- default|telescope|fzf_lua
          },
        },
        ["file"] = {
          callback = "helpers.slash_commands.file",
          description = "Share a file's contents with the LLM",
          opts = {
            contains_code = true,
            max_lines = 1000,
            provider = "telescope", -- telescope|mini_pick|fzf_lua
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
        send = {
          modes = {
            n = { "<CR>", "<C-s>" },
            i = "<C-s>",
          },
          index = 1,
          callback = "keymaps.send",
          description = "Send",
        },
        regenerate = {
          modes = {
            n = "gr",
          },
          index = 2,
          callback = "keymaps.regenerate",
          description = "Regenerate the last response",
        },
        close = {
          modes = {
            n = "<C-c>",
            i = "<C-c>",
          },
          index = 3,
          callback = "keymaps.close",
          description = "Close Chat",
        },
        stop = {
          modes = {
            n = "q",
          },
          index = 4,
          callback = "keymaps.stop",
          description = "Stop Request",
        },
        clear = {
          modes = {
            n = "gx",
          },
          index = 5,
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
          index = 7,
          callback = "keymaps.next_chat",
          description = "Next Chat",
        },
        previous_chat = {
          modes = {
            n = "{",
          },
          index = 8,
          callback = "keymaps.previous_chat",
          description = "Previous Chat",
        },
        next_header = {
          modes = {
            n = "]]",
          },
          index = 9,
          callback = "keymaps.next_header",
          description = "Next Header",
        },
        previous_header = {
          modes = {
            n = "[[",
          },
          index = 10,
          callback = "keymaps.previous_header",
          description = "Previous Header",
        },
        change_adapter = {
          modes = {
            n = "ga",
          },
          index = 11,
          callback = "keymaps.change_adapter",
          description = "Change adapter",
        },
        fold_code = {
          modes = {
            n = "gf",
          },
          index = 12,
          callback = "keymaps.fold_code",
          description = "Fold code",
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
          opts = {
            visible = false,
          },
        },
        {
          role = "user",
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

            return "Please explain this code:\n\n```" .. context.filetype .. "\n" .. code .. "\n```\n\n"
          end,
          opts = {
            contains_code = true,
          },
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
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

            return "Please generate unit tests for this code:\n\n```" .. context.filetype .. "\n" .. code .. "\n```\n\n"
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
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

            return "Please fix the selected code:\n\n```" .. context.filetype .. "\n" .. code .. "\n```\n\n"
          end,
          opts = {
            contains_code = true,
          },
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
          content = function(context)
            local buf_utils = require("codecompanion.utils.buffers")

            return " \n\n```" .. context.filetype .. "\n" .. buf_utils.get_content(context.bufnr) .. "\n```\n\n"
          end,
          opts = {
            contains_code = true,
            visible = false,
          },
        },
        {
          role = "user",
          condition = function(context)
            return context.is_visual
          end,
          content = function(context)
            local selection = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)
            return "And this is some that relates to my question:\n\n```"
              .. context.filetype
              .. "\n"
              .. selection
              .. "\n```\n\n"
          end,
          opts = {
            contains_code = true,
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
        index = 9,
        default_prompt = true,
        mapping = "<LocalLeader>cm",
        slash_cmd = "commit",
        auto_submit = true,
      },
      prompts = {
        {
          role = "user",
          content = function()
            return "You are an expert at following the Conventional Commit specification. Given the git diff listed below, please generate a commit message for me:"
              .. "\n\n```\n"
              .. vim.fn.system("git diff")
              .. "\n```"
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

      separator = "─", -- The separator between the different messages in the chat buffer
      show_settings = false, -- Show LLM settings at the top of the chat buffer?

      show_token_count = true, -- Show the token count for each response?

      ---@param tokens number
      ---@param adapter CodeCompanion.Adapter
      token_count = function(tokens, adapter) -- The function to display the token count
        return " (" .. tokens .. " tokens)"
      end,
    },
    inline = {
      -- If the inline prompt creates a new buffer, how should we display this?
      layout = "vertical", -- vertical|horizontal|buffer
      diff = {
        enabled = true,
        close_chat_at = 240, -- Close an open chat buffer if the total columns of your display are less than...
        layout = "vertical", -- vertical|horizontal
        opts = { "internal", "filler", "closeoff", "algorithm:patience", "followwrap", "linematch:120" },
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

    use_default_actions = true, -- Show the default actions in the action palette?
    use_default_prompts = true, -- Show the default prompts in the action palette?

    -- This is the default prompt which is sent with every request in the chat
    -- strategy. It is primarily based on the GitHub Copilot Chat's prompt
    -- but with some modifications. You can choose to remove this via
    -- your own config but note that LLM results may not be as good
    system_prompt = [[You are an AI programming assistant named "CodeCompanion".
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
})
```

</details>

<!-- panvimdoc-ignore-end -->

### :electric_plug: Adapters

Please refer to your [chosen adapter](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters) to understand its configuration. You will need to set an API key for non-locally hosted LLMs.

> [!TIP]
> To create your own adapter or better understand how they work, please refer to the [ADAPTERS](doc/ADAPTERS.md) guide.

**Changing the Default Adapter**

To specify a different adapter to the default (`openai`), simply change the `strategies.*` table:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      adapter = "anthropic",
    },
    inline = {
      adapter = "copilot",
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
          api_key = "MY_OTHER_ANTHROPIC_KEY"
        },
      })
    end,
  },
})
```

In the example above, we're using the base of the Anthropic adapter but changing the name of the default API key which it uses.

**Setting an API Key Using a Command**

Having API keys in plain text in your shell is not always safe. Thanks to [this PR](https://github.com/olimorris/codecompanion.nvim/pull/24), you can run commands from within your config.  In the example below, we're using the 1Password CLI to read an OpenAI credential.

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

**Using Ollama Remotely**

To use Ollama remotely, simply change the URL in the `env` table and set an API key:

```lua
require("codecompanion").setup({
  adapters = {
    ollama = function()
      return require("codecompanion.adapters").extend("ollama", {
        env = {
          url = "https://my_ollama_url",
          api_key = "OLLAMA_API_KEY",
        },
        headers = {
          ["Content-Type"] = "application/json",
          ["Authorization"] = "Bearer ${api_key}",
        },
        parameters = {
          sync = true,
        },
      })
    end,
  },
})
```

**Connecting via a Proxy**

```lua
require("codecompanion").setup({
  adapters = {
    opts = {
      allow_insecure = true, -- Use if required
      proxy = "socks5://127.0.0.1:9999"
    }
  },
})
```

**Changing an Adapter's Default Model**

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

**Configuring Adapter Settings**

LLMs have many settings such as _model_, _temperature_ and _max_tokens_. In an adapter, these sit within a schema table and can be configured during setup:

```lua
require("codecompanion").setup({
  adapters = {
    llama3 = function()
      return require("codecompanion.adapters").extend("ollama", {
        name = "llama3", -- Ensure this adapter is differentiated from Ollama
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

## :bulb: Advanced Usage

### :clipboard: Default Prompts

The plugin comes with a number of default prompts. As per [the config](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua), these can be called via keymaps or slash commands (via the inline assistant). These prompts have been carefully curated to mimic those in [GitHub's Copilot Chat](https://docs.github.com/en/copilot/using-github-copilot/asking-github-copilot-questions-in-your-ide). Of course, you can create your own prompts and add them to the Action Palette. Please see the [RECIPES](doc/RECIPES.md) guide for more information.

### :speech_balloon: The Chat Buffer

The chat buffer is where you converse with an LLM from within Neovim. The chat buffer has been designed to be turn based, whereby you send a message and the LLM replies. Messages are segmented by H2 headers and once a message has been sent, it cannot be edited. You can also have multiple chat buffers open at the same.

The look and feel of the chat buffer can be customised as per the `display.chat` table in the [config](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua). You can also add additional _Variables_ and _Slash Commands_ which can then be referenced in the chat buffer.

**Keymaps**

When in the chat buffer, there are number of keymaps available to you:

- `?` - Bring up the options menu
- `<CR>`|`<C-s>` - Send the buffer to the LLM
- `<C-c>` - Close the buffer
- `q` - Cancel the request from the LLM
- `gr` - Regenerate the last response from the LLM
- `ga` - Change the adapter
- `gx` - Clear the buffer's contents
- `gx` - Add a codeblock
- `gf` - To refresh the code folds in the buffer
- `}` - Move to the next chat
- `{` - Move to the previous chat
- `]]` - Move to the next header
- `[[` - Move to the previous header

**Settings**

You can display your selected adapter's schema at the top of the buffer, if `display.chat.show_settings` is set to `true`. This allows you to vary the response from the LLM.

**Slash Commands**

Slash Commands allow you to easily share additional context with your LLM from the chat buffer. There are a number of providers you can use to accomplish this:

- `/buffer` - Has a `default` provider (which leverages `vim.ui.select`), `telescope` and `fzf_lua`
- `/files` - Has `telescope`, `mini_pick` and `fzf_lua`

Please refer to [the config](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua) to see how to change the default provider.

### :pencil2: Inline Assistant

> [!NOTE]
> If `send_code = false` in the config then this will take precedent and no code will be sent to the LLM

One of the challenges with inline editing is determining how the LLM's response should be handled in the buffer. If you've prompted the LLM to _"create a table of 5 common text editors"_ then you may wish for the response to be placed at the cursor's position in the current buffer. However, if you asked the LLM to _"refactor this function"_ then you'd expect the response to _replace_ a visual selection. The plugin will use the inline LLM you've specified in your config to determine if the response should...

- _replace_ - replace a visual selection you've made
- _add_ - be added in the current buffer at the cursor position
- _new_ - be placed in a new buffer
- _chat_ - be placed in a chat buffer

By default, an inline assistant prompt will trigger the diff feature, showing differences between the original buffer and the changes from the LLM. This can be turned off in your config via the `display.inline.diff` table. You can also choose to accept or reject the LLM's suggestions with the following keymaps:

- `ga` - Accept an inline edit
- `gr` - Reject an inline edit

### :robot: Agents / Tools

<!-- panvimdoc-ignore-start -->

<div align="center">
  <p>https://github.com/user-attachments/assets/8bc083c7-f4f1-4eab-b9fe-ab6c4c30ee91</p>
</div>

<!-- panvimdoc-ignore-end -->

As outlined by Andrew Ng in [Agentic Design Patterns Part 3, Tool Use](https://www.deeplearning.ai/the-batch/agentic-design-patterns-part-3-tool-use), LLMs can act as agents by leveraging external tools. Andrew notes some common examples such as web searching or code execution that have obvious benefits when using LLMs.

In the plugin, agents are simply context that's given to an LLM via a `system` prompt. This gives it knowledge and a defined schema which it can include in its response for the plugin to parse, execute and feedback on. Agents can be added as a participant in a chat buffer by using the `@` key.

More information on how agents work and how you can create your own can be found in the [AGENTS](doc/AGENTS.md) guide.

### :world_map: Workflows

> [!WARNING]
> Workflows may result in the significant consumption of tokens if you're using an external LLM.

As [outlined](https://www.deeplearning.ai/the-batch/issue-242/) by Andrew Ng, agentic workflows have the ability to dramatically improve the output of an LLM. Infact, it's possible for older models like GPT 3.5 to outperform newer models (using traditional zero-shot inference). Andrew [discussed](https://www.youtube.com/watch?v=sal78ACtGTc&t=249s) how an agentic workflow can be utilised via multiple prompts that invoke the LLM to self reflect. Implementing Andrew's advice, the plugin supports this notion via the use of workflows. At various stages of a pre-defined workflow, the plugin will automatically prompt the LLM without any input or triggering required from the user.

Currently, the plugin comes with the following workflows:

- Adding a new feature
- Refactoring code

Of course you can add new workflows by following the [RECIPES](doc/RECIPES.md) guide.

## :lollipop: Extras

**Highlight Groups**

The plugin sets the following highlight groups during setup:

- `CodeCompanionChatHeader` - The headers in the chat buffer
- `CodeCompanionChatSeparator` - Separator between headings in the chat buffer
- `CodeCompanionChatTokens` - Virtual text in the chat buffer showing the token count
- `CodeCompanionChatTool` - Tools in the chat buffer
- `CodeCompanionChatVariable` - Variables in the chat buffer
- `CodeCompanionVirtualText` - All other virtual text in the plugin

**Events/Hooks**

The plugin fires many events during its lifecycle:

- `CodeCompanionChatClosed` - Fired after a chat has been closed
- `CodeCompanionChatAdapter` - Fired after the adapter has been set in the chat
- `CodeCompanionAgentStarted` - Fired when an agent has started using a tool
- `CodeCompanionAgentFinished` - Fired when an agent has finished using a tool
- `CodeCompanionInlineStarted` - Fired at the start of the Inline strategy
- `CodeCompanionInlineFinished` - Fired at the end of the Inline strategy
- `CodeCompanionRequestStarted` - Fired at the start of any API request
- `CodeCompanionRequestFinished` - Fired at the end of any API request

> [!TIP]
> Some events are sent with a data payload which can be leveraged.

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

and inspect the log file as per the location from the checkhealth command.

<!-- panvimdoc-ignore-start -->

## :gift: Contributing

I am open to contributions but they will be implemented at my discretion. Feel free to open up a discussion before embarking on a PR and please read the [CONTRIBUTING.md](CONTRIBUTING.md) guide.

## :clap: Acknowledgements

- [Steven Arcangeli](https://github.com/stevearc) for his genius creation of the chat buffer and his feedback early on
- [Dante.nvim](https://github.com/S1M0N38/dante.nvim) for the beautifully simple diff implementation
- [Wtf.nvim](https://github.com/piersolenski/wtf.nvim) for the LSP assistant action
- [CopilotChat.nvim](https://github.com/CopilotC-Nvim/CopilotChat.nvim) for the rendering and usability of the chat
buffer

<!-- panvimdoc-ignore-end -->
