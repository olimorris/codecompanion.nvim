local log = require("codecompanion.utils.log")
local xml2lua = require("codecompanion.utils.xml.xml2lua")

---@class CodeCompanion.Tool
return {
  name = "code_runner",
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
    tool = {
      _attr = { name = "code_runner" },
      lang = "python",
      code = "print('Hello World')",
    },
  },
  ---@param schema table
  env = function(schema)
    local temp_input = vim.fn.tempname()
    local temp_dir = temp_input:match("(.*/)")
    local lang = schema.lang
    local code = schema.code

    return {
      code = code,
      lang = lang,
      temp_dir = temp_dir,
      temp_input = temp_input,
    }
  end,
  system_prompt = function(schema)
    return string.format(
      [[### You have gained access to a new tool!

Name: Code Runner
Purpose: The tool enables you to execute any code that you've created
Why: This enables yourself and the user to validate that the code you've created is working as intended
Usage: To use this tool, you need to return an XML markdown code block (with backticks). Consider the following example which prints 'Hello World' in Python:

```xml
%s
```

You must:
- Only use the tool when prompted by the user. For example "can you update the code for me?" or "can you add ..."
- Be mindful that you may not be required to use the tool in all of your responses
- Ensure the code you're executing will be able to parsed as valid XML
- Ensure the code you're executing is concise
- Ensure the code you're executing is relevant to the conversation
- Ensure the XML markdown code block is valid and follows the schema]],
      xml2lua.toXml({ tools = { schema } })
    )
  end,
  ---@param env table
  ---@param xml table
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
  ---@param error table|string
  output_error_prompt = function(error)
    if type(error) == "table" then
      error = table.concat(error, "\n")
    end
    return string.format(
      [[After the tool completed, there was an error:

```
%s
```

Can you attempt to fix this?]],
      error
    )
  end,
  ---@param output table|string
  output_prompt = function(output)
    if type(output) == "table" then
      output = table.concat(output, "\n")
    end

    return string.format(
      [[After the tool completed the output was:

```
%s
```

Is that what you expected? If it is, just reply with a confirmation. Don't reply with any code. If not, say so and I can plan our next step.]],
      output
    )
  end,
}
