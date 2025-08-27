# Using Agents

CodeCompanion enables you to work with agents such as [Gemini](https://github.com/google-gemini/gemini-cli) by leveraging the [Agent Client Protocol](https://agentclientprotocol.com).

## Getting Started

To start coding with agents right away, open a chat buffer with `:CodeCompanionChat` and [switch](/usage/chat-buffer/#changing-adapter) to an ACP adapter such as `gemini_cli`, if it's not set as your default.

Currently, CodeCompanion only supports agent authentication via an API key. In the case of _gemini_cli_, ensure you've [set](/configuration/adapters.html#setting-an-api-key) the [correct](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/adapters/acp/gemini_cli.lua#L31) API key.

A key difference in working with agents versus LLMs is the matter of state. LLMs, via _http_ adapters, are stateless. This means that CodeCompanion sends the entire message history over with every request. Agents differ in that they are the ones responsible for managing state. As a result, CodeCompanion only sends the latest messages over with every prompt. From a UX perspective however, neither of these have an impact on how it feels to work with CodeCompanion.

## Prompting

Conversing with an agent in CodeCompanion is done in exactly the same way as with an LLM. Simply type your prompt and press `<C-CR>` in insert mode or `<CR>` in normal mode to send it to the agent.

[Slash Commands](/usage/chat-buffer/slash-commands) and [Variables](/usage/chat-buffer/variables) are available to share additional context with the agent. However, [Tools](/usage/chat-buffer/tools) are disabled as the agent has their own tool set and the autonomy to decide what to run and when.

As outlined in the Agent Client Protocol [documentation](https://agentclientprotocol.com/protocol/initialization), there are a number of steps which take place internally before a response is received from the agent. The initialization and creating of a session inevitably lead to the first prompt waiting slightly longer to receive a response than future ones.

## Permissions

At various points during the agent's lifecycle, you may be prompted for [permission](https://agentclientprotocol.com/protocol/schema#session%2Frequest-permission) to execute a tool.

If the agent wishes to edit a file, then you will be shown a diff and presented with the various options available to you. You can send a response back to the agent via the keymaps defined in your config at `strategies.chat.keymaps._acp_*` (which are also displayed to you in the diff). If there is no diff associated with the tool call then you will be prompted via [vim.fn.confirm](https://neovim.io/doc/user/editing.html#_6.-dialogs).

By default, the chat buffer will wait for c. 30 mins for you to respond to a permission request. This can be configured in `strategies.chat.opts.wait_timeout` with the default response, after a timeout, being defined at `strategies.chat.opts.acp_timeout_response`.

## Cancelling a Request

You can halt the execution of a request at any point by pressing `q` in normal mode which will send a cancellation notification to the agent.

## Images

The [image](/usage/chat-buffer/slash-commands.html#image) slash command can be leveraged to share images with the agent.
