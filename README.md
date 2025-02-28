<!-- panvimdoc-ignore-start -->

<p align="center">
<img src="https://raw.githubusercontent.com/olimorris/codecompanion.nvim/refs/heads/main/doc/media/logo.png" alt="CodeCompanion.nvim" />
</p>

<p align="center">
<a href="https://github.com/olimorris/codecompanion.nvim/stargazers"><img src="https://img.shields.io/github/stars/olimorris/codecompanion.nvim?color=c678dd&logoColor=e06c75&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/olimorris/codecompanion.nvim/ci.yml?branch=main&label=tests&style=for-the-badge"></a>
<a href="https://github.com/olimorris/codecompanion.nvim/releases"><img src="https://img.shields.io/github/v/release/olimorris/codecompanion.nvim?style=for-the-badge"></a>
</p>

<p align="center">AI-powered coding, seamlessly in Neovim</p>

<p align="center">Connect to any LLM with the <a href="https://codecompanion.olimorris.dev/getting-started.html">in-built</a> adapters, the <a href="https://codecompanion.olimorris.dev/configuration/adapters.html#user-contributed-adapters">community</a> adapters or by <a href="https://codecompanion.olimorris.dev/extending/adapters.html">building</a> your own</p>

<p align="center">New features are always announced <a href="https://github.com/olimorris/codecompanion.nvim/discussions/categories/announcements">here</a></p>

## :purple_heart: Sponsors

Thank you to the following people:

<p align="center">
<!-- coffee --><a href="https://github.com/bassamsdata"><img src="https://github.com/bassamsdata.png" width="60px" alt="Bassam Data" /></a><a href="https://github.com/ivo-toby"><img src="https://github.com/ivo-toby.png" width="60px" alt="Ivo Toby" /></a><a href="https://github.com/KTSCode"><img src="https://github.com/KTSCode.png" width="60px" alt="KTS Code" /></a><a href="https://x.com/luxus"><img src="https://pbs.twimg.com/profile_images/744754093495844864/GwnEJygG_400x400.jpg" width="60px" alt="Luxus" /></a><!-- coffee --><!-- sponsors --><a href="https://github.com/koskeller"><img src="https:&#x2F;&#x2F;github.com&#x2F;koskeller.png" width="60px" alt="User avatar: Konstantin Keller" /></a><a href="https://github.com/carlosflorencio"><img src="https:&#x2F;&#x2F;github.com&#x2F;carlosflorencio.png" width="60px" alt="User avatar: Carlos Florêncio" /></a><a href="https://github.com/jfgordon2"><img src="https:&#x2F;&#x2F;github.com&#x2F;jfgordon2.png" width="60px" alt="User avatar: Jeff Gordon" /></a><a href="https://github.com/rnevius"><img src="https:&#x2F;&#x2F;github.com&#x2F;rnevius.png" width="60px" alt="User avatar: Ryan Nevius" /></a><a href="https://github.com/versality"><img src="https:&#x2F;&#x2F;github.com&#x2F;versality.png" width="60px" alt="User avatar: Artyom Pertsovsky" /></a><a href="https://github.com/llinfeng"><img src="https:&#x2F;&#x2F;github.com&#x2F;llinfeng.png" width="60px" alt="User avatar: Linfeng Li" /></a><a href="https://github.com/Jawkx"><img src="https:&#x2F;&#x2F;github.com&#x2F;Jawkx.png" width="60px" alt="User avatar: JAW" /></a><a href="https://github.com/prettymuchbryce"><img src="https:&#x2F;&#x2F;github.com&#x2F;prettymuchbryce.png" width="60px" alt="User avatar: Bryce Neal" /></a><a href="https://github.com/brenocq"><img src="https:&#x2F;&#x2F;github.com&#x2F;brenocq.png" width="60px" alt="User avatar: Breno Cunha Queiroz" /></a><!-- sponsors -->
</p>

<!-- panvimdoc-ignore-end -->

## :sparkles: Features

- :speech_balloon: [Copilot Chat](https://github.com/features/copilot) meets [Zed AI](https://zed.dev/blog/zed-ai), in Neovim
- :electric_plug: Support for Anthropic, Copilot, GitHub Models, DeepSeek, Gemini, Ollama, OpenAI, Azure OpenAI, HuggingFace and xAI LLMs (or [bring your own](https://codecompanion.olimorris.dev/extending/adapters.html))
- :heart_hands: User contributed and supported [adapters](https://codecompanion.olimorris.dev/configuration/adapters.html#user-contributed-adapters)
- :rocket: Inline transformations, code creation and refactoring
- :robot: Variables, Slash Commands, Agents/Tools and Workflows to improve LLM output
- :sparkles: Built in prompt library for common tasks like advice on LSP errors and code explanations
- :building_construction: Create your own custom prompts, Variables and Slash Commands
- :books: Have multiple chats open at the same time
- :muscle: Async execution for fast performance

<!-- panvimdoc-ignore-start -->

## :camera_flash: In Action

<div align="center">
  <p>
    <h3>The Chat Buffer</h3>
    <video controls muted src="https://github.com/user-attachments/assets/aa109f1d-0ec9-4f08-bd9a-df99da03b9a4"></video>
  </p>
  <p>
    <h3>Using Agents and Tools</h3>
    <video controls muted src="https://github.com/user-attachments/assets/16bd6c17-bd70-41a1-83aa-7af45c166ae9"></video>
  </p>
  <p>
    <h3>Agentic Workflows</h3>
    <video controls muted src="https://github.com/user-attachments/assets/31bae248-ae70-4395-9df1-67fc252475ca"></video>
  </p>
  <p>
    <h3>Inline Assistant</h3>
    <video controls muted src="https://github.com/user-attachments/assets/dcddcb85-cba0-4017-9723-6e6b7f080fee"></video>
  </p>
</div>

<!-- panvimdoc-ignore-end -->

## :rocket: Getting Started

Please visit the [docs](https://codecompanion.olimorris.dev) for information on installation, configuration and usage.

## :toolbox: Troubleshooting

Before raising an [issue](https://github.com/olimorris/codecompanion.nvim/issues), there are a number of steps you can take to troubleshoot a problem:

**Checkhealth**

Run `:checkhealth codecompanion` and check all dependencies are installed correctly. Also take note of the log file path.

**Turn on logging**

Update your config and turn debug logging on:

```lua
require("codecompanion").setup({
  opts = {
    log_level = "DEBUG", -- or "TRACE"
  }
})
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
- [Saghen](https://github.com/Saghen) for the fantastic docs inspiration from [blink.cmp](https://github.com/Saghen/blink.cmp)

<!-- panvimdoc-ignore-end -->
