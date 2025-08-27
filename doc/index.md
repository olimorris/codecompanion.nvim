---
prev: false
next:
  text: 'Installation'
  link: '/installation'
---

# Welcome to CodeCompanion.nvim

> AI Coding, Vim Style

CodeCompanion is a productivity tool which streamlines how you develop with LLMs, in Neovim.

<p>
<video controls muted src="https://github.com/user-attachments/assets/3cc83544-2690-49b5-8be6-51e671db52ef"></video>
</p>

## Features

- :speech_balloon: [Copilot Chat](https://github.com/features/copilot) meets [Zed AI](https://zed.dev/blog/zed-ai), in Neovim
- :electric_plug: Support for LLMs from Anthropic, Copilot, GitHub Models, DeepSeek, Gemini, Mistral AI, Novita, Ollama, OpenAI, Azure OpenAI, HuggingFace and xAI out of the box (or bring your own!)
- :robot: Support for [Agent Client Protocol](https://agentclientprotocol.com/overview/introduction), enabling coding with agents like [Gemini CLI](https://github.com/google-gemini/gemini-cli)
- :heart_hands: User contributed and supported [adapters](/configuration/adapters#community-adapters)
- :rocket: [Inline transformations](/usage/inline-assistant.html), code creation and refactoring
- :robot: [Variables](/usage/chat-buffer/variables), [Slash Commands](/usage/chat-buffer/slash-commands), [Tools](/usage/chat-buffer/tools) and [Workflows](/usage/workflows) to improve LLM output
- :crystal_ball: Native [Super Diff](/usage/chat-buffer/index#super-diff) for tracking agent edits
- :sparkles: Built-in [prompt library](/usage/action-palette.html) for common tasks like advice on LSP errors and code explanations
- :building_construction: Create your own [custom prompts](extending/prompts), Variables and Slash Commands
- :books: Have [multiple chats](/usage/introduction#quickly-accessing-a-chat-buffer) open at the same time
- :art: Support for [vision and images](/usage/chat-buffer/#images-vision) as input
- :muscle: Async execution for fast performance

## Plugin Overview

The plugin uses [adapters](configuration/adapters) to connect to LLMs. Out of the box, the plugin supports:

- Anthropic (`anthropic`) - Requires an API key and supports [prompt caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
- Copilot (`copilot`) - Requires a token which is created via `:Copilot setup` in [Copilot.vim](https://github.com/github/copilot.vim)
- GitHub Models (`githubmodels`) - Requires [`gh`](https://github.com/cli/cli) to be installed and logged in
- DeepSeek (`deepseek`) - Requires an API key
- Gemini (`gemini`) - Requires an API key
- HuggingFace (`huggingface`) - Requires an API key
- Mistral AI (`mistral`) - Requires an API key
- Novita (`novita`) - Requires an API key
- Ollama (`ollama`) - Both local and remotely hosted
- OpenAI (`openai`) - Requires an API key
- Azure OpenAI (`azure_openai`) - Requires an Azure OpenAI service with a model deployment
- xAI (`xai`) - Requires an API key

The plugin utilises objects called _strategies_. These are the different ways that a user can interact with the plugin. The _chat_ strategy harnesses a buffer to allow direct conversation with the LLM. The _inline_ strategy allows for output from the LLM to be written directly into a pre-existing Neovim buffer.

The plugin allows you to specify adapters for each strategy and also for each [prompt library](configuration/prompt-library) entry.
