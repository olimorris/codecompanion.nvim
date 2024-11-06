<!-- panvimdoc-ignore-start -->

<p align="center">
<img src="https://github.com/user-attachments/assets/b56cbf02-2e48-43a2-9d86-321209bc0664" alt="CodeCompanion.nvim" />
</p>

<p align="center">
<a href="https://github.com/olimorris/codecompanion.nvim/stargazers"><img src="https://img.shields.io/github/stars/olimorris/codecompanion.nvim?color=c678dd&logoColor=e06c75&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/olimorris/codecompanion.nvim/ci.yml?branch=main&label=tests&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/releases"><img src="https://img.shields.io/github/v/release/olimorris/codecompanion.nvim?style=for-the-badge"></a>
</p>

<p align="center">
Currently supports: Anthropic, Copilot, Gemini, Ollama, OpenAI, Azure OpenAI and xAI adapters<br><br>
New features are always announced <a href="https://github.com/olimorris/codecompanion.nvim/discussions/categories/announcements">here</a>
</p>

## :purple_heart: Sponsors

Thank you to the following people:

<p align="center">
<!-- coffee --><a href="https://github.com/bassamsdata"><img src="https://github.com/bassamsdata.png" width="60px" alt="Bassam Data" /></a><a href="https://github.com/ivo-toby"><img src="https://github.com/ivo-toby.png" width="60px" alt="Ivo Toby" /></a><a href="https://github.com/KTSCode"><img src="https://github.com/KTSCode.png" width="60px" alt="KTS Code" /></a><a href="https://x.com/luxus"><img src="https://pbs.twimg.com/profile_images/744754093495844864/GwnEJygG_400x400.jpg" width="60px" alt="Luxus" /></a><!-- coffee --><!-- sponsors --><a href="https://github.com/zhming0"><img src="https:&#x2F;&#x2F;avatars.githubusercontent.com&#x2F;u&#x2F;1054703?u&#x3D;b173a2c1afc61fa25d9343704659630406e3dea7&amp;v&#x3D;4" width="60px" alt="Zhiming Guo" /></a><a href="https://github.com/carlosflorencio"><img src="https:&#x2F;&#x2F;avatars.githubusercontent.com&#x2F;u&#x2F;1500881?u&#x3D;6b4f80028aea4589bc3632739a40191bbcf58d22&amp;v&#x3D;4" width="60px" alt="Carlos Florêncio" /></a><!-- sponsors -->
</p>

<!-- panvimdoc-ignore-end -->

## :sparkles: Features

- :speech_balloon: [Copilot Chat](https://github.com/features/copilot) meets [Zed AI](https://zed.dev/blog/zed-ai), in Neovim
- :electric_plug: Support for Anthropic, Copilot, Gemini, Ollama, OpenAI, Azure OpenAI and xAI LLMs (or bring your own!)
- :rocket: Inline transformations, code creation and refactoring
- :robot: Variables, Slash Commands, Agents/Tools and Workflows to improve LLM output
- :sparkles: Built in prompt library for common tasks like advice on LSP errors and code explanations
- :building_construction: Create your own custom prompts, Variables and Slash Commands
- :books: Have multiple chats open at the same time
- :muscle: Async execution for fast performance

<!-- panvimdoc-ignore-start -->

## :camera_flash: Screenshots

<div align="center">
  <p>https://github.com/user-attachments/assets/04a2bed3-7af0-4c07-b58f-f644cef1c4bb</p>
  <p>https://github.com/user-attachments/assets/4e2a3680-cef5-4134-bf94-e2be93242b38</p>
</div>

<!-- panvimdoc-ignore-end -->

## :zap: Requirements

- The `curl` library
- Neovim 0.10.0 or greater
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
    "nvim-telescope/telescope.nvim", -- Optional: For using slash commands
    { "MeanderingProgrammer/render-markdown.nvim", ft = { "markdown", "codecompanion" } }, -- Optional: For prettier markdown rendering
    { "stevearc/dressing.nvim", opts = {} }, -- Optional: Improves `vim.ui.select`
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
    "nvim-telescope/telescope.nvim", -- Optional: For using slash commands
    { "MeanderingProgrammer/render-markdown.nvim", ft = { "markdown", "codecompanion" } }, -- Optional: For prettier markdown rendering
    "stevearc/dressing.nvim" -- Optional: Improves `vim.ui.select`
  }
})
```

**[vim-plug](https://github.com/junegunn/vim-plug)**

```vim
call plug#begin()

Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-treesitter/nvim-treesitter'
Plug 'hrsh7th/nvim-cmp', " Optional: For using slash commands and variables in the chat buffer
Plug 'nvim-telescope/telescope.nvim', " Optional: For using slash commands
Plug 'stevearc/dressing.nvim' " Optional: Improves `vim.ui.select`
Plug 'MeanderingProgrammer/render-markdown.nvim' " Optional: For prettier markdown rendering
Plug 'olimorris/codecompanion.nvim'

call plug#end()

lua << EOF
  require("codecompanion").setup()
EOF
```

> [!IMPORTANT]
> The plugin requires the markdown Tree-sitter parser to be installed with `:TSInstall markdown`

[Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) is a suggested inclusion as it makes leveraging the Slash Commands a little bit prettier. However, other providers are available. Please refer to the [Chat Buffer](#speech_balloon-the-chat-buffer) section for more information.

As per [#377](https://github.com/olimorris/codecompanion.nvim/issues/377), if you pin your plugins to the latest releases, consider setting plenary.nvim to:

```lua
{ "nvim-lua/plenary.nvim", branch = "master" },
```

## :rocket: Quickstart

> [!NOTE]
> Okay, okay...it's not quite a quickstart as you'll need to configure an [adapter](#electric_plug-adapters) and I recommend starting from the [configuration](#gear-configuration) section to understand how the plugin works.

**Chat Buffer**

<!-- panvimdoc-ignore-start -->

<p align="center">
  <img src="https://github.com/user-attachments/assets/597299d2-36b3-469e-b69c-4d8fd14838f8" alt="Chat buffer">
</p>

<!-- panvimdoc-ignore-end -->

Run `:CodeCompanionChat` to open the chat buffer. Type your prompt and press `<CR>`. Or, run `:CodeCompanionChat why are Lua and Neovim so perfect together?` to send a prompt directly to the chat buffer. Toggle the chat buffer with `:CodeCompanionChat Toggle`.

You can add context from your code base by using _Variables_ and _Slash Commands_ in the chat buffer.

_Variables_, accessed via `#`, contain data about the present state of Neovim:

- `#buffer` - Shares the current buffer's code. You can also specify line numbers with `#buffer:8-20`
- `#lsp` - Shares LSP information and code for the current buffer
- `#viewport` - Shares the buffers and lines that you see in the Neovim viewport

_Slash commands_, accessed via `/`, run commands to insert additional context into the chat buffer:

- `/buffer` - Insert open buffers
- `/fetch` - Insert URL contents
- `/file` - Insert a file
- `/help` - Insert content from help tags
- `/now` - Insert the current date and time
- `/symbols` - Insert symbols from a selected file
- `/terminal` - Insert terminal output

_Tools_, accessed via `@`, allow the LLM to function as an agent and carry out actions:

- `@cmd_runner` - The LLM will run shell commands (subject to approval)
- `@editor` - The LLM will edit code in a Neovim buffer
- `@files` -  The LLM will can work with files on the file system (subject to approval)
- `@rag` - The LLM will browse and search the internet for real-time information to supplement its response

Tools can also be grouped together to form _Agents_, which are also accessed via `@` in the chat buffer:

- `@full_stack_dev` - Contains the `cmd_runner`, `editor` and `files` tools.

> [!TIP]
> Press `?` in the chat buffer to reveal the keymaps and options that are available.

**Inline Assistant**

<!-- panvimdoc-ignore-start -->

<p align="center">
  <img src="https://github.com/user-attachments/assets/21568a7f-aea8-4928-b3d4-f39c6566a23c" alt="Inline Assistant">
</p>

> [!NOTE]
> The diff provider was selected as `mini_pick` in the video above

<!-- panvimdoc-ignore-end -->

Run `:CodeCompanion <your prompt>` to call the inline assistant. The assistant will evaluate the prompt and either write code or open a chat buffer. You can also make a visual selection and call the assistant.

The assistant has knowledge of your last conversation from a chat buffer. A prompt such as `:CodeCompanion add the new function here` will see the assistant add a code block directly into the current buffer.

For convenience, you can call prompts from the [prompt library](#clipboard-prompt-library) via the assistant such as `:'<,'>CodeCompanion /buffer what does this file do?`. The prompt library comes with the following defaults:

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

Run `:CodeCompanionActions` to open the action palette, which gives you access to all functionality of the plugin. By default the plugin uses `vim.ui.select`, however, you can change the provider by altering the `display.action_palette.provider` config value to be `telescope` or `mini_pick`. You can also call the Telescope extension with `:Telescope codecompanion`.

> [!NOTE]
> Some actions and prompts will only be visible if you're in _Visual mode_.

**List of commands**

The plugin has three core commands:

- `CodeCompanion` - Open the inline assistant
- `CodeCompanionChat` - Open a chat buffer
- `CodeCompanionActions` - Open the _Action Palette_

However, there are multiple options available:

- `CodeCompanion <your prompt>` - Prompt the inline assistant
- `CodeCompanion /<prompt library>` - Use the [prompt library](#clipboard-prompt-library) with the inline assistant e.g. `/commit`
- `CodeCompanionChat <prompt>` - Send a prompt to the LLM via a chat buffer
- `CodeCompanionChat <adapter>` - Open a chat buffer with a specific adapter
- `CodeCompanionChat Toggle` - Toggle a chat buffer
- `CodeCompanionChat Add` - Add visually selected chat to the current chat buffer

**Suggested plugin workflow**

For an optimum plugin workflow, I recommend the following:

```lua
vim.api.nvim_set_keymap("n", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<C-a>", "<cmd>CodeCompanionActions<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<LocalLeader>a", "<cmd>CodeCompanionChat Toggle<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<LocalLeader>a", "<cmd>CodeCompanionChat Toggle<cr>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "ga", "<cmd>CodeCompanionChat Add<cr>", { noremap = true, silent = true })

-- Expand 'cc' into 'CodeCompanion' in the command line
vim.cmd([[cab cc CodeCompanion]])
```

> [!NOTE]
> You can also assign prompts from the library to specific mappings. See the [prompt library](#clipboard-prompt-library) section for more information.

## :gear: Configuration

Before configuring the plugin, it's important to understand how it's structured.

The plugin uses adapters to connect to LLMs. Out of the box, the plugin supports:

- Anthropic (`anthropic`) - Requires an API key and supports [prompt caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
- Copilot (`copilot`) - Requires a token which is created via `:Copilot setup` in [Copilot.vim](https://github.com/github/copilot.vim)
- Gemini (`gemini`) - Requires an API key
- Ollama (`ollama`) - Both local and remotely hosted
- OpenAI (`openai`) - Requires an API key
- Azure OpenAI (`azure_openai`) - Requires an Azure OpenAI service with a model deployment
- xAI (`xai`) - Requires an API key

The plugin utilises objects called Strategies. These are the different ways that a user can interact with the plugin. The _chat_ strategy harnesses a buffer to allow direct conversation with the LLM. The _inline_ strategy allows for output from the LLM to be written directly into a pre-existing Neovim buffer. The _agent_ and _workflow_ strategies are wrappers for the _chat_ strategy, allowing for [tool use](#robot-agents--tools) and [agentic workflows](#world_map-agentic-workflows).

The plugin allows you to specify adapters for each strategy and also for each [prompt library](#clipboard-prompt-library) entry.

### :hammer_and_wrench: Changing the Defaults

The default config can be found in the [config.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua) file and the defaults can be changed by calling the `setup` function:

```lua
require("codecompanion").setup({
  display = {
    diff = {
      provider = "mini_diff",
    },
  },
  opts = {
    log_level = "DEBUG",
  },
})
```

Please refer to the [adapter](#electric_plug-adapters) section below in order to configure adapters.

**Changing the System Prompt**

The default system prompt has been carefully curated to deliver responses which are similar to GitHub Copilot Chat, no matter which LLM you use. That is, you'll receive responses which are terse, professional and with expertise in coding. However, you can modify the `opts.system_prompt` table in the config to suit your needs. You can also set it as a function which can receive the current chat buffer's adapter as a parameter, giving you the option of setting system prompts that are LLM or model specific:

```lua
require("codecompanion").setup({
  opts = {
    ---@param adapter CodeCompanion.Adapter
    ---@return string
    system_prompt = function(opts)
      if opts.adapter.schema.model.default == "llama3.1:latest" then
        return "My custom system prompt"
      end
      return "My default system prompt"
    end
  }
})
```
**Changing the Language**

CodeCompanion supports multiple languages for non-code responses. You can configure this in your setup:

```lua
require('codecompanion').setup({
  opts = {
    language = "English" -- Default is "English"
  }
})
```

**Using with render-markdown.nvim**

If you use the fantastic [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) plugin, then please ensure you turn off the `render_headers` display option:

```lua
require("codecompanion").setup({
  display = {
    chat = {
      render_headers = false,
    }
  }
})
```

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

Having API keys in plain text in your shell is not always safe. Thanks to [this PR](https://github.com/olimorris/codecompanion.nvim/pull/24), you can run commands from within your config by prefixing them with `cmd:`. In the example below, we're using the 1Password CLI to read an OpenAI credential.

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

To use Ollama remotely, change the URL in the `env` table, set an API key and pass it via an "Authorization" header:

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

**Using OpenAI compatible Models like LMStudio or self-hosted models**

To use any other OpenAI compatible models, change the URL in the `env` table, set an API key:

```lua
require("codecompanion").setup({
  adapters = {
    ollama = function()
      return require("codecompanion.adapters").extend("openai_compatible", {
        env = {
          url = "http[s]://open_compatible_ai_url", -- optional: default value is ollama url http://127.0.0.1:11434
          api_key = "OpenAI_API_KEY", -- optional: if your endpoint is authenticated
          chat_url = "/v1/chat/completions", -- optional: default value, override if different
        },
      })
    end,
  },
})
```

**Using Azure OpenAI**

To use Azure OpenAI, you need to have an Azure OpenAI service, an API key, and a model deployment. Follow these steps to configure the adapter:

1. Create an Azure OpenAI service in your Azure portal.
2. Deploy a model in the Azure OpenAI service.
3. Obtain the API key from the Azure portal.

Then, configure the adapter in your setup as follows:

```lua
require("codecompanion").setup({
  strategies = {
    chat = {
      adapter = "azure_openai",
    },
    inline = {
      adapter = "azure_openai",
    },
  },
  adapters = {
    azure_openai = function()
      return require("codecompanion.adapters").extend("azure_openai", {
        env = {
          api_key = 'YOUR_AZURE_OPENAI_API_KEY',
          endpoint = 'YOUR_AZURE_OPENAI_ENDPOINT',
        },
        schema = {
          model = "YOUR_DEPLOYMENT_NAME",
        },
      })
    end,
  },
})
```

**Connecting via a Proxy**

You can also connect via a proxy:

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

A common ask is to change an adapter's default model. This can be done by altering the `schema.model.default` table:

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
        name = "llama3", -- Give this adapter a different name to differentiate it from the default ollama adapter
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

**Set a Global Adapter with a Global Variable**

In some cases, it may be helpful to set a global adapter across both the `chat` and `inline` strategies, on the fly. Perhaps, if your LLM of choice is down or you're without internet. This can be achieved by setting the `vim.g.codecompanion_adapter` variable to the name of an adapter in the config. This also prevents you from having to go into every chat buffer that you have open to manually set the adapter.

## :bulb: Advanced Usage

### :clipboard: Prompt Library

The plugin comes with a number of pre-built prompts. As per [the config](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua), these can be called via keymaps or via the cmdline. These prompts have been carefully curated to mimic those in [GitHub's Copilot Chat](https://docs.github.com/en/copilot/using-github-copilot/asking-github-copilot-questions-in-your-ide). Of course, you can create your own prompts and add them to the Action Palette or even to the slash command completion menu in the chat buffer. Please see the [RECIPES](doc/RECIPES.md) guide for more information.

**Using Keymaps**

You can call a prompt from the library via a keymap using the `prompt` helper:

```lua
vim.api.nvim_set_keymap("v", "<LocalLeader>ce", "", {
  callback = function()
    require("codecompanion").prompt("explain")
  end,
  noremap = true,
  silent = true,
})
```

In the example above, we've set a visual keymap that will trigger the Explain prompt. Providing the `short_name` of the prompt as an argument to the helper (e.g. "commit") will resolve the strategy down to an action.

### :speech_balloon: The Chat Buffer

The chat buffer is where you converse with an LLM from within Neovim. The chat buffer has been designed to be turn based, whereby you send a message and the LLM replies. Messages are segmented by H2 headers and once a message has been sent, it cannot be edited. You can also have multiple chat buffers open at the same.

The look and feel of the chat buffer can be customised as per the `display.chat` table in the [config](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua). You can also add additional _Variables_ and _Slash Commands_ which can then be referenced in the chat buffer.

**Keymaps**

When in the chat buffer, press `?` to bring up a menu that lists the available keymaps, variables, slash commands and tools. Currently, the keymaps available to you in normal mode are:

- `<CR>|<C-s>` to send a message to the LLM
- `<C-c>` to close the chat buffer
- `q` to stop the current request
- `ga` to change the adapter for the currentchat
- `gc` to insert a codeblock in the chat buffer
- `gd` to view/debug the chat buffer's contents
- `gf` to fold any codeblocks in the chat buffer
- `gr` to regenerate the last response
- `gs` to toggle the system prompt on/off
- `gx` to clear the chat buffer's contents
- `gy` to yank the last codeblock in the chat buffer
- `[[` to move to the previous header
- `]]` to move to the next header
- `{` to move to the previous chat
- `}` to move to the next chat

> [!NOTE]
> There are also corresponding insert mode mappings available.

**Settings**

You can display your selected adapter's schema at the top of the buffer, if `display.chat.show_settings` is set to `true`. This allows you to vary the response from the LLM.

**Slash Commands**

As outlined in the [Quickstart](#rocket-quickstart) section, Slash Commands allow you to easily share additional context with your LLM from the chat buffer. Some of the commands also allow for multiple providers:

- `/buffer` - Has `default`, `telescope` and `fzf_lua` providers
- `/files` - Has `default`, `telescope`, `mini_pick` and `fzf_lua` providers

Please refer to [the config](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua) to see how to change the default provider.

### :pencil2: Inline Assistant

> [!NOTE]
> If you've set `opts.send_code = false` in your config then the plugin will endeavour to ensure no code is sent to the LLM.

One of the challenges with inline editing is determining how the LLM's response should be handled in the buffer. If you've prompted the LLM to _"create a table of 5 common text editors"_ then you may wish for the response to be placed at the cursor's position in the current buffer. However, if you asked the LLM to _"refactor this function"_ then you'd expect the response to _replace_ a visual selection. The plugin will use the inline LLM you've specified in your config to determine if the response should...

- _replace_ - replace a visual selection you've made
- _add_ - be added in the current buffer at the cursor position
- _new_ - be placed in a new buffer
- _chat_ - be placed in a chat buffer

By default, an inline assistant prompt will trigger the diff feature, showing differences between the original buffer and the changes from the LLM. This can be turned off in your config via the `display.diff.provider` table. You can also choose to accept or reject the LLM's suggestions with the following keymaps:

- `ga` - Accept an inline edit
- `gr` - Reject an inline edit

### :robot: Agents / Tools

As outlined by Andrew Ng in [Agentic Design Patterns Part 3, Tool Use](https://www.deeplearning.ai/the-batch/agentic-design-patterns-part-3-tool-use), LLMs can act as agents by leveraging external tools. Andrew notes some common examples such as web searching or code execution that have obvious benefits when using LLMs.

In the plugin, tools are simply context that's given to an LLM via a `system` prompt and Agents are groupings of tools. These give LLM's knowledge and a defined schema which can be included in the response for the plugin to parse, execute and feedback on. Agents and tools can be added as a participant to the chat buffer by using the `@` key.

More information on how agents and tools work and how you can create your own can be found in the [TOOLS](doc/TOOLS.md) guide.

### :world_map: Agentic Workflows

Agentic Workflows prompt an LLM multiple times, giving them the ability to build their answer step-by-step instead of at once. This leads to much better output as [outlined](https://www.deeplearning.ai/the-batch/issue-242/) by Andrew Ng. Infact, it's possible for older models like GPT 3.5 to outperform newer models (using traditional zero-shot inference).

Implementing Andrew's advice, at various stages of a pre-defined workflow, the plugin will automatically prompt the LLM without any input or triggering required from the user. The plugin contains a default `Code workflow`, as part of the prompt library, which guides the LLM into writing better code.

Of course you can add new workflows by following the [RECIPES](doc/RECIPES.md) guide.

## :lollipop: Extras

**Highlight Groups**

The plugin sets the following highlight groups during setup:

- `CodeCompanionChatHeader` - The headers in the chat buffer
- `CodeCompanionChatSeparator` - Separator between headings in the chat buffer
- `CodeCompanionChatTokens` - Virtual text in the chat buffer showing the token count
- `CodeCompanionChatAgent` - Agents in the chat buffer
- `CodeCompanionChatTool` - Tools in the chat buffer
- `CodeCompanionChatVariable` - Variables in the chat buffer
- `CodeCompanionVirtualText` - All other virtual text in the plugin

**Events/Hooks**

The plugin fires many events during its lifecycle:

- `CodeCompanionChatClosed` - Fired after a chat has been closed
- `CodeCompanionChatAdapter` - Fired after the adapter has been set in the chat
- `CodeCompanionChatModel` - Fired after the model has been set in the chat
- `CodeCompanionToolAdded` - Fired when a tool has been added to a chat
- `CodeCompanionAgentStarted` - Fired when an agent has been initiated in the chat
- `CodeCompanionAgentFinished` - Fired when an agent has finished all tool executions
- `CodeCompanionInlineStarted` - Fired at the start of the Inline strategy
- `CodeCompanionInlineFinished` - Fired at the end of the Inline strategy
- `CodeCompanionRequestStarted` - Fired at the start of any API request
- `CodeCompanionRequestFinished` - Fired at the end of any API request
- `CodeCompanionDiffAttached` - Fired when in Diff mode
- `CodeCompanionDiffDetached` - Fired when exiting Diff mode

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

**Mini.Diff**

If you're using [mini.diff](https://github.com/echasnovski/mini.diff) you can put an icon in the statusline to indicate which diff is currently in use in a buffer:

```lua
local function diff_source()
  local bufnr, diff_source, icon
  bufnr = vim.api.nvim_get_current_buf()
  diff_source = vim.b[bufnr].diffCompGit
  if not diff_source then
    return ""
  end
  if diff_source == "git" then
    icon = "󰊤 "
  elseif diff_source == "codecompanion" then
    icon = " "
  end
  return string.format("%%#StatusLineLSP#%s", icon)
end
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

**Try with a `minimal.lua` file**

A large proportion of issues which are raised in Neovim plugins are to do with a user's own config. That's why I always ask users to fill in a `minimal.lua` file when they raise an issue. We can rule out their config being an issue and it allows me to recreate the problem.

For this purpose, I have included a [minimal.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/minimal.lua) file in the repository for you to test out if you're facing issues. Simply copy the file, edit it and run neovim with `nvim --clean -u minimal.lua`.

<!-- panvimdoc-ignore-start -->

## :gift: Contributing

I am open to contributions but they will be implemented at my discretion. Feel free to open up a discussion before embarking on a PR and please read the [CONTRIBUTING.md](CONTRIBUTING.md) guide.

## :clap: Acknowledgements

- [Steven Arcangeli](https://github.com/stevearc) for his genius creation of the chat buffer and his feedback early on
- [Manoel Campos](https://github.com/manoelcampos) for the [xml2lua](https://github.com/manoelcampos/xml2lua) library that's used in the tools implementation
- [Dante.nvim](https://github.com/S1M0N38/dante.nvim) for the beautifully simple diff implementation
- [Wtf.nvim](https://github.com/piersolenski/wtf.nvim) for the LSP assistant action
- [CopilotChat.nvim](https://github.com/CopilotC-Nvim/CopilotChat.nvim) for the rendering and usability of the chat
buffer
- [Aerial.nvim](https://github.com/stevearc/aerial.nvim) for the Tree-sitter parsing which inspired the symbols Slash
Command

<!-- panvimdoc-ignore-end -->
