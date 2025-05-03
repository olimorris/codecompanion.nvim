# MCP Hub

[MCP Hub](https://github.com/ravitemer/mcphub.nvim) is an extension that integrates the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) with CodeCompanion. It allows you to leverage MCP tools and resources directly within your chat interactions.

## Features

- Access MCP tools via the `@mcp` tool in the chat buffer.
- Utilize MCP resources as context variables using the `#` prefix (e.g., `#resource_name`).
- Execute MCP prompts directly using `/mcp:prompt_name` slash commands.
- Receive real-time updates in CodeCompanion when MCP servers change.

## Installation

First, install the MCP Hub Neovim plugin:

```lua
{
  "ravitemer/mcphub.nvim",
  build = "npm install -g mcp-hub@latest",
  config = function()
    require("mcphub").setup()
  end
}
```

For detailed MCP Hub configuration options, please refer to the [documentation](https://github.com/ravitemer/mcphub.nvim#installation).

Next, register MCP Hub as an extension in your CodeCompanion configuration:

```lua
require("codecompanion").setup({
  extensions = {
    mcphub = {
      callback = "mcphub.extensions.codecompanion",
      opts = {
        show_result_in_chat = true,  -- Show mcp tool results in chat
        make_vars = true,            -- Convert resources to #variables
        make_slash_commands = true,  -- Add prompts as /slash commands
      }
    }
  }
})
```

## Usage

Once configured, you can interact with MCP Hub within the CodeCompanion chat buffer:

-   **Tool Access:** Type `@mcp` to add available MCP servers to the system prompt, enabling the LLM to use registered MCP tools.
-   **Resources as Variables:** If `make_vars = true`, MCP resources become available as variables prefixed with `#`. You can include these in your prompts (e.g., `Summarize the issues in #mcp:lsp:get_diagnostics`):

*Example: Accessing LSP diagnostics*:

![image](https://github.com/user-attachments/assets/fb04393c-a9da-4704-884b-2810ff69f59a)
![image](https://github.com/user-attachments/assets/8aeaa5f6-f48a-46fd-b761-4f4e34aeb262)

**Prompts as Slash Commands:** If `make_slash_commands = true`, MCP prompts are available as slash commands (e.g., `/mcp:prompt_name`). Arguments are handled via `vim.ui.input`.

*Example: Using an MCP prompt via slash command*:

![image](https://github.com/user-attachments/assets/678a06a5-ada9-4bb5-8f49-6e58549c8f32)

![image](https://github.com/user-attachments/assets/f1fa305a-5d48-4119-b3e6-e13a9176da07)

### Auto-approvals

MCP tool requests can be automatically approved, bypassing the confirmation prompt, if any of the following are true:
1. MCP Hub configuration:
```lua
require("mcphub").setup({
  config = { auto_approve = true }
})
```
2. Global MCP Hub variable: `vim.g.mcphub_auto_approve = true`
3. CodeCompanion auto tool mode: `vim.g.codecompanion_auto_tool_mode = true` (toggled via `gta` in the chat buffer)

## Additional Resources

- [MCP Hub Documentation](https://github.com/ravitemer/mcphub.nvim)
- [Model Context Protocol Website](https://modelcontextprotocol.io/)
- [Guide on Creating Lua Native MCP Servers](https://github.com/ravitemer/mcphub.nvim/wiki/Native-Servers)
