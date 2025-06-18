# VectorCode

> Last updated for VectorCode 0.7

[VectorCode](https://github.com/Davidyz/VectorCode) is a code repository indexing tool enabling semantic search across your local projects. This extension integrates VectorCode with CodeCompanion, allowing LLMs to query your indexed repositories for enhanced context during chat sessions.

## Features

- Provides the `@vectorcode` tool for use in the chat buffer.
- Enables LLMs to perform semantic searches across multiple indexed local code repositories.
- Supplies relevant code snippets from your projects as context to the LLM.

## Prerequisites

> [!NOTE]
> VectorCode requires initial setup outside of CodeCompanion. You must install the Python backend and index your project files using the VectorCode CLI.

Please refer to the [VectorCode CLI documentation](https://github.com/Davidyz/VectorCode/blob/main/docs/cli.md) for detailed setup instructions.

## Installation

First, install the [VectorCode Neovim plugin](https://github.com/Davidyz/VectorCode/blob/main/docs/neovim.md). A minimal installation is sufficient if you only plan to use VectorCode via CodeCompanion:

```lua
{
  "Davidyz/VectorCode",
  -- pin the nvim plugin to the latest release for stability
  version = "*",
  -- keep the CLI up to date so that it supports the features needed by the lua binding
  build = "uv tool install --upgrade vectorcode",
  dependencies = { "nvim-lua/plenary.nvim" },
}
```

Next, register VectorCode as an extension in your CodeCompanion configuration:

```lua
---@module "vectorcode"

require("codecompanion").setup({
  extensions = {
    vectorcode = {
      ---@type VectorCode.CodeCompanion.ExtensionOpts
      opts = {
        tool_group = {
          enabled = true,
          collapse = true,
          -- tools in this array will be included to the `vectorcode_toolbox` tool group
          extras = {}, 
        },
        tool_opts = {
          ---@type VectorCode.CodeCompanion.LsToolOpts
          ls = {},
          ---@type VectorCode.CodeCompanion.QueryToolOpts
          query = {},
          ---@type VectorCode.CodeCompanion.VectoriseToolOpts
          vectorise = {}
        }
      }
    }
  }
})
```

The extension will create the following 3 tools:

- The `ls` tool (named `@vectorcode_ls` in the chat buffer) returns all projects indexed by VectorCode;
- The `query` tool (named `@vectorcode_query` in the chat buffer) allows the LLM to search for related files in a particular
  project;
- The `vectorise` tool (named `@vectorcode_vectorise` in the chat buffer) allows
  the LLM to vectorise files and add them to the database.

For your convenience, a tool group named `@vectorcode_toolbox` will be created.
This is a shortcut that you can use to quickly add all 3 tools mentioned above
into the chat.

For further configuration options, see the [VectorCode wiki](https://github.com/Davidyz/VectorCode/wiki/Neovim-Integrations#olimorriscodecompanionnvim).

## Usage

To grant the LLM access to your indexed codebases, simply mention the corresponding tool(s) in the chat buffer. 
The LLM can then query any projects indexed by VectorCode to retrieve relevant context for your prompts.

**Example: Using VectorCode to Interact with a Code Repository in a CodeCompanion Chat Buffer**

![](https://github.com/Davidyz/VectorCode/blob/main/images/codecompanion_chat.png?raw=true)

## Additional Resources

- [VectorCode GitHub repository](https://github.com/Davidyz/VectorCode).
- [VectorCode wiki](https://github.com/Davidyz/VectorCode/wiki).
- [VectorCode discussion forum](https://github.com/Davidyz/VectorCode/discussions).
