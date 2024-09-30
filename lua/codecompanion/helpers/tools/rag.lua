local rag = require("codecompanion.utils.rag")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

---@class CodeCompanion.Tool
return {
  name = "rag",
  cmds = {
    { "curl", "${url}/${query}" },
  },
  schema = {
    {
      tool = {
        _attr = { name = "rag" },
        action = {
          _attr = { type = "search" },
          query = "What's the newest version of Neovim?",
        },
      },
    },
    {
      tool = {
        _attr = { name = "rag" },
        action = {
          _attr = { type = "navigate" },
          url = "https://github.com/neovim/neovim/releases",
        },
      },
    },
  },
  system_prompt = function(schema)
    return string.format(
      [[### You have gained access to a new tool!

Name: RAG (Retrieval Augmented Generation)
Purpose: This gives you the ability to pull information from the internet
Why: Sometimes you may need up to date information from the internet to help you with your responses
Usage: To use this tool, you need to return an XML markdown code block (with backticks). Consider the following schema:

```xml
%s
```

This is how you can use the RAG tool to search the internet. In this specific example, to search for the newest version of Neovim. Based on returned results results, you could then decide to navigate to a specific URL:

```xml
%s
```

Such as in this example where you can navigate to the Neovim releases page.

You must:
- Only use the tool when you have a gap in your knowledge and need to pull information from the internet
- Be mindful that you may not be required to use the tool in all of your responses
- Ensure the XML markdown code block is valid and follows the schema]],
      xml2lua.toXml({ tools = { schema[1] } }),
      xml2lua.toXml({ tools = { schema[2] } })
    )
  end,
  env = function(tool)
    local url
    local query
    local action = tool.action._attr.type
    if action == "search" then
      url = "https://s.jina.ai"
      query = rag.encode(tool.action.query)
    elseif action == "navigate" then
      url = "https://r.jina.ai"
      query = tool.action.url
    end

    return {
      url = url,
      query = query,
    }
  end,
  output_error_prompt = function(error)
    if type(error) == "table" then
      error = table.concat(error, "\n")
    end
    return string.format(
      [[After the tool completed, there was an error:

```
%s
```
]],
      error
    )
  end,
  output_prompt = function(output)
    if type(output) == "table" then
      output = table.concat(output, "\n")
    end

    return string.format(
      [[After browsing the internet, this is what the rag tool found:

### tool output

```
%s
```
]],
      rag.strip_markdown(output)
    )
  end,
}
