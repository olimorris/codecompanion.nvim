# Contributing to CodeCompanion.nvim

Thank you for considering contributing to CodeCompanion.nvim! This document provides guidelines and information to help you get started with contributing to the project.

## Before Contributing

Before contributing a PR, please open up a discussion to talk about it. While I welcome contributions that improve the plugin, I want to refrain from adding features that add little value and a lot of bloat as the plugin is already quite large (approximately 9,000 LOC).

The plugin has adopted semantic versioning. As such, any PR which breaks the existing API is unlikely to be merged.

## How to Contribute

1. Open up a [discussion](https://github.com/olimorris/codecompanion.nvim/discussions) to propose your idea.
2. Fork the repository and create your branch from `main`.
3. Add your feature or fix to your branch.
4. Ensure your code follows the project's coding style and conventions.
5. Make sure your code has adequate test coverage and is well-documented.
6. Open a pull request (PR) with a clear title and description.

## Tips for Contributing

The best way to contribute to CodeCompanion is to use CodeCompanion to help you add a feature or squash a bug. Below are some useful tips to enable you to get started as quickly as possible.

### Read the Docs

They're located [here](https://codecompanion.olimorris.dev) and are regularly updated.

### Use Workspaces

CodeCompanion makes use of [workspaces](https://codecompanion.olimorris.dev/usage/chat-buffer/slash-commands.html#workspace), which allow groups of files and context, to be shared with an LLM more easily:

<img src="https://github.com/user-attachments/assets/a04e9b2d-bfc6-4f03-84fe-77c0f5cb92f2">

This allows the LLM to understand exactly what CodeCompanion does and how it functions. Multiple workspaces can be loaded into a chat buffer as well.

### Use VectorCode

[VectorCode](https://github.com/Davidyz/VectorCode/tree/main) is a repository indexing tool and makes it very easy to intelligently share relevant parts of a codebase with an LLM. Follow the installation instructions [here](https://codecompanion.olimorris.dev/extensions/vectorcode.html#installation) including how to add it as a CodeCompanion extension.

Once installed, you can begin to index the CodeCompanion repository that you've cloned. Simply run `vectorcode vectorise -r` and you should see output similar to:

![Image](https://github.com/user-attachments/assets/9fb7ef65-3a3f-4e56-9d75-f4e2e1f71aea)

You can then proceed to using VectorCode as per the [usage](https://codecompanion.olimorris.dev/extensions/vectorcode.html#usage) instructions in the chat buffer.

### Refer to the Tests

CodeCompanion has [c. 200 tests](https://github.com/olimorris/codecompanion.nvim/tree/main/tests) that have been carefully crafted to give great test coverage and to act as a second source of documentation. The [testing](#testing) section has more on how you can create your own tests.

## Project Structure

CodeCompanion.nvim is organized into several key directories:

- `lua/codecompanion/`:
  - `adapters/`: Adapters for different LLM providers (OpenAI, Anthropic, etc.)
  - `strategies/`:
    - `chat/`: Chat buffer implementation
    - `inline/`: Inline code editing functionality
    - `cmd/`: Command-line editing
  - `providers/`: Integration of providers (e.g. Snacks.nvim, Telescope.nvim)
  - `utils/`: Utility functions
- `doc/`: The documentation for the CodeCompanion site and vim docs
- `queries/`: Tree-sitter queries for various languages
- `tests/`: Various tests for the plugin

## Development Environment

### Prerequisites

- Neovim 0.10.0+
- [lua-language-server](https://github.com/LuaLS/lua-language-server) for LSP support and type annotations
- [stylua](https://github.com/JohnnyMorganz/StyLua) for Lua formatting
- [pandoc](https://pandoc.org) for doc generation

### Setting Up for Development

> This section explain how to setup the environment for development using lazy.nvim package manager. However you can use the package manager of your choice.

1. Clone your fork of the repository.
2. Define CodeCompanion configuration pointing to your local repository:

```lua
{
  dir = "/full/path/to/local/codecompanion.nvim",
  dev = true,
  dependencies = {
    { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
    { "nvim-lua/plenary.nvim" },
    -- Include any optional dependencies needed for your development
  },
  opts = {
    opts = {
      log_level = "DEBUG", -- For development
    },
    -- The rest of your configuration
  }
}
```

## Debugging and Logging

### Logging

CodeCompanion uses a hierarchical logging system that writes to a log file. You can configure the log level in your setup:

```lua
require("codecompanion").setup({
  opts = {
    log_level = "DEBUG", -- Options: ERROR, WARN, INFO, DEBUG, TRACE
  }
})
```

Log files are stored in Neovim's log directory, which can be found by running `:checkhealth codecompanion`.

### Debug Chat

When developing, you can debug the message history in the chat buffer by pressing `gd` to open a debug window. This shows the current messages (from yourself and the LLM) alongside any adapter settings.

### Debug Requests with Proxy

If you need to debug requests and responses sent to LLM providers, you can use the `proxy` option to forward requests to a proxy server.

A simple proxy server can be set up using [mitmproxy](https://mitmproxy.org/).

1. Follow the [mitmproxy installation guide](https://docs.mitmproxy.org/stable/overview-installation/) to install mitmproxy.
2. Start mitmproxy with the web interface and listen on port 4141: `mitmweb --set listen_port=4141`
3. Configure CodeCompanion to use the proxy server:

```lua
{
  dir = "/full/path/to/local/codecompanion.nvim",
  -- The rest of your configuration ...
  opts = {
    adapters = {
      opts = {
        allow_insecure = true,
        proxy = "http://127.0.0.1:4141",
      },
    }
    -- The rest of your configuration ...
  }
}
```

From now on, all requests will be forwarded to the proxy server.
<details>
<summary>screenshot</summary>
<img width="1506" alt="debug request with proxy screenshot" src="https://github.com/user-attachments/assets/60f31736-da83-4b80-bc61-341bb7fc82f7" />
</details>

With mitmproxy you can much more using custom scripts/hooks like simulating slower connections, patch requests, etc. Check out the [documentation](https://docs.mitmproxy.org/stable/addons-overview/) for more information.


## Testing

CodeCompanion uses the awesome [Mini.Test](https://github.com/echasnovski/mini.nvim/blob/main/TESTING.md) for all its tests. To run the full suite of tests, call:

```bash
make test
```

or to run a specific test file:

```bash
FILE=tests/adapters/test_openai.lua make test_file
```

When adding new features, please include tests in the appropriate test file under the `tests/` directory.

### Testing Tips

Trying to understand the CodeCompanion codebase and then having to learn how to create tests can feel onerous. So to make this process easier, it's recommended to load the `test` workspace into your chat buffer to give your LLM knowledge of how Mini.Test works.

It can also be useful to share an example [test file](https://github.com/olimorris/codecompanion.nvim/blob/main/tests/adapters/test_openai.lua) with an LLM too.

## Code Style and Conventions

- Use [stylua](https://github.com/JohnnyMorganz/StyLua) for formatting Lua code
- Configuration is in `stylua.toml`
- Run `make format` to format the code before submitting a PR
- Type annotations are encouraged (see `lua/codecompanion/types.lua`) and [LuaCATS site](https://luals.github.io/wiki/annotations/)

## Building Documentation

Documentation is built using [panvimdoc](https://github.com/kdheepak/panvimdoc):

```bash
make docs
```
