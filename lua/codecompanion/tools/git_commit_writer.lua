local log = require("codecompanion.utils.log")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

---@class CodeCompanion.Tool
return {
  cmds = {
    { "git", "diff" },
  },
  schema = [[<tool>
  <name>git_commit_writer</name>
</tool>]],
  opts = {
    hide_output = true,
  },
  prompts = {
    {
      role = "system",
      content = function(schema)
        return "You are an expert in writing singular git commit messages using the Conventional Commits specification.\n\nI am giving you access to a tool that shows you the git diff of the current repository. When prompted by the user, you can initiate the tool and receive the git diff output. Simply return a markdown code block that follows the given schema exactly:"
          .. "\n\n```xml\n"
          .. schema
          .. "\n```"
          .. "\n\nThe tool will then execute and the output will be shown to you so you can write the commit message."
      end,
    },
    {
      role = "user",
      content = function()
        return "Can you generate git commit message for me using the tool, with no explanations?"
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
      .. "\n\n## Tool"
      .. "\n\n```\n"
      .. output
      .. "\n```\n\n"
      .. "If appropriate, please respond with the git commit message in a code block."
  end,
}
