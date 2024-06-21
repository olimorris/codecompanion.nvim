local rag = require("codecompanion.utils.rag")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

---@class CodeCompanion.Tool
return {
  cmds = {
    { "curl", "${address}${query}" },
  },
  schema = {
    name = "rag",
    parameters = {
      inputs = {
        type = "Please choose from 'search' or 'read'",
        query = "The query to search for or the URL to browse",
      },
    },
  },
  opts = {
    hide_output = true,
  },
  env = function(xml)
    local address
    local query = xml.parameters.inputs.query

    local type = xml.parameters.inputs.type
    if type == "search" then
      address = "https://s.jina.ai/"
      query = rag.encode(query)
    elseif type == "read" then
      address = "https://r.jina.ai/"
    end

    return {
      address = address,
      query = query,
    }
  end,
  prompts = {
    {
      role = "system",
      content = function(schema)
        return "I am giving you access to a real-time capabilities and external databases via the use of something I'm calling a tool."
          .. "\n\nWith this tool, you can search and read from the internet. To execute this tool, you need to return a markdown code block which follows the below schema:"
          .. "\n\n```xml\n"
          .. xml2lua.toXml(schema, "tool")
          .. "\n```\n\n"
          .. "You only need to change the query and type values in the schema. Do not change the name. Please only execute one of the tools at a time. Review the output before deciding if you need to run another tool"
      end,
    },
    {
      role = "user",
      content = function()
        return "Using the tool, can you "
      end,
    },
  },
  output_error_prompt = function(error)
    if type(error) == "table" then
      error = table.concat(error, "\n")
    end
    return "After the tool completed, there was an error:" .. "\n\n```\n" .. error .. "\n```\n\n"
  end,
  output_prompt = function(output)
    if type(output) == "table" then
      output = table.concat(output, "\n")
    end

    return "The output from the tool can be seen below. Please use the output to answer the user's question or run another of the tools at your disposal:"
      .. "\n\n## Tool"
      .. "\n\n```\n"
      .. rag.strip_markdown(output)
      .. "\n```\n"
  end,
}
