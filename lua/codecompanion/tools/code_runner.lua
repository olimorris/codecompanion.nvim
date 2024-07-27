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
  system_prompt = function(schema)
    return "I'm giving you access to the **Code Runner** tool which enables you to run any code that you've created. You can write code and using the tool, trigger its execution and immediately see the output. This is useful to see if the code worked as you intended. Of course, not every question I ask you will need the tool so bear that in mind.\n\nTo use the tool, you need to return an XML markdown code block (with backticks) which follows the below schema:"
      .. "\n\n```xml\n"
      .. xml2lua.toXml(schema, "tool")
      .. "\n```\n\n"
      .. "You can see that the schema has input parameters where you can specify the language (e.g. Python) and the code you'd like to run.\n\n"
      .. "NOTE: The tool will only parse the last schema that you respond with.\n\n"
      .. "NOTE: If you don't conform to the schema, EXACTLY, then the tool will not run.\n\n"
      .. "NOTE: Please respond concisely so I can understand and observe the code you're executing with the tool."
  end,
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
