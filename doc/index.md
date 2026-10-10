---
description: "Code with LLMs and agents in Neovim: chat with Claude, GPT and Gemini, run agents like Claude Code and Codex, and edit code inline."
prev: false
next:
  text: 'Installation'
  link: '/installation'
---

# Welcome to CodeCompanion.nvim

> AI Coding, Vim Style

CodeCompanion lets you code with LLMs and agents in Neovim.

<p>
<video controls muted title="CodeCompanion overview demo" src="https://github.com/user-attachments/assets/3cc83544-2690-49b5-8be6-51e671db52ef"></video>
</p>

## Features

- :speech_balloon: [Copilot Chat](https://github.com/features/copilot) meets [Zed AI](https://zed.dev/blog/zed-ai), in Neovim
- :zap: Run [CLI agents](/usage/cli) like Claude Code and Codex alongside your code
- :electric_plug: LLMs from [Anthropic](https://platform.claude.com/docs/en/about-claude/models/overview), [DeepSeek](https://www.deepseek.com), [Gemini](https://ai.google.dev/gemini-api/docs/models), [GitHub Copilot](https://github.com/features/copilot), [Hugging Face](https://huggingface.co/), [Kimi](https://platform.kimi.ai), [Mistral](https://mistral.ai/), [Novita](https://novita.ai/), [Ollama](https://ollama.com/), [OpenAI](https://developers.openai.com/api/docs/models), Azure OpenAI, [OpenRouter](https://openrouter.ai/) and [xAI](https://docs.x.ai/developers/models) out of the box, or [bring your own](/extending/adapters)
- :robot: Agents over the [Agent Client Protocol](/agent-client-protocol), including [Auggie](https://docs.augmentcode.com/cli/overview), [Cagent](https://github.com/docker/cagent), [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview), [Cline](https://docs.cline.bot/home), [Codex](https://openai.com/codex), [Copilot CLI](https://github.com/features/copilot/cli), [Cursor CLI](https://cursor.com/docs/cli/overview), [Gemini CLI](https://github.com/google-gemini/gemini-cli), [Goose](https://block.github.io/goose/), [Kilo Code](https://kilo.ai), [Kimi CLI](https://github.com/MoonshotAI/kimi-cli), [Kiro](https://kiro.dev/cli/), [Mistral Vibe](https://github.com/mistralai/mistral-vibe) and [OpenCode](https://opencode.ai)
- :heart_hands: [Community adapters](/configuration/adapters-http#community-adapters), contributed and supported by users
- :man_technologist: [Code reviews](/usage/code-review) to comment on, accept or revert an agent's changes
- :battery: [Model Context Protocol (MCP)](/model-context-protocol) servers
- :rocket: [Inline](/usage/inline) code creation and refactoring
- :robot: [Editor context](/usage/chat-buffer/editor-context), [slash commands](/usage/chat-buffer/slash-commands), [tools](/usage/chat-buffer/agents-tools) and [workflows](/usage/workflows) to improve the LLM's output
- :brain: [Skills](/usage/chat-buffer/skills) and [rules](/usage/chat-buffer/rules), such as `CLAUDE.md`, `.cursor/rules` and your own
- :sparkles: A built-in [prompt library](/usage/prompt-library) for common tasks, like explaining code or LSP errors
- :building_construction: Your own [prompts](/configuration/prompt-library), editor context and slash commands
- :inbox_tray: [Multiple chats](/usage/chat-buffer/#multiple-chats) open at the same time
- :art: [Images](/usage/chat-buffer/#images) and PDFs as input
- :muscle: Async execution, so Neovim stays responsive

## Overview

CodeCompanion is built around _interactions_, the different ways you work with an LLM. The _chat_ interaction is a buffer where you converse with an LLM or an agent, and the _inline_ interaction writes the LLM's response straight into the buffer you're editing.

An [adapter](/configuration/adapters-http) connects an interaction to an LLM or an agent, and sets its [model](/configuration/adapters-http#changing-the-default-model) and [parameters](/configuration/adapters-http#changing-adapter-parameters-schema). Each interaction, and each [prompt library](/configuration/prompt-library) item, can use a different adapter. The full set is in the [adapters folder](https://github.com/olimorris/codecompanion.nvim/tree/main/lua/codecompanion/adapters/http). To write your own, see [Extending with Adapters](/extending/adapters).

## Using the Docs

Ask an LLM to search these docs for you with the [@{search_help}](/usage/chat-buffer/agents-tools#search-help) tool. On the site, use the search bar at the top left of the page.
