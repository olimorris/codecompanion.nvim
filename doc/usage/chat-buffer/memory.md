# Using Memory

LLMs don’t retain memory between completions. In CodeCompanion, memory provides persistent, reusable context for chat buffers, via the notion of groups.

Below is the `default` memory group in the plugin:

```lua
require("codecompanion").setup({
  memory = {
    default = {
      description = "My default group",
      files = {
        ".clinerules",
        ".cursorrules",
        ".goosehints",
        ".rules",
        ".windsurfrules",
        ".github/copilot-instructions.md",
        "AGENT.md",
        "AGENTS.md",
        { path = "CLAUDE.md", parser = "claude" },
        { path = "CLAUDE.local.md", parser = "claude" },
        { path = "~/.claude/CLAUDE.md", parser = "claude" },
      },
    },
  },
})
```

Once [enabled](/configuration/memory#enabling-memory), there are many ways that memory can be added to the chat buffer.

## Creating Memory

The plugin does not require memory to be in a specific filetype or even format (unless you're using the `claude` parser). This allows you to leverage [mdc](https://docs.cursor.com/en/context/rules#rule-anatomy) files, markdown files or good old plain text files.

The location of the memory is also unimportant. The memory files could be local to the project you're working in. Or, they could reside in a separate location on your disk. Just ensure the path is correct when you're [creating/configuring](/configuration/memory#working-with-groups) the memory group.

## Adding Memory

### When Opening the Chat Buffer

Memory can automatically be added to a chat buffer when it's created. Simply modify the `memory.opts.chat.default_memory` value to reflect the group(s) you wish to add:

```lua
require("codecompanion").setup({
  memory = {
    opts = {
      chat = {
        default_memory = { "default", "claude "}
      },
    },
  },
})
```

Or, edit the group that resides in `memory.opts.chat.default_memory`:

```lua
require("codecompanion").setup({
  memory = {
    default = {
      description = "My default group",
      files = {
        "CLAUDE.md",
        "~/Code/Helpers/my_project_specific_help.md",
      },
    },
    opts = {
      chat = {
        default_memory = "default",
      },
    },
  },
})
```

### Whilst in the Chat Buffer

To add memory to an existing chat buffer, use the `/memory` slash command. This will allow multiple memory groups to be added at a time.

### From the Action Palette

<img src="https://github.com/user-attachments/assets/09ecd976-ac8b-446f-bed3-a8122617eb79">

There is also a _Chat with memory_ action in the [Action Palette](/usage/action-palette). This lists all of the memory groups in the config that can be added to a new chat buffer.

### Clearing Memory

Memory can also be cleared from a chat buffer via the `gM` keymap. Although note, this will remove _ALL_ context that's been designated as _memory_.

