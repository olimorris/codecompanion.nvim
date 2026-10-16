# Contributing to CodeCompanion.nvim

Thank you for considering contributing to CodeCompanion.nvim! This document covers what to contribute and how to get set up. The [style guide](STYLE.md) covers how to write it.

## Before Contributing

Before opening a PR, please open a [discussion](https://github.com/olimorris/codecompanion.nvim/discussions) to talk about it. I welcome contributions that improve the plugin, but I want to avoid features that add little value and a lot of code to maintain.

The plugin follows semantic versioning. Any PR which breaks the existing API is unlikely to be merged.

### CodeCompanion is Omakase

In Japanese cuisine, omakase means _"I'll leave it up to you"_ - the diner allows the chef to carefully select each course. CodeCompanion follows this philosophy: carefully curated features, rather than an all-you-can-eat buffet of every possible feature. In the world of LLMs, this means that CodeCompanion will never be at the bleeding edge. However, what it sacrifices in novelty, it makes up for in stability, reliability, and a great user experience.

- **Intentional over exhaustive** - Each new feature is considered against the whole menu rather than just the course itself
- **Complementary** - New features complement the dish rather than acting like an unnecessary side
- **Maintainable** - Every addition is code that I commit to maintaining indefinitely

### Using AI

You're welcome to use coding agents such as CodeCompanion, Claude Code or Codex to contribute. [AGENTS.md](AGENTS.md) and [STYLE.md](STYLE.md) give your agent the architecture, commands and conventions it needs, so point it at them before it writes any code.

Every PR is held to the same standard, however it was written:

- **It follows the [style guide](STYLE.md)** - this is the contract for comments, naming, function signatures and tests, and it's what the automated reviewer checks against
- **It fits the codebase** - it follows existing architectural patterns and reads like the code around it
- **It tests the change** - the tests exercise the behaviour that changed, including the edge cases
- **You own it** - you can explain every line and respond to review feedback yourself

PRs that don't meet this bar will be closed. The most common reasons are verbose comments, overly defensive code, invented naming schemes, changes outside the scope of the PR, and tests that look comprehensive but never hit the edge case.

## How to Contribute

1. Open a [discussion](https://github.com/olimorris/codecompanion.nvim/discussions) to propose your idea
2. Fork the repository and create your branch from `main`
3. Add your feature or fix, with tests
4. Run `make all` to format the code, generate the docs and run the tests
5. Open a PR with a clear title and description, filling in the PR template

The [Architecture](AGENTS.md#architecture) section of `AGENTS.md` is the quickest way to find your way around `lua/codecompanion/`.

## Development Environment

### Prerequisites

- Neovim 0.12+
- [tree-sitter](https://github.com/tree-sitter/tree-sitter) for testing
- [stylua](https://github.com/JohnnyMorganz/StyLua) for Lua formatting
- [pandoc](https://pandoc.org) for doc generation

### Setting Up for Development

Clone your fork and point your plugin manager at it. With lazy.nvim:

```lua
{
  dir = "/full/path/to/local/codecompanion.nvim",
  dev = true,
  dependencies = {
    { "nvim-lua/plenary.nvim" },
  },
  opts = {
    opts = {
      log_level = "DEBUG",
    },
  },
}
```

### Using the included Dockerfile

The Dockerfile creates a container where you can run the `make` tools, including the tests:

```bash
docker build -t codecompanion.nvim .
docker run --rm -ti -u $(id -u):$(id -g) -v "$(pwd)":/cc -w /cc codecompanion.nvim:latest make deps test
```

## Debugging

### Logging

Set `opts.log_level` to `DEBUG` or `TRACE` in your config. Run `:checkhealth codecompanion` to find the log file.

### Debug Chat

Press `gd` in the chat buffer to open a debug window. This shows the message history alongside the adapter settings.

### Debug Requests with Proxy

To inspect the requests and responses sent to an LLM provider, forward them through a proxy such as [mitmproxy](https://mitmproxy.org/):

1. Follow the [mitmproxy installation guide](https://docs.mitmproxy.org/stable/overview-installation/)
2. Start mitmproxy with the web interface on port 4141: `mitmweb --set listen_port=4141`
3. Configure CodeCompanion to use the proxy:

```lua
require("codecompanion").setup({
  adapters = {
    opts = {
      allow_insecure = true,
      proxy = "http://127.0.0.1:4141",
    },
  },
})
```

<details>
<summary>screenshot</summary>
<img width="1506" alt="debug request with proxy screenshot" src="https://github.com/user-attachments/assets/60f31736-da83-4b80-bc61-341bb7fc82f7" />
</details>

## Testing

CodeCompanion uses [Mini.Test](https://github.com/nvim-mini/mini.nvim/blob/main/TESTING.md). There are c. 800 tests and they act as a second source of documentation, so read the existing tests for the area you're changing before writing your own.

```bash
make test
make test_file FILE=tests/adapters/test_openai.lua
```

### Running tests on Windows

> [!NOTE]
> This guide is for native Windows, not POSIX emulation environments such as WSL, MSYS2 or Cygwin.

Ensure the following:

- `git` is in `%PATH%`
- Some `make` is in `%PATH%`
- Some C/C++ compiler is in path for Tree-sitter to get bootstrapped
- Define the `%HOME%` environment variable to `%HOMEDRIVE%%HOMEPATH%` or `%USERPROFILE%`
- Create the directory `deps` in the CodeCompanion root, if it doesn't exist

For _make_ and a compiler, running _x64 Native Tools Command Prompt_ from _Visual Studio Community 2022_ provides _NMake_ and the _Visual C++_ compiler, which work fine for this purpose.

From cmd.exe:

```winbatch
REM setup environment
IF NOT EXIST deps MD deps
SET "HOME=%HOMEDRIVE%%HOMEPATH%"
SET "PATH=%PATH%;C:\Program Files\Git\bin"
"C:\Program Files (x86)\Microsoft Visual Studio\2022\VC\Auxiliary\Build\vcvars64.bat"

REM run all tests
nmake test

REM run a single test file
nmake FILE=tests/adapters/test_openai.lua test_file
```

> [!NOTE]
> You can also use the `Make.ps1` PowerShell script to run the same commands as `make` (format/docs/test/test_file), or run `Make.ps1` alone to execute `all`. Use forward slashes in your `test_file` args, as backslashes break Mini.Test.

## Building Documentation

Documentation is built with [panvimdoc](https://github.com/kdheepak/panvimdoc). Run `make docs` after changing any page in `doc/`.
