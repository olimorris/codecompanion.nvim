# Welcome to CodeCompanion.nvim

> AI-powered coding, seamlessly in _Neovim_

CodeCompanion is a productivity tool which streamlines how you develop with LLMs, in Neovim.

<video controls autoplay muted src="https://github.com/user-attachments/assets/04a2bed3-7af0-4c07-b58f-f644cef1c4bb"></video>

## Features

- :speech_balloon: [Copilot Chat](https://github.com/features/copilot) meets [Zed AI](https://zed.dev/blog/zed-ai), in Neovim
- :electric_plug: Support for Anthropic, Copilot, Gemini, Ollama, OpenAI, Azure OpenAI, HuggingFace and xAI LLMs (or bring your own!)
- :rocket: Inline transformations, code creation and refactoring
- :robot: Variables, Slash Commands, Agents/Tools and Workflows to improve LLM output
- :sparkles: Built in prompt library for common tasks like advice on LSP errors and code explanations
- :building_construction: Create your own custom prompts, Variables and Slash Commands
- :books: Have multiple chats open at the same time
- :muscle: Async execution for fast performance

## Plugin Overview

The plugin uses [adapters](configuration/adapters) to connect to LLMs. Out of the box, the plugin supports:

- Anthropic (`anthropic`) - Requires an API key and supports [prompt caching](https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching)
- Copilot (`copilot`) - Requires a token which is created via `:Copilot setup` in [Copilot.vim](https://github.com/github/copilot.vim)
- Gemini (`gemini`) - Requires an API key
- HuggingFace (`huggingface`) - Requires an API key
- Ollama (`ollama`) - Both local and remotely hosted
- OpenAI (`openai`) - Requires an API key
- Azure OpenAI (`azure_openai`) - Requires an Azure OpenAI service with a model deployment
- xAI (`xai`) - Requires an API key

The plugin utilises objects called Strategies. These are the different ways that a user can interact with the plugin. The _chat_ strategy harnesses a buffer to allow direct conversation with the LLM. The _inline_ strategy allows for output from the LLM to be written directly into a pre-existing Neovim buffer.

The plugin allows you to specify adapters for each strategy and also for each [prompt library](configuration/prompt-library) entry.

