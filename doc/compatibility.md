# Compatibility

## Tools / Function Calling

In order to use [Tools](/usage/chat-buffer/agents) in CodeCompanion, the adapter and model need to support function calling. Below is a list of the status of various adapters and models in the plugin:

| Adapter           | Model                      | Supported          | Notes                            |
|-------------------|----------------------------| :----------------: |----------------------------------|
| Anthropic         | claude-3-opus-20240229     | :white_check_mark: |                                  |
| Anthropic         | claude-3-5-haiku-20241022  | :white_check_mark: |                                  |
| Anthropic         | claude-3-5-sonnet-20241022 | :white_check_mark: |                                  |
| Anthropic         | claude-3-7-sonnet-20250219 | :white_check_mark: |                                  |
| Copilot           | gpt-4o                     | :white_check_mark: |                                  |
| Copilot           | gpt-4.1                    | :white_check_mark: |                                  |
| Copilot           | o1                         | :white_check_mark: |                                  |
| Copilot           | o3-mini                    | :white_check_mark: |                                  |
| Copilot           | o4-mini                    | :white_check_mark: |                                  |
| Copilot           | claude-3-5-sonnet          | :white_check_mark: |                                  |
| Copilot           | claude-3-7-sonnet          | :white_check_mark: |                                  |
| Copilot           | claude-3-7-sonnet-thought  | :x:                | Doesn't support function calling |
| Copilot           | gemini-2.0-flash-001       | :x:                |                                  |
| Copilot           | gemini-2.5-pro             | :x:                |                                  |
| DeepSeek          | deepseek-chat              | :white_check_mark: |                                  |
| DeepSeek          | deepseek-reasoner          | :x:                | Doesn't support function calling |
| Gemini            | Gemini-2.0-flash           | :white_check_mark: |                                  |
| Gemini            | Gemini-2.5-pro-exp-03-25   | :white_check_mark: |                                  |
| GitHub Models     | All                        | :x:                | Not supported yet                |
| Huggingface       | All                        | :x:                | Not supported yet                |
| Mistral           | All                        | :x:                | Not supported yet                |
| Novita            | All                        | :x:                | Not supported yet                |
| Ollama            | All                        | :x:                | Doesn't support function calling |
| OpenAI Compatible | All                        | :grey_question:    | Unable to test                   |
| OpenAI            | gpt-3.5-turbo              | :white_check_mark: |                                  |
| OpenAI            | gpt-4                      | :white_check_mark: |                                  |
| OpenAI            | gpt-4o                     | :white_check_mark: |                                  |
| OpenAI            | gpt-4o-mini                | :white_check_mark: |                                  |
| OpenAI            | o1-2024-12-17              | :white_check_mark: |                                  |
| OpenAI            | o1-mini-2024-09-12         | :x:                | Doesn't support function calling |
| OpenAI            | o3-mini-2025-01-31         | :white_check_mark: |                                  |
| xAI               | All                        | :x:                |                                  |




