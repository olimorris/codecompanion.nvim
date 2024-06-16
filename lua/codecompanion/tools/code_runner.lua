local log = require("codecompanion.utils.log")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

---@class CodeCompanion.Tool
return {
  cmds = {
    { "docker", "pull", "${lang}" },
    {
      "docker",
      "run",
      "--rm",
      "-v",
      "${temp_dir}:${temp_dir}",
      "${lang}",
      "${lang}",
      "${temp_input}",
    },
  },
  schema = {
    name = "code_runner",
    parameters = {
      inputs = {
        lang = "python",
        code = "print('Hello World')",
      },
    },
  },
  prompts = {
    {
      role = "system",
      content = function(schema)
        return "You are an expert in writing and reviewing code. To aid you further, I'm giving you access to be able to execute code in a remote environment. This enables you to write code, trigger its execution and immediately see the output from your efforts. Of course, not every question I ask may need code to be executed so bear that in mind.\n\nTo execute code, you need to return a markdown code block which follows the below schema:"
          .. "\n\n```xml\n"
          .. xml2lua.toXml(schema, "tool")
          .. "\n```\n"
      end,
    },
    {
      role = "user",
      content = "\n \n",
    },
  },
  env = function(xml)
    local temp_input = vim.fn.tempname()
    local temp_dir = temp_input:match("(.*/)")
    local lang = xml.parameters.inputs.lang
    local code = xml.parameters.inputs.code

    return {
      code = code,
      lang = lang,
      temp_dir = temp_dir,
      temp_input = temp_input,
    }
  end,
  pre_cmd = function(env, xml)
    -- Write the code to a temporary file
    local file = io.open(env.temp_input, "w")
    if file then
      file:write(env.code)
      file:close()
    else
      log:error("Failed to write code to temporary file")
      return
    end
  end,
  output_error_prompt = function(error)
    if type(error) == "table" then
      error = table.concat(error, "\n")
    end
    return "After the tool completed, there was an error:"
      .. "\n\n```\n"
      .. error
      .. "\n```\n\n"
      .. "Can you attempt to fix this?"
  end,
  output_prompt = function(output)
    if type(output) == "table" then
      output = table.concat(output, "\n")
    end

    return "After the tool completed the output was:"
      .. "\n\n```\n"
      .. output
      .. "\n```\n\n"
      .. "Is that what you expected? If it is, just reply with a confirmation. Don't reply with any code. If not, say so and I can plan our next step."
  end,
}
