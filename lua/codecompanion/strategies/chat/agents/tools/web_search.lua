local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local function tavily_result_to_string(results)
  local output = {}
  for _, result in ipairs(results) do
    local title = result.title or ""
    local url = result.url or ""
    local content = result.content or ""
    table.insert(output, string.format("**Title: %s**\nURL: %s\nContent: %s\n\n", title, url, content))
  end
  return table.concat(output, "")
end

local function websearch(action, adapter, agent)
  log:debug('Web Search Tool: Searching for "%s"', action.query)

  return client
    .new({
      adapter = adapter,
    })
    :request({
      query = action.query,
    }, {
      callback = function(err, data)
        if err then
          return log:error("Failed to fetch the URL, with error %s", err)
        end

        if data then
          local ok, body = pcall(vim.json.decode, data.body)
          if not ok then
            return log:error("Could not parse the JSON response")
          end
          if data.status == 200 then
            local content = ""

            if adapter.name == "tavily" then
              content = tavily_result_to_string(body.results)
            end

            return agent.chat:add_buf_message({
              role = config.constants.LLM_ROLE,
              content = content,
            })
          else
            return log:error("Error %s - %s", data.status, body)
          end
        end
      end,
    })
end

---@class CodeCompanion.Agent.Tool
return {
  name = "web_search",
  cmds = {},
  schema = {
    {
      tool = {
        _attr = { name = "web_search" },
        action = {
          query = "<![CDATA[Neovim latest version]]>",
        },
      },
    },
  },
  system_prompt = function(schema, xml2lua)
    return string.format(
      [[## Web Search Tool (`web_search`) – Enhanced Guidelines

### Purpose:
- Search for recent information on the web to provide relevant context to the LLM.

### When to Use:
- Search for the query the users asks and include it inside the CDATA block.
- Do not include the "web_search" call in the query.
- Use this tool strictly for web search.

### Execution Format:
- Always return an XML markdown code block.
- Each search query should:
  - Be wrapped in a CDATA section to protect special characters.
  - Follow the XML schema exactly.

### XML Schema:
- The XML must be valid. Each tool invocation should adhere to this structure:

```xml
%s
```

### Key Considerations
- **Safety First:** Ensure every search query is safe and validated.

### Reminder
- Minimize explanations and focus on returning precise XML blocks with CDATA-wrapped commands.
- Follow this structure each time to ensure consistency and reliability.]],
      xml2lua.toXml({ tools = { schema[1] } })
    )
  end,
  handlers = {
    ---@param agent CodeCompanion.Agent The tool object
    setup = function(agent)
      local tool = agent.tool --[[@type CodeCompanion.Agent.Tool]]
      local action = tool.request.action

      local ok, adapter = pcall(require, "codecompanion.adapters.non_llm." .. agent.tool.opts.adapter)

      if not ok then
        return log:error("Failed to load the adapter for the web_search Tool")
      end

      if type(adapter) == "function" then
        adapter = adapter()
      end

      adapter = adapters.resolve(adapter)
      if not adapter then
        return log:error("Failed to load the adapter for the fetch Slash Command")
      end

      table.insert(tool.cmds, action)

      return websearch(action, adapter, agent)
    end,
  },
}
