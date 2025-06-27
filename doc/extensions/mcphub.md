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

Please visit MCP Hub's [CodeCompanion](https://ravitemer.github.io/mcphub.nvim/extensions/codecompanion.html) extension page for detailed up-to-date usage instructions.

## Additional Resources

- [MCP Hub Documentation](https://github.com/ravitemer/mcphub.nvim)
- [Model Context Protocol Website](https://modelcontextprotocol.io/)
- [Guide on Creating Lua Native MCP Servers](https://github.com/ravitemer/mcphub.nvim/wiki/Native-Servers)
