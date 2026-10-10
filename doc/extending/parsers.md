---
description: "Write your own rules parser to transform a rules file before it's shared with an LLM."
---

# Extending with Rules Parsers

A _parser_ processes the contents of a [rules](/configuration/rules) file before it's shared with an LLM. It can rewrite the content, pull out a system prompt or add other files to the chat.

## Writing a Parser

A parser is a module that returns a function. The function receives the rules file and returns a table with a `content` key:

```lua
---@param file CodeCompanion.Chat.Rules.ProcessedFile
---@return CodeCompanion.Chat.Rules.Parser
return function(file)
  return { content = file.content or "" }
end
```

The `file` table has:

| Field | Description |
| --- | --- |
| `content` | The file's contents |
| `path` | The file's full path, or relative to the current working directory if it's inside it |
| `filename` | The file's name, without its directory |
| `name` | The path as written in your rules config, or the full path for a file found in a directory |

The parser can return:

| Key | Description |
| --- | --- |
| `content` | The text to share with the LLM. Required |
| `system_prompt` | Text to add as a system message |
| `meta.included_files` | Files to add to the chat as context |

If a parser errors, the file's original content is shared instead.

## Registering a Parser

Add it under `rules.parsers`, as a module path or a function that returns the parser:

```lua
require("codecompanion").setup({
  rules = {
    parsers = {
      my_parser = "my_config.rules.my_parser",
    },
  },
})
```

Then apply it to a rules group or file by name, as shown in [Applying Parsers](/configuration/rules#applying-parsers).

## Including Files

To add other files to the chat, return them in `meta.included_files`:

```lua
{
  content = "Your parsed content",
  meta = {
    included_files = {
      ".codecompanion/acp/acp_json_schema.json",
      "./lua/codecompanion/acp/init.lua",
      "./lua/codecompanion/adapters/acp/claude_code.lua",
    },
  },
}
```

Relative paths are resolved against the current working directory. A file that's open in a buffer is added as a buffer, and a file that's already in the chat isn't added again.

The built-in `claude` parser does this for every line that starts with `@`, such as `@AGENTS.md`.
