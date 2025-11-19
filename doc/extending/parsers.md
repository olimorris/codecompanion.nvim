---
description: Learn how to create your parsers for memory in CodeCompanion
---

# Creating Memory Parsers

In CodeCompanion, parsers act on the contents of a memory file, carrying out some post-processing activities and returning the content back to the memory class.

Parsers serve as an excellent way to apply modifications and extract metadata prior to sharing them with an LLM.

## Structure of a Parser

A parser has limited restrictions. It is simply required to return a function that the _memory_ class can execute, passing in the file to be processed as a parameter:

```lua
---@class CodeCompanion.Chat.Memory.Parser
---@field content string The content of the memory file
---@field meta? { included_files: string[] } The filename of the memory file

---@param file CodeCompanion.Chat.Memory.ProcessedFile
---@return CodeCompanion.Chat.Memory.Parser
return function(file)
  -- Your logic
end
```

As an output, the function must return a table containing a `content` key.

## Processing Files

Parsers may also return a list of files to be shared with the LLM by the _memory_ class. To enable this, ensure that the parser returns a `meta.included_files` array in its output:

```lua
{
  content = "Your parsed content",
  meta = {
    included_files = {
      ".codecompanion/acp/acp_json_schema.json",
      "./lua/codecompanion/acp/init.lua",
      "./lua/codecompanion/adapters/acp/claude_code.lua",
      "./lua/codecompanion/adapters/acp/helpers.lua",
      "./lua/codecompanion/acp/prompt_builder.lua",
      "./lua/codecompanion/strategies/chat/acp/handler.lua",
      "./lua/codecompanion/strategies/chat/acp/request_permission.lua",
    },
  },
}
```
