local rag = require("codecompanion.utils.rag")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

---@class CodeCompanion.Agent
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
        return "I am giving you access to a real-time capabilities and external databases via the use of something I'm calling a RAG (retrieval augmented generation) agent."
          .. "\n\nWith this agent, you can search and read from the internet. To execute this agent, you need to return a markdown code block which follows the below schema:"
          .. "\n\n```xml\n"
          .. xml2lua.toXml(schema, "agent")
          .. "\n```\n\n"
          .. "You only need to change the query and type values in the schema. Do not change the name. Please only execute one of the agents at a time. Review the output before deciding if you need to run another agent"
      end,
    },
    {
      role = "user",
      content = function()
        return "Using the rag agent, can you "
      end,
    },
  },
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
