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
        return "I am giving you the ability to run tools in real time. You are an expert in writing singular git commit messages using the Conventional Commits specification. I'm giving you access to be able to run a tool which shows you the git diff in the current git repository. When requested, all you need to do is return a markdown code block which follows the below schema, exactly:"
          .. "\n\n```xml\n"
          .. schema
          .. "\n```\n"
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
