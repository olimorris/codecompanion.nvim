# VectorCode Extension

[VectorCode](https://github.com/Davidyz/VectorCode) is a code repository
indexing tool that allows you to easily perform semantic search on your local
code repository. Its CodeCompanion extension gives the LLMs ability to search in
your local repositories for more context.

## Showcase

### Using VectorCode to Explore VectorCode Itself
![](https://github.com/Davidyz/VectorCode/blob/main/images/codecompanion_chat.png?raw=true)

### Using VectorCode to Explore neovim Lua API
![](https://private-user-images.githubusercontent.com/30951234/437676365-3aca5100-f47b-4536-9540-8813a6530518.png?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NDYyNTc1NTAsIm5iZiI6MTc0NjI1NzI1MCwicGF0aCI6Ii8zMDk1MTIzNC80Mzc2NzYzNjUtM2FjYTUxMDAtZjQ3Yi00NTM2LTk1NDAtODgxM2E2NTMwNTE4LnBuZz9YLUFtei1BbGdvcml0aG09QVdTNC1ITUFDLVNIQTI1NiZYLUFtei1DcmVkZW50aWFsPUFLSUFWQ09EWUxTQTUzUFFLNFpBJTJGMjAyNTA1MDMlMkZ1cy1lYXN0LTElMkZzMyUyRmF3czRfcmVxdWVzdCZYLUFtei1EYXRlPTIwMjUwNTAzVDA3MjczMFomWC1BbXotRXhwaXJlcz0zMDAmWC1BbXotU2lnbmF0dXJlPWJmM2ZkMzMyMTE4OTU0ODc0ZmMwZTQ3YTg5NDQ2YjYxMDQ3ZDI4NjU3NTI2MTdiN2Y0NjdmZjMyZDUwNzlkN2ImWC1BbXotU2lnbmVkSGVhZGVycz1ob3N0In0.iyLdYALw7iuqWcp8KYsImU_ju4uFlBs3l54EumO4B3I)

## Prerequisites

VectorCode requires some setting up before use. Specifically, you need to
install the Python backend that performs the heavy lifting, and vectorise files
in your projects so that they'll appear in your search results. For details on
how to set this up, please refer to the 
[VectorCode CLI documentation](https://github.com/Davidyz/VectorCode/blob/main/docs/cli.md).

## Installation

Install the 
[VectorCode neovim plugin](https://github.com/Davidyz/VectorCode/blob/main/docs/neovim.md).
If you're only using VectorCode with CodeCompanion, you don't have to pass any
options to the setup function. The most basic installation will do the trick:
```lua
{
  "Davidyz/VectorCode",
  version = "*", -- optional, depending on whether you're on nightly or release
  build = "pipx upgrade vectorcode", -- optional but recommended. This keeps your CLI up-to-date. 
  dependencies = { "nvim-lua/plenary.nvim" },
}
```

After that, register VectorCode as a CodeCompanion extension:
```lua
require("codecompanion").setup({
  extensions = {
    vectorcode = {
      opts = {
        add_tool = true,
      }
    }
  }
})
```
And you'll be able to use the `@vectorcode` command in CodeCompanion chat!

There are some options that allows you to configure the VectorCode CodeCompanion
extension, which may improve your experience when you talk to LLMs. For more
information, see [the VectorCode wiki](https://github.com/Davidyz/VectorCode/wiki/Neovim-Integrations).

## Usage

The CodeCompanion tool in VectorCode gives the LLM the ability to query from not
just one, but any projects on your system, as long as they're indexed in the
database (you can see them by running `vectorcode ls` in the terminal). Ideally
(that is, if your model is good at instruction following and long-context
handling), after given the tool (type `@vectorcode` in the chat), your model will 
start calling it when it needs to.

## Additional Resources

- [VectorCode GitHub repository](https://github.com/Davidyz/VectorCode).
- [VectorCode wiki](https://github.com/Davidyz/VectorCode/wiki).
- [VectorCode discussion forum](https://github.com/Davidyz/VectorCode/discussions).
