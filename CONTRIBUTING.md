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

## Project Structure

CodeCompanion.nvim is organized into several key directories:

- `lua/codecompanion/`: Main plugin code
  - `adapters/`: LLM adapters for different providers (OpenAI, Anthropic, etc.)
  - `strategies/`: Core functionality components
    - `chat/`: Chat buffer implementation
    - `inline/`: Inline code editing functionality
    - `cmd/`: Command-line interaction
  - `providers/`: Utility providers for various functionalities
  - `utils/`: Shared utility functions
- `tests/`: Tests organized by component
- `doc/`: Documentation files
- `queries/`: TreeSitter queries for various languages

## Development Environment

### Prerequisites

- Neovim 0.10.0+
- [lua-language-server](https://github.com/LuaLS/lua-language-server) for LSP support and type annotations
- [stylua](https://github.com/JohnnyMorganz/StyLua) for Lua formatting

### Setting Up for Development

> This section explain how to setup the environment for development using lazy.nvim package manager. However you can use the package manager of your choice.

1. Clone your fork of the repository.
2. Define codecompanion configuration pointing to your local repository:

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

### Debug Functions

When developing, you can use the built-in debug functions:

- In chat buffers, press `gd` to open a debug window showing current messages and settings
- Run `:checkhealth codecompanion` to verify your environment is set up correctly

### Debug Requests with Proxy

If you need to debug requests and responses sent to LLM providers, you can use the `proxy` option to forward requests to a proxy server.

A simple proxy server can be set up using [mitmproxy](https://mitmproxy.org/).

1. Follow the [mitmproxy installation guide](https://docs.mitmproxy.org/stable/overview-installation/) to install mitmproxy.
2. Start mitmproxy with the web interface and listen on port 4141: `mitmweb --set listen_port=4141`
3. Configure codecompanion to use the proxy server:

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

CodeCompanion uses [Mini.Test](https://github.com/echasnovski/mini.nvim/tree/main/lua/mini/test) for testing. To run the tests:

```bash
make test           # Run all tests
make test_file FILE=path/to/test_file.lua  # Run a specific test file
```

When adding new features, please include tests in the appropriate test file under the `tests/` directory.

## Code Style and Conventions

- Use [stylua](https://github.com/JohnnyMorganz/StyLua) for formatting Lua code
- Configuration is in `stylua.toml`
- Run `make format` to format the code before submitting a PR
- Type annotations are encouraged (see `lua/codecompanion/types.lua`) and [LuaCATS site](https://luals.github.io/wiki/annotations/)

## Building Documentation

Documentation is built using [panvimdoc](https://github.com/kdheepak/panvimdoc):

```bash
make docs  # Generate plugin documentation
```

## Contribution Guidelines

- **Feature Requests**: Please suggest new features, but note that only features that align with the maintainer's workflow may be accepted.
- **Bug Fixes**: When submitting a PR for a bug, ensure you've first raised an issue that can be recreated.
- **Responsibility**: If you add a feature, you are responsible for maintaining and bug fixing that feature going forward. The maintainers may provide guidance and support, but ultimate responsibility lies with the contributor.
- **Code Quality**: Strive to maintain high code quality with proper tests.
- **Communication**: If you have questions, open an issue or reach out to the maintainers.

## Common Issues and Troubleshooting

When facing issues during development, try these steps:

1. Check logs at the path shown by `:checkhealth codecompanion`
2. Enable DEBUG or TRACE log level
3. Test with a minimal configuration (see `minimal.lua` in the repository)
4. Ensure all dependencies are properly installed

## Pull Request Process

1. Update documentation if you're changing behavior or adding features
2. Update tests to cover your changes
3. Format your code with `make format`
4. Reference any related issues in your PR description
5. The PR should be based on a prior discussion unless it's a straightforward bug fix

Thank you for contributing to CodeCompanion.nvim!
