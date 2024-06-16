local log = require("codecompanion.utils.log")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

---@class CodeCompanion.Tool
return {
  cmds = {
    { "git", "diff" },
  },
  schema = {
    name = "git_commit_writer",
    parameters = {},
  },
  prompts = {
    {
      role = "system",
      content = function(schema)
        return "You are an expert in writing singular git commit messages using the Conventional Commits specification. I'm giving you access to be able to run a tool which shows you the git diff in the current git repository.\n\nTo see the changes and execute the command, you need to return a markdown code block which follows the below schema:"
          .. "\n\n```xml\n"
          .. xml2lua.toXml(schema, "tool")
          .. "\n```\n"
      end,
    },
    {
      role = "user",
      content = function()
        return "Can you generate git commit message for me?"
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

    return "After the tool completed the output was:"
      .. "\n\n```\n"
      .. output
      .. "\n```\n\n"
      .. "If appropriate, please respond with the git commit message in a code block."
  end,
}
