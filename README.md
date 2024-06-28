<!-- panvimdoc-ignore-start -->

<p align="center">
<img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/e54f98b6-8bfd-465a-85b6-73ab6bb274fa" alt="CodeCompanion.nvim" />
</p>

<p align="center">
<a href="https://github.com/olimorris/codecompanion.nvim/stargazers"><img src="https://img.shields.io/github/stars/olimorris/codecompanion.nvim?color=c678dd&logoColor=e06c75&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/issues"><img src="https://img.shields.io/github/issues/olimorris/codecompanion.nvim?color=%23d19a66&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/blob/main/LICENSE"><img src="https://img.shields.io/github/license/olimorris/codecompanion.nvim?style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/olimorris/codecompanion.nvim/ci.yml?branch=main&label=tests&style=for-the-badge"></a>
</p>

<p align="center">
Currently supports: Anthropic, Ollama and OpenAI adapters
</p>

> [!IMPORTANT]
> This plugin is provided as-is and is primarily developed for my own workflows. As such, I offer no guarantees of regular updates or support and I expect the plugin's API to change regularly. Bug fixes and feature enhancements will be implemented at my discretion, and only if they align with my personal use-cases. Feel free to fork the project and customize it to your needs, but please understand my involvement in further development will be intermittent. To be notified of breaking changes in the plugin, please subscribe to [this issue](https://github.com/olimorris/codecompanion.nvim/issues/9).

<p align="center">
<img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/5e5a5e54-c1d9-4fe2-8ae0-1cfbfdd6cea5" alt="Header" />
</p>

<!-- panvimdoc-ignore-end -->

## :sparkles: Features

- :speech_balloon: A Copilot Chat experience in Neovim
- :electric_plug: Support for OpenAI, Anthropic and Ollama
- :rocket: Inline code creation and refactoring
- :robot: Agentic Workflows and Tools to improve LLM output
- :sparkles: Built in prompts for LSP error fixes and code advice
- :building_construction: Create your own custom prompts for Neovim
- :floppy_disk: Save and restore your chats
- :muscle: Async execution for improved performance

<!-- panvimdoc-ignore-start -->

## :camera_flash: Screenshots

<div align="center">
  <p>https://github.com/olimorris/codecompanion.nvim/assets/9512444/3bd96f3e-6195-40f4-b427-99999a3fff99</p>
  <p>https://github.com/olimorris/codecompanion.nvim/assets/9512444/4e7972d3-4c53-4fe7-8fb7-0dce174d94b5</p>
</div>

<!-- panvimdoc-ignore-end -->

## :zap: Requirements

- The `curl` library installed
- Neovim 0.9.2 or greater
- _(Optional)_ An API key for your chosen LLM
- _(Optional)_ The `base64` library installed

## :package: Installation

Install the plugin with your package manager of choice:

```lua
-- Lazy.nvim
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

-- Packer.nvim
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

You only need to the call the `setup` function if you wish to change any of the defaults:

<details>
  <summary>Click to see the default configuration</summary>

```lua
require("codecompanion").setup({
  adapters = {
    anthropic = "anthropic",
    ollama = "ollama",
    openai = "openai",
  },
  strategies = {
    chat = "openai",
    inline = "openai",
    tool = "openai",
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
    ["Fix LSP Diagnostics"] = {
      strategy = "chat",
      description = "Use an LLM to fix your LSP diagnostics",
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
  tools = {
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
  },
  keymaps = {
    ["<C-s>"] = "keymaps.save",
    ["<C-c>"] = "keymaps.close",
    ["q"] = "keymaps.stop",
    ["gc"] = "keymaps.clear",
    ["ga"] = "keymaps.codeblock",
    ["gs"] = "keymaps.save_chat",
    ["gt"] = "keymaps.add_tool",
    ["]"] = "keymaps.next",
    ["["] = "keymaps.previous",
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

You also have access to tools that you can use to initiate actions on the user's machine:
- Code Runner: To run any code that you've generated and receive the output
- RAG: To supplement your responses with real-time information and insight

When informed by the user of an available tool, pay attention to the schema that the user provides in order to execute the tool.]],
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
})
```

</details>

**Adapters**

> [!WARNING]
> Depending on your [chosen adapter](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters), you may need to set an API key.

The plugin uses adapters to bridge between LLMs and the plugin. Currently the plugin supports:

- Anthropic (`anthropic`) - Requires an API key
- Ollama (`ollama`)
- OpenAI (`openai`) - Requires an API key

Strategies are the different ways that a user can interact with the plugin. The _chat_ and _tool_ strategies harness a buffer to allow direct conversation with the LLM. The _inline_ strategy allows for output from the LLM to be written directly into a pre-existing Neovim buffer.

To specify a different adapter to the defaults, simply change the `strategies.*` table:

```lua
require("codecompanion").setup({
  strategies = {
    chat = "ollama",
    inline = "ollama",
    tool = "anthropic"
  },
})
```

> [!TIP]
> To create your own adapter please refer to the [ADAPTERS](ADAPTERS.md) guide.

**Configuring environment variables**

You can customise an adapter's configuration as follows:

```lua
require("codecompanion").setup({
  adapters = {
    anthropic = require("codecompanion.adapters").use("anthropic", {
      env = {
        api_key = "ANTHROPIC_API_KEY_1"
      },
    }),
  },
  strategies = {
    chat = "anthropic",
    inline = "anthropic",
    tool = "anthropic"
  },
})
```

In the example above, we've changed the name of the default API key which the Anthropic adapter uses. Having API keys in plain text in your shell is not always safe. Thanks to [this PR](https://github.com/olimorris/codecompanion.nvim/pull/24), you can run commands from within the configuration:

```lua
require("codecompanion").setup({
  adapters = {
    openai = require("codecompanion.adapters").use("openai", {
      env = {
        api_key = "cmd:op read op://personal/OpenAI/credential --no-newline",
      },
    }),
    strategies = {
      chat = "openai",
      inline = "anthropic",
      tool = "openai"
    },
  },
})
```

In this example, we're using the 1Password CLI to read an OpenAI credential.

**Configuring adapter settings**

LLMs have many settings such as _model_, _temperature_ and _max_tokens_. In an adapter, these sit within a schema table and can be configured during setup:

```lua
require("codecompanion").setup({
  adapters = {
    anthropic = require("codecompanion.adapters").use("anthropic", {
      schema = {
        model = {
          default = "claude-3-sonnet-20240229",
        },
      },
    }),
  },
})
```

> [!TIP]
> Refer to your chosen [adapter](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters) to see the settings available.

**Highlight Groups**

The plugin sets the following highlight groups during setup:

- `CodeCompanionTokens` - Virtual text in the chat buffer showing the token count
- `CodeCompanionVirtualText` - All other virtual text in the chat buffer
- `CodeCompanionVirtualTextTools` - Virtual text in the chat buffer for when a tool is running

## :rocket: Getting Started

**Inline Prompting**

<!-- panvimdoc-ignore-start -->

<div align="center">
  <p>https://github.com/olimorris/codecompanion.nvim/assets/9512444/2b072735-eb43-468a-9d4b-8e401a46beca</p>
</div>

<!-- panvimdoc-ignore-end -->

To start interacting with the plugin you can run `:CodeCompanion <your prompt>` from the command line. You can also make a visual selection in Neovim and run `:'<,'>CodeCompanion <your prompt>` to send it as context. A command such as `:'<,'>CodeCompanion what does this code do?` will prompt the LLM the respond in a chat buffer allowing you to ask any follow up questions. Whereas a command such as `:CodeCompanion can you create a function that outputs the current date and time` would result in the output being placed at the cursor's position in the buffer.

> [!NOTE]
> Any open and loaded buffers can be sent to the LLM as context with the `@buffers` keyword, assuming they match the current filetype. For example: `:'<,'>CodeCompanion @buffers can you explain this class?`.

**Chat Buffer**

<!-- panvimdoc-ignore-start -->

<p><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/654b8ce6-be61-42c8-b5e7-0437ea03ac8e" alt="Chat buffer"></p>

<!-- panvimdoc-ignore-end -->

The chat buffer is where you'll likely spend most of your time. Running `:CodeCompanionChat` or `:'<,'>CodeCompanionChat` will open up a chat buffer where you can converse directly with an LLM. As a convenience, you can use `:CodeCompanionToggle` to toggle the latest chat buffer. There are many convenient keymaps you can leverage in the chat buffer which are covered in the section below.

**Action Palette**

<!-- panvimdoc-ignore-start -->

<p><img src="https://github.com/olimorris/codecompanion.nvim/assets/9512444/efb7013e-6c73-48fe-bd79-cdc233dfdc61" alt="Action Palette"></p>

<!-- panvimdoc-ignore-end -->

The `:CodeCompanionActions` command will open the _Action Palette_, giving you access to all of the functionality in the plugin. The _Prompts_ section is where your custom prompts and the pre-defined ones can be accessed. You'll notice that some prompts have a label in their description such as `@commit`. This enables you to more easily trigger them from the command line by doing `:CodeCompanion @commit`. Some of these prompts also have keymaps assigned to them (which can be overwritten!) which offers an even easier route to triggering them.

> [!NOTE]
> Some actions will only be visible in the _Action Palette_ if you're in Visual mode.

**List of commands**

Below is the full list of commands that are available in the plugin:

- `CodeCompanionActions` - To open the _Action Palette_
- `CodeCompanion` - Inline prompting of the plugin
- `CodeCompanion <shortcut>` - Inline prompting of the plugin with a shortcut e.g. `@commit`
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

A [RECIPES](RECIPES.md) guide has been created to show you how you can add your own prompts to the _Action Palette_

### The Chat Buffer

The chat buffer is where you can converse with an LLM, directly from Neovim. It behaves as a regular markdown buffer with some clever additions. When the buffer is written (or "saved"), autocmds trigger the sending of its content to the LLM in the form of prompts. These prompts are segmented by H1 headers: `user`, `system` and `assistant`. When a response is received, it is then streamed back into the buffer. The result is that you experience the feel of conversing with your LLM from within Neovim.

**Keymaps**

When in the chat buffer, there are number of keymaps available to you:

- `<C-s>` - Save the buffer and trigger a response from the LLM
- `<C-c>` - Close the buffer
- `q` - Cancel the stream from the LLM
- `gc` - Clear the buffer's contents
- `ga` - Add a codeblock
- `gs` - Save the chat to disk
- `gt` - Add a tool to an existing chat
- `[` - Move to the next header
- `]` - Move to the previous header

**Saved Chats**

Chat buffers are not saved to disk by default, but can be by pressing `gs` in the buffer. Saved chats can then be restored via the Action Palette and the _Load saved chats_ action.

**Settings**

If `display.chat.show_settings` is set to `true`, at the very top of the chat buffer will be the adapter's model parameters which can be changed to tweak the response. You can find more detail about them by moving the cursor over them.

**Open Chats**

From the Action Palette, the `Open Chats` action enables users to easily navigate between their open chat buffers. A chat buffer can be deleted (and removed from memory) by pressing `<C-c>`.

### Inline Prompting

> [!NOTE]
> If `send_code = false` then this will take precedent and no buffers will be sent to the LLM

Inline prompts can be triggered via the `CodeCompanion <your prompt>` command. As mentioned in the [Getting Started](#rocket-getting-started) guide, you can also leverage visual selections and prompt shortcuts like `'<,'>CodeCompanion @lsp`.

One of the challenges with inline editing is determining how the LLM's response should be handled in the buffer. If you've prompted the LLM to _"create a table of 5 common text editors"_ then you may wish for the response to be placed after the cursor's current position in the buffer. However, if you asked the LLM to _"refactor this function"_ then you'd expect the response to overwrite a visual selection. The plugin will use the inline LLM you've specified to determine if the response should follow any of the placements below:

- _after_ - after the visual selection/cursor
- _before_ - before the visual selection/cursor
- _new_ - in a new buffer
- _replace_ - replacing the visual selection
- _chat_ - in a chat buffer

### Default Prompts

> [!NOTE]
> Please see the [RECIPES](RECIPES.md) guide in order to add your own pre-defined prompts to the palette.

The plugin comes with a number of default prompts and corresponding keymaps/shortcuts:

- Custom Prompt - For custom inline prompting of an LLM (`<LocalLeader>cc`)
- Senior Developer - Chat with a senior developer for the given filetype (`<LocalLeader>ce`)
- Generate a Commit Message - Use an LLM to write a commit message for you (`<LocalLeader>cm` / `@commit`)
- Code Advisor - Get advice from an LLM on code you've selected (`<LocalLeader>ca` / `@advisor`)
- Fix LSP Diagnostics - Use an LLM to fix LSP diagnostics for code you've selected (`<LocalLeader>cl` / `@lsp`)

### Tools

<!-- panvimdoc-ignore-start -->

<p>https://github.com/olimorris/codecompanion.nvim/assets/9512444/a19229b1-36b2-43b0-ad87-600da06b371e</p>

<!-- panvimdoc-ignore-end -->

> [!IMPORTANT]
> Tools are currently at an alpha stage. I'm yet to properly battle test them so feedback is much appreciated.

As outlined by Andrew Ng in [Agentic Design Patterns Part 3, Tool Use](https://www.deeplearning.ai/the-batch/agentic-design-patterns-part-3-tool-use), LLMs can act as agents by leveraging external tools. Andrew notes some common examples such as web searching or code execution that have obvious benefits when using LLMs.

In this plugin, tools are simply context that's given to an LLM via a `system` prompt. This gives it knowledge and a defined schema which it can include in its response for the plugin to parse, execute and feedback on. Tools can be leveraged by opening up the action palette and choosing the _tools_ option. Or, tools can be added when in an existing chat buffer via the `gt` keymap.

More information on how tools work and how you can create your own can be found in the [TOOLS](TOOLS.md) guide.

### Workflows

> [!WARNING]
> Workflows may result in the significant consumption of tokens if you're using an external LLM.

As [outlined](https://www.deeplearning.ai/the-batch/issue-242/) by Andrew Ng, agentic workflows have the ability to dramatically improve the output of an LLM. Infact, it's possible for older models like GPT 3.5 to outperform newer models (using traditional zero-shot inference). Andrew [discussed](https://www.youtube.com/watch?v=sal78ACtGTc&t=249s) how an agentic workflow can be utilised via multiple prompts that invoke the LLM to self reflect. Implementing Andrew's advice, the plugin supports this notion via the use of workflows. At various stages of a pre-defined workflow, the plugin will automatically prompt the LLM without any input or triggering required from the user.

Currently, the plugin comes with the following workflows:

- Adding a new feature
- Refactoring code

Of course you can add new workflows by following the [RECIPES](RECIPES.md) guide.

## :rainbow: Helpers

**Hooks / User events**

The plugin fires the following events during its lifecycle:

- `CodeCompanionRequest` - Fired during the API request. Outputs `data.status` with a value of `started` or `finished`
- `CodeCompanionChatSaved` - Fired after a chat has been saved to disk
- `CodeCompanionChat` - Fired at various points during the chat buffer. Comes with the following attributes:
  - `data.action = hide_buffer` - For when a chat buffer is hidden
  - `data.action = show_buffer` - For when a chat buffer is visible after being hidden
- `CodeCompanionInline` - Fired during the inline API request alongside `CodeCompanionRequest`. Outputs `data.status` with a value of `started` or `finished`
- `CodeCompanionTool` - Fired when a tool is running. Outputs `data.status` with a value of `started` or `success`/`failure`

Events can be hooked into as follows:

```lua
local group = vim.api.nvim_create_augroup("CodeCompanionHooks", {})

vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "CodeCompanionInline",
  group = group,
  callback = function(request)
    print(request.data.status) -- outputs "started" or "finished"
  end,
})
```

**Statuslines**

You can incorporate a visual indication to show when the plugin is communicating with an LLM in your Neovim configuration. Below are examples for two popular statusline plugins.

**lualine.nvim:**

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
    pattern = "CodeCompanionRequest",
    group = group,
    callback = function(request)
      self.processing = (request.data.status == "started")
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

**heirline.nvim:**

```lua
local CodeCompanion = {
  static = {
    processing = false,
  },
  update = {
    "User",
    pattern = "CodeCompanionRequest",
    callback = function(self, args)
      self.processing = (args.data.status == "started")
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

<!-- panvimdoc-ignore-start -->

## :gift: Contributing

I am open to contributions but they will be implemented at my discretion. Feel free to open up a discussion before embarking on a big PR and please make sure you've read the [CONTRIBUTING.md](CONTRIBUTING.md) guide.

## :clap: Acknowledgements

- [Steven Arcangeli](https://github.com/stevearc) for his genius creation of the chat buffer and his feedback
- [Wtf.nvim](https://github.com/piersolenski/wtf.nvim) for the LSP assistant action
- [ChatGPT.nvim](https://github.com/jackMort/ChatGPT.nvim) for the calculation of tokens

<!-- panvimdoc-ignore-end -->
