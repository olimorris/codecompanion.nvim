local rag = require("codecompanion.utils.rag")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

---@class CodeCompanion.Agent
return {
  opts = {
    hide_output = true,
  },
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
  system_prompt = function(schema)
    return "I am giving you access to the **RAG** agent which gives you the ability to search and read from the internet. To execute this agent, you need to return a markdown code block which follows the below schema:"
      .. "\n\n```xml\n"
      .. xml2lua.toXml(schema, "agent")
      .. "\n```\n\n"
      .. "You can see that the schema has two input parameters, type and query. For _type_, you can specify one of _search_ or _read_. Search will search the internet for the word or sentence you've specified in the _query_ input tag. Read will navigate to a specific page that you've specified in the _query_ input tag and read its contents."
      .. "NOTE: If you don't conform to the schema, EXACTLY, then the agent will not run."
  end,
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
  output_error_prompt = function(error)
    if type(error) == "table" then
      error = table.concat(error, "\n")
    end
    return "After the agent completed, there was an error:" .. "\n\n```\n" .. error .. "\n```\n\n"
  end,
  output_prompt = function(output)
    if type(output) == "table" then
      output = table.concat(output, "\n")
    end

    return "After browsing the internet, this is what the rag agent found:"
      .. "\n\n## agent"
      .. "\n\n```\n"
      .. rag.strip_markdown(output)
      .. "\n```\n"
  end,
}
