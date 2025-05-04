# VectorCode

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
  version = "*", -- optional, depending on whether you're on nightly or release
  build = "pipx upgrade vectorcode", -- optional but recommended. This keeps your CLI up-to-date.
  dependencies = { "nvim-lua/plenary.nvim" },
}
```

Next, register VectorCode as an extension in your CodeCompanion configuration:

```lua
require("codecompanion").setup({
  extensions = {
    vectorcode = {
      opts = {
        add_tool = true,
      }
    }
  }
})
```

With `add_tool = true`, the `@vectorcode` tool becomes available in the CodeCompanion chat buffer. For further configuration options, see the [VectorCode wiki](https://github.com/Davidyz/VectorCode/wiki/Neovim-Integrations).

## Usage

To grant the LLM access to your indexed codebases, simply mention the `@vectorcode` tool in the chat buffer. The LLM can then query any projects indexed by VectorCode (verifiable via `vectorcode ls` in your terminal) to retrieve relevant context for your prompts.

**Example: Using VectorCode to Explore the VectorCode Repository**

![](https://github.com/Davidyz/VectorCode/blob/main/images/codecompanion_chat.png?raw=true)

## Additional Resources

- [VectorCode GitHub repository](https://github.com/Davidyz/VectorCode).
- [VectorCode wiki](https://github.com/Davidyz/VectorCode/wiki).
- [VectorCode discussion forum](https://github.com/Davidyz/VectorCode/discussions).
