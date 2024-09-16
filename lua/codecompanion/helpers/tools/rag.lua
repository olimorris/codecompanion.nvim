local rag = require("codecompanion.utils.rag")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

---@class CodeCompanion.Tool
return {
  name = "rag",
  cmds = {
    { "curl", "${address}${query}" },
  },
  schema = {
    {
      name = "rag",
      parameters = {
        inputs = {
          action = "search",
          query = "The query to search for",
        },
      },
    },
    {
      name = "rag",
      parameters = {
        inputs = {
          action = "navigate",
          url = "The page to navigate to",
        },
      },
    },
  },
  system_prompt = function(schema)
    return string.format(
      [[### You have gained access to a new tool!

Name: RAG (Retrieval Augmented Generation)
Purpose: This gives you the ability to search or read from the internet
Why: Sometimes you may need up to date information from the internet to help you with your responses
Usage: To use this tool, you need to return an XML markdown code block (with backticks). Consider the following schema::

```xml
%s
```

It will use the RAG tool to search the internet:
- Ensure the action input tag contains 'search'
- Include your search query in the query input tag

```xml
%s
```

It will use the RAG tool to navigate to a specific page:
- Ensure action input tag contains 'navigate'
- Include the URL of the page you'd like to read in the url input tag]],
      xml2lua.toXml(schema[1], "tool"),
      xml2lua.toXml(schema[2], "tool")
    )
  end,
  env = function(xml)
    local address
    local query = xml.parameters.inputs.query

    local action = xml.parameters.inputs.action
    if action == "search" then
      address = "https://s.jina.ai/"
      query = rag.encode(query)
    elseif action == "read" then
      address = "https://r.jina.ai/"
      query = xml.parameters.inputs.url
    end

    return {
      address = address,
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
