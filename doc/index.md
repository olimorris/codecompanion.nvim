---
description: "CodeCompanion.nvim is an AI coding plugin for Neovim. Chat with Claude, GPT-5, and Gemini, run CLI agents like Claude Code and Codex, and edit code inline."
prev: false
next:
  text: 'Installation'
  link: '/installation'
---

# Welcome to CodeCompanion.nvim

> AI Coding, Vim Style

CodeCompanion is a plugin which enables you to code with AI, using LLMs and agents, in Neovim.

<p>
<video controls muted title="CodeCompanion overview demo" src="https://github.com/user-attachments/assets/3cc83544-2690-49b5-8be6-51e671db52ef"></video>
</p>

## Features

- :speech_balloon: [Copilot Chat](https://github.com/features/copilot) meets [Zed AI](https://zed.dev/blog/zed-ai), in Neovim
- :zap: Integrates Neovim with LLMs and Agents in the CLI
- :electric_plug: Support for LLMs from [Anthropic](https://platform.claude.com/docs/en/about-claude/models/overview),  [DeepSeek](https://www.deepseek.com), [Google Gemini](https://ai.google.dev/gemini-api/docs/models), [GitHub Copilot](https://github.com/features/copilot), [GitHub Models](https://docs.github.com/en/github-models), [Kimi](https://platform.kimi.ai), [Mistral](https://mistral.ai/), [Novita](https://novita.ai/), [Ollama](https://ollama.com/), [OpenAI](https://developers.openai.com/api/docs/models), Azure OpenAI, [OpenRouter](https://openrouter.ai/), [HuggingFace](https://huggingface.co/) and [xAI](https://docs.x.ai/developers/models) out of the box (or [bring your own!](/extending/adapters))
- :robot: Support for [Agent Client Protocol](https://agentclientprotocol.com/overview/introduction), enabling coding with agents like [Augment Code](https://docs.augmentcode.com/cli/overview), [Cagent](https://github.com/docker/cagent) from Docker, [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview), [Cline CLI](https://docs.cline.bot/home), [Codex](https://openai.com/codex), [Copilot CLI](https://github.com/features/copilot/cli), [Gemini CLI](https://github.com/google-gemini/gemini-cli), [Goose](https://block.github.io/goose/), [Grok Build](https://github.com/xai-org/grok-build), [Cursor CLI](https://cursor.com/docs/cli/overview), [Kilo Code](https://kilo.ai), [Kimi CLI](https://github.com/MoonshotAI/kimi-cli), [Kiro](https://kiro.dev/cli/), [Mistral Vibe](https://github.com/mistralai/mistral-vibe) and [OpenCode](https://opencode.ai)
- :heart_hands: User contributed and supported [adapters](/configuration/adapters-http#community-adapters)
- :man_technologist: [Code reviews](/usage/code-review) enabling you to comment on and approve/reject agent code
- :battery: Support for [Model Context Protocol (MCP)](/model-context-protocol)
- :rocket: [Inline transformations](/usage/inline), code creation and refactoring
- :robot: [Editor Context](/usage/chat-buffer/editor-context), [Slash Commands](/usage/chat-buffer/slash-commands), [Tools](/usage/chat-buffer/agents-tools) and [Workflows](/usage/workflows) to improve LLM output
- :brain: Support for [rules](/usage/chat-buffer/rules) files like `CLAUDE.md`, `.cursor/rules` and your own custom ones
- :sparkles: Built-in [prompt library](/usage/action-palette) for common tasks like advice on LSP errors and code explanations
- :building_construction: Create your own [custom prompts](configuration/prompt-library#creating-prompts), Editor Context and Slash Commands
- :inbox_tray: Have [multiple chats](/usage/introduction#quickly-accessing-a-chat-buffer) open at the same time
- :art: Support for [images](/usage/chat-buffer/#images-vision) and PDFs as input
- :muscle: Async execution for fast performance

## Overview

CodeCompanion utilises objects called _interactions_. These are the different ways that a user can interact with an LLM. The _chat_ interaction harnesses a buffer to allow direct conversations with LLMs. The _inline_ interaction allows for output from the LLM to be written directly, inline to a pre-existing Neovim buffer.

CodeCompanion uses [adapters](/configuration/adapters-http) to connect Neovim to an LLM or agent, even going as far as specifying [models](/configuration/adapters-http#changing-the-default-model) and/or [hyperparameters](/configuration/adapters-http#changing-adapter-parameters-schema). You can specify adapters for each interaction type and also for each [prompt library](configuration/prompt-library) entry. There are far too many adapters to list so be sure to check out the [adapters folder](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters/http) in the main repository.  You can also roll your own adapters. Refer to the [extending adapters](/extending/adapters) documentation for more information. Finally, be sure to check out the [community adapters](configuration/adapters-http#community-adapters) section for user contributed adapters.
