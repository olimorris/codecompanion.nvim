# Configuring the Prompt Library

The plugin comes with a number of pre-built prompts. As per [the config](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/config.lua), these can be called via keymaps or via the cmdline. These prompts have been carefully curated to mimic those in [GitHub's Copilot Chat](https://docs.github.com/en/copilot/using-github-copilot/asking-github-copilot-questions-in-your-ide). Of course, you can create your own prompts and add them to the Action Palette or even to the slash command completion menu in the chat buffer.

## Adding Prompts

> [!NOTE]
> See the [Creating Prompts](/extending/prompt-library) guide to learn more on their syntax and how you can create your own

Custom prompts can be added as follows:

```lua
require("codecompanion").setup({
  prompt_library = {
    ["Docusaurus"] = {
      strategy = "chat",
      description = "Write documentation for me",
      opts = {
        index = 11,
        is_slash_cmd = false,
        auto_submit = false,
        short_name = "docs",
      },
      references = {
        {
          type = "file",
          path = {
            "doc/.vitepress/config.mjs",
            "lua/codecompanion/config.lua",
            "README.md",
          },
        },
      },
      prompts = {
        {
          role = "user",
          content = [[I'm rewriting the documentation for my plugin CodeCompanion.nvim, as I'm moving to a vitepress website. Can you help me rewrite it?

I'm sharing my vitepress config file so you have the context of how the documentation website is structured in the `sidebar` section of that file.

I'm also sharing my `config.lua` file which I'm mapping to the `configuration` section of the sidebar.
]],
        },
      },
    },
  },
})
```
