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
require("codecompanion").setup({
  extensions = {
    vectorcode = {
      opts = {
        add_tools = { "ls", "query" },
      }
    }
  }
})
```

The `add_tools` array should contain VectorCode tools that you want the LLM to have access to.

- The `ls` tool (named `@vectorcode_ls` in the chat buffer) returns all projects indexed by VectorCode;
- The `query` tool (named `@vectorcode_query` in the chat buffer) allows the LLM to search for related files in a particular
  project.

For further configuration options, see the [VectorCode wiki](https://github.com/Davidyz/VectorCode/wiki/Neovim-Integrations).

## Usage

To grant the LLM access to your indexed codebases, simply mention the corresponding tool(s) in the chat buffer. 
The LLM can then query any projects indexed by VectorCode to retrieve relevant context for your prompts.

**Example: Using VectorCode to Explore the VectorCode Repository**

![](https://github.com/Davidyz/VectorCode/blob/main/images/codecompanion_chat.png?raw=true)

## Additional Resources

- [VectorCode GitHub repository](https://github.com/Davidyz/VectorCode).
- [VectorCode wiki](https://github.com/Davidyz/VectorCode/wiki).
- [VectorCode discussion forum](https://github.com/Davidyz/VectorCode/discussions).
