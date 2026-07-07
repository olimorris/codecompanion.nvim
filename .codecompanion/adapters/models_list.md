# Models List

CodeCompanion allows some adapters to dynamically fetch the list of models that they support.

@./lua/codecompanion/adapters/http/openrouter.lua
@./lua/codecompanion/adapters/http/copilot/get_models.lua

This can be seen in the OpenRouter and Copilot adapters.

## Anthropic

Anthropic's `https://api.anthropic.com/v1/models` endpoint (with `x-api-key` and `anthropic-version` headers) outputs:

@./tests/adapters/http/stubs/model_list/anthropic.json

## Copilot

Copilot's endpoint outputs:

@./tests/adapters/http/stubs/model_list/copilot.json

## Ollama

Ollama's endpoint `http://localhost:11434/api/tags`:

@./tests/adapters/http/stubs/model_list/ollama.json

## OpenRouter

OpenRouter's `https://openrouter.ai/api/v1/models` endpoint outputs:

@./tests/adapters/http/stubs/model_list/openrouter.json
