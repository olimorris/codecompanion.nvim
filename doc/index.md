---
description: CodeCompanion is a Neovim plugin which streamlines how you write code with LLMs, in Neovim
prev: false
next:
  text: 'Installation'
  link: '/installation'
---

# Welcome to CodeCompanion.nvim

> AI Coding, Vim Style

CodeCompanion is a Neovim plugin which enables you to code with AI, using LLMs and agents, in Neovim.

<p>
<video controls muted src="https://github.com/user-attachments/assets/3cc83544-2690-49b5-8be6-51e671db52ef"></video>
</p>

## Features

- :speech_balloon: [Copilot Chat](https://github.com/features/copilot) meets [Zed AI](https://zed.dev/blog/zed-ai), in Neovim
- :electric_plug: Support for LLMs from Anthropic, Copilot, GitHub Models, DeepSeek, Gemini, Mistral AI, Novita, Ollama, OpenAI, Azure OpenAI, HuggingFace and xAI out of the box (or bring your own!)
- :robot: Support for [Agent Client Protocol](https://agentclientprotocol.com/overview/introduction), enabling coding with agents like [Augment Code](https://docs.augmentcode.com/cli/overview), [Cagent](https://github.com/docker/cagent) from Docker, [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview), [Codex](https://openai.com/codex), [Gemini CLI](https://github.com/google-gemini/gemini-cli), [Goose](https://block.github.io/goose/), [Kimi CLI](https://github.com/MoonshotAI/kimi-cli), [Kiro](https://kiro.dev/cli/), [Mistral Vibe](https://github.com/mistralai/mistral-vibe) and [OpenCode](https://opencode.ai)
- :heart_hands: User contributed and supported [adapters](/configuration/adapters-http#community-adapters)
- :battery: Support for [Model Context Protocol (MCP)](/model-context-protocol)
- :rocket: [Inline transformations](/usage/inline-assistant.html), code creation and refactoring
- :robot: [Editor Context](/usage/chat-buffer/editor-context), [Slash Commands](/usage/chat-buffer/slash-commands), [Tools](/usage/chat-buffer/agents-tools) and [Workflows](/usage/workflows) to improve LLM output
- :brain: Support for [rules](/usage/chat-buffer/rules) files like `CLAUDE.md`, `.cursor/rules` and your own custom ones
- :sparkles: Built-in [prompt library](/usage/action-palette.html) for common tasks like advice on LSP errors and code explanations
- :building_construction: Create your own [custom prompts](configuration/prompt-library#creating-prompts), Editor Context and Slash Commands
- :books: Have [multiple chats](/usage/introduction#quickly-accessing-a-chat-buffer) open at the same time
- :art: Support for [vision and images](/usage/chat-buffer/#images-vision) as input
- :muscle: Async execution for fast performance

## Overview

The plugin utilises objects called _interactions_. These are the different ways that a user can interact with the plugin. The _chat_ interaction harnesses a buffer to allow direct conversation with the LLM. The _inline_ interaction allows for output from the LLM to be written directly into a pre-existing Neovim buffer.

The plugin allows you to specify adapters for each interaction and also for each [prompt library](configuration/prompt-library) entry.

## Supported LLMs and Agents

CodeCompanion uses [HTTP](configuration/adapters-http) and [ACP](configuration/adapters-acp) adapters to connect to LLMs and agents. Out of the box, the plugin supports:

- Anthropic (`anthropic`) - Requires an API key and supports [prompt caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
- Augment Code (`auggie_cli`) - Requires an API key
- Cagent (`cagent`)
- Claude Code (`claude_code`) - Requires an API key or a Claude Pro subscription
- Codex (`codex`) - Requires an API key
- Copilot (`copilot`) - Requires a token which is created via `:Copilot setup` in [Copilot.vim](https://github.com/github/copilot.vim)
- Gemini CLI (`gemini_cli`) - Requires an API key or a Gemini Pro subscription
- GitHub Models (`githubmodels`) - Requires [`gh`](https://github.com/cli/cli) to be installed and logged in
- Goose (`goose`) - Requires an API key
- DeepSeek (`deepseek`) - Requires an API key
- Gemini (`gemini`) - Requires an API key
- HuggingFace (`huggingface`) - Requires an API key
- Kimi CLI (`kimi_cli`) - Requires an API key
- Mistral AI (`mistral`) - Requires an API key or a Le Chat Pro subscription
- Novita (`novita`) - Requires an API key
- Ollama (`ollama`) - Both local and remotely hosted
- OpenAI (`openai`) - Requires an API key
- opencode (`opencode`) - Requires an API key
- xAI (`xai`) - Requires an API key

In order to add a custom adapter, please refer to the [extending adapters](/extending/adapters) documentation. Also, be sure to check out the [community adapters](configuration/adapters-http#community-adapters) section for user contributed adapters.
