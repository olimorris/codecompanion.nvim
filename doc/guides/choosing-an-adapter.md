---
description: "Pick between GitHub Copilot, an API provider, a local model, an OpenAI-compatible endpoint or an agent for CodeCompanion in Neovim, and set it up."
---

# Choosing an Adapter

CodeCompanion defaults to GitHub Copilot, which is no help if you don't have it. Every other option works too, and you can mix them across interactions. If you haven't set up the plugin yet, start with [Getting Started](/getting-started).

## The Options

An _adapter_ connects CodeCompanion to an LLM or an agent. They come in two types: _HTTP_ adapters send requests to a model and use CodeCompanion's own [tools](/usage/chat-buffer/agents-tools), whilst _ACP_ adapters hand the conversation to an agent that runs its own tools. The [CLI interaction](/usage/cli) sits apart from both, running an agent's own interface in a terminal inside Neovim.

| Option | Adapter | What you need |
|---|---|---|
| GitHub Copilot | `copilot` | A Copilot plan, including Free and Student, signed in with copilot.vim or copilot.lua |
| API provider | `anthropic`, `openai`, `gemini`, `deepseek`, `mistral`, `openrouter`, `xai`... | An API key |
| Local model | `ollama` | Ollama running on your machine or network |
| OpenAI-compatible endpoint | `openai_compatible` | The endpoint's URL, and a key if it requires one |
| ACP agent | `claude_code`, `codex`, `gemini_cli`, `opencode`, `copilot_acp`... | The agent installed and signed in |
| CLI interaction | Any agent you define | The agent's CLI installed |

The first four run CodeCompanion's own tools and work everywhere. An ACP agent runs its own tools and only works in the chat buffer. The CLI interaction runs in its own terminal buffer.

### GitHub Copilot

If you pay for Copilot, or have Copilot Free or Student, there's nothing to configure beyond signing in. The default model is `auto`, which lets Copilot pick the model and is the only option on the Free and Student plans. CodeCompanion reads the token that copilot.vim or copilot.lua saves when you sign in.

### An API Provider

Choose this when you already pay a provider or want a specific model. Each adapter reads its key from an environment variable named after the provider, such as `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` or `OPENROUTER_API_KEY`.

Adapters are set per _interaction_, which is one of the ways you work with an LLM in CodeCompanion. `chat` is the chat buffer and `inline` is `:CodeCompanion`, which edits a buffer in place. To use Anthropic for both:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = "anthropic",
    },
    inline = {
      adapter = "anthropic",
    },
  },
})
```

To read the key from a password manager or a file instead, see [environment variables](/configuration/adapters-http#environment-variables). [OpenRouter](/configuration/adapters-http#openrouter) gives you models from many providers behind one key.

### A Local Model

Choose this when code can't leave your machine or you don't want to pay per request. The `ollama` adapter connects to `http://localhost:11434`, or `OLLAMA_HOST` if it's set. Small local models are slower and weaker at tool calling than hosted ones, so expect agentic tasks with `@{agent}` to be less reliable. See [Running Local Models](/guides/running-local-models).

### An OpenAI-Compatible Endpoint

Choose this for a self-hosted server like llama.cpp or vLLM, or a company gateway that speaks the OpenAI API. There's no preset for it, so you extend `openai_compatible` with your URL. See [Connecting an OpenAI-Compatible Provider](/guides/openai-compatible-providers).

### An ACP Agent

Choose this when you already use Claude Code, Codex or another agent and want it in a chat buffer. The agent runs its own tools, so `@{files}` and the other CodeCompanion tools aren't offered, and it can bill against an existing subscription such as Claude Pro. Each agent needs installing and authenticating first. See [Coding with an Agent](/guides/coding-with-an-agent) and the setup steps in [ACP Adapters](/configuration/adapters-acp).

> [!NOTE]
> ACP adapters only work in the chat buffer. Inline, cmd and background interactions need an HTTP adapter

### The CLI Interaction

Choose this when you'd rather use the agent's own interface, with CodeCompanion sending it prompts and context from your buffers. Nothing is set up by default, so you define the agent yourself. See [Using the CLI](/usage/cli) and [Configuring the CLI](/configuration/cli).

## Choosing a Model

Every adapter has a default model. To use a different one, pass a table with the adapter's `name` and a `model` instead of just the name:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = {
        name = "anthropic",
        model = "claude-opus-5-5",
      },
    },
  },
})
```

This works for agents too, such as `{ name = "claude_code", model = "opus" }`. For an agent's mode and other options, see [Choosing a Default Model and Mode](/guides/coding-with-an-agent#choosing-a-default-model-and-mode).

Press `ga` in a chat buffer to see which models an adapter offers. Copilot, Anthropic, Mistral, OpenRouter, Hugging Face, Novita, Ollama and `openai_compatible` fetch the list from the provider, so it matches what your account can use. The others list a fixed set, but any model name the provider accepts works. See [Changing the Default Model](/configuration/adapters-http#changing-the-default-model) to set a model on the adapter itself rather than per interaction.

## Mixing Adapters

CodeCompanion has four interactions that use an adapter:

- **Chat** - The chat buffer (`:CodeCompanionChat`)
- **Inline** - Edits a buffer in place (`:CodeCompanion`)
- **Cmd** - Writes a command in the command-line (`:CodeCompanionCmd`)
- **Background** - Runs tasks without any input from you, such as naming a chat

Each has its own adapter, so you can pair an agent for long tasks in the chat buffer with a fast HTTP adapter for inline edits, and keep background tasks on something cheap:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      adapter = "claude_code",
    },
    inline = {
      adapter = "anthropic",
    },
    cmd = {
      adapter = "anthropic",
    },
    background = {
      adapter = {
        name = "ollama",
        model = "qwen3:8b",
      },
    },
  },
})
```

**Any interaction you leave unset stays on `copilot`**, and fails without it. See [Running Background Tasks on a Cheaper Model](/guides/background-model) for the background interaction.

## Switching in a Chat

Press `ga` in a chat buffer to pick a different adapter, then a model. **Once the LLM has called a tool or returned reasoning, you can only change the model, not the adapter.** Start a new chat instead.

<img src="https://github.com/user-attachments/assets/49094ea5-efa5-4490-ba5c-2d4b080d42c4" alt="Adapter picker" />

> [!NOTE]
> `ga` is disabled when `display.chat.show_settings = true`. Change the model in the settings at the top of the chat buffer instead

To open a chat with a specific adapter and model:

```
:CodeCompanionChat adapter=openai model=gpt-4.1
```

For an ACP adapter, `command=` picks one of the adapter's commands instead of a model, such as `:CodeCompanionChat adapter=gemini_cli command=yolo`. Inline prompts take the adapter too, with `:CodeCompanion adapter=anthropic <prompt>`. See [Commands](/commands) for the rest.

## Hiding Adapters

The `ga` picker and command completion list every preset. To remove the ones you never use:

```lua
require("codecompanion").setup({
  adapters = {
    http = {
      opts = {
        hidden = { azure_openai = true, huggingface = true, novita = true },
      },
    },
  },
})
```

Hidden adapters can still be set in your config and resolved by name. Your list is merged with the default one, which already hides `duckduckgo`, `jina`, `markitdown` and `tavily`.

To show only the adapters you've defined yourself, set `show_presets = false` under `adapters.http.opts` or `adapters.acp.opts`. See [Hiding Adapters](/configuration/adapters-http#hiding-adapters) and [Hiding Preset Adapters](/configuration/adapters-acp#hiding-preset-adapters).
