# Using Memory

LLMs don’t retain memory between completions. In CodeCompanion, memory provides persistent, reusable context for chat buffers, via the notion of groups.

Once [enabled](/configuration/memory#enabling-memory), there are many ways that memory can be added to the chat buffer.

## With the Chat Buffer

Simply modify the `memory.opts.chat.default_memory` value to reflect the group(s) you wish to automatically add to the chat buffer:

```lua
require("codecompanion").setup({
  memory = {
    opts = {
      chat = {
        default_memory = { "default", "claude "}
    },
  },
})
```

## In the Chat Buffer

To add memory to an existing chat buffer, you can use the `/memory` slash command. This will allow multiple memory groups to be added at a time whilst also protecting against duplicate files.

## From the Action Palette

<img src="https://github.com/user-attachments/assets/09ecd976-ac8b-446f-bed3-a8122617eb79">

There is also a _Chat with memory_ action in the [Action Palette](/usage/action-palette). This lists all of the memory groups in the config that can be added to the chat buffer.

## Clearing Memory

Memory can also be cleared from the chat buffer via the `gM` keymap. Although note, this will remove _ALL_ context that's been designated as "memory".
