# MCP Hub Extension

[MCP Hub](https://github.com/ravitemer/mcphub.nvim) is a powerful extension that adds [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) support to CodeCompanion, allowing you to use MCP tools and resources in your chat interactions.

## Features

- Access MCP tools via `@mcp` in chat
- Use MCP resources as chat variables with `#` prefix
- Execute MCP prompts via slash commands
- Real-time updates when servers change

## Installation

First, install MCP Hub:

```lua
{
  "ravitemer/mcphub.nvim",
  build = "npm install -g mcp-hub@latest",
  config = function()
    require("mcphub").setup()
  end
}
```

For detailed MCP Hub configuration options, see the [MCPHub documentation](https://github.com/ravitemer/mcphub.nvim#installation).

## CodeCompanion Setup

Add MCP Hub as an extension in your CodeCompanion configuration:

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

- Type `@mcp` to add available MCP servers to system prompts and add tool access
- Use `#variable_name` to access MCP resources in chat
- Use `/mcp:prompt_name` to execute MCP prompts


### Resources as Variables

When `make_vars = true`, MCP resources become available as chat variables. For example:

![image](https://github.com/user-attachments/assets/fb04393c-a9da-4704-884b-2810ff69f59a)

* E.g LSP current file diagnostics
![image](https://github.com/user-attachments/assets/8aeaa5f6-f48a-46fd-b761-4f4e34aeb262)

### Prompts as Slash Commands

When `make_slash_commands = true`, MCP prompts become available as slash commands:
- Format: `/mcp:prompt_name`
- Arguments are handled via vim.ui.input

![image](https://github.com/user-attachments/assets/678a06a5-ada9-4bb5-8f49-6e58549c8f32) 

![image](https://github.com/user-attachments/assets/f1fa305a-5d48-4119-b3e6-e13a9176da07)


### Auto-approval

Tool requests can be automatically approved in several ways:
1. MCPHub config: `config.auto_approve = true`
2. Global MCPHub setting: `vim.g.mcphub_auto_approve = true`
3. CodeCompanion's gta mode: `vim.g.codecompanion_auto_tool_mode = true`
4. Using the `gta` command in chat

The tool will respect any of these auto-approval settings.

## See Also

- [MCP Hub Documentation](https://github.com/ravitemer/mcphub.nvim)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Creating Lua Native MCP Servers](https://github.com/ravitemer/mcphub.nvim/wiki/Native-Servers)
