# Tools

In CodeCompanion, tools offer pre-defined ways for LLMs to execute actions. This guide walks you through the implementation of the default _Code Runner_ tool to enable you to create your own.

## The Tool Interface

Let's take a look at the interface of a tool as per the `code_runner.lua` file:

```lua
---@class CodeCompanion.Tool
---@field cmd table The commands to execute
---@field schema string The schema that the LLM must use in its response to execute a tool
---@field prompts table The prompts to the LLM explaining the tool and the schema
---@field env fun(xml: table): table|nil Any environment variables that can be used in the *_cmd fields. Receives the parsed schema from the LLM
---@field pre_cmd fun(env: table, xml: table): table|nil Function to call before the cmd table is executed
---@field override_cmds fun(cmds: table): table Function to call to override the default cmds table
---@field output_error_prompt fun(error: table): string The prompt to share with the LLM if an error is encountered
---@field output_prompt fun(output: table): string The prompt to share with the LLM if the cmd is successful
```

Hopefully the fields should be self-explanatory but we'll investigate how they're used in the Code Runner tool in the next sections.

### Schema

The schema represents the structure of the response that the LLM must follow in order to enable the tool to be called.

In the Code Runner tool, the schema is defined as a Lua table and then converted into XML in the chat buffer:

```lua
schema = {
  tool = {
    name = "code_runner",
    parameters = {
      inputs = {
        lang = "python",
        code = "print('Hello World')",
      },
    },
  },
},
```

If the LLM outputs a markdown XML block as per the schema, the plugin will parse it and duly execute the code.

### Prompts

In the plugin, tools are shared with the LLM via a system prompt. This gives the LLM knowledge of the tool and instructions (via the schema) on how to utilize it.

For the Code Runner tool, the prompts table is:

```lua
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
```

### Env

You can setup environment variables that other functions can access in the `env` function. This function receives the parsed XML which is returned by the LLM when it follows the schema's structure.

For the Code Runner tool, the environment has been setup as:

```lua
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
end
```

Note that a table has been returned that can then be used in other functions.

### Cmds

The `cmds` table is a collection of commands which the tool will execute one after another. It's also possible to pass in environment variables (from the `env` function) by calling them in `${}` brackets.

For the Code Runner tool, the `cmds` table has been setup as:

```lua
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
}
```

In this example, the tool will pull a docker image down as the first step, using the `lang` environment variable. Before calling the `docker run` command.

### Override Cmds

If you wish to override any of the default commands, the `override_cmds` function can be called, returning a table.

### Pre Cmds

A `pre_cmd` function can also be used in tools to do some pre-processing prior to the `cmds` table being executed. It receives the `env` table and also the parsed XML from the LLM.

For the Code Runner tool, the `pre_cmd` has been setup as:

```lua
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
end
```

### Output Error Prompt

There may be instances when the command executes with an error. This can be fed back to the LLM via the `output_error_prompt` function which outputs a string.

For the Code Runner tool, the `output_error_prompt` has been setup as:

```lua
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
```

By default, the plugin will *not* automatically send this to the LLM for feedback, in order to avoid an expensive loop. However, this can be enabled by changing `tools.opts.auto_submit_errors = true` in the config.

### Output Prompt

Finally, the `output_prompt` function can be used to customise the prompt back to the LLM with the response from the tool. It must output a string.

For the Code Runner tool, the `output_prompt` has been setup as:

```lua
output_prompt = function(output)
  if type(output) == "table" then
    output = table.concat(output, "\n")
  end

  return "After the tool completed the output was:"
    .. "\n\n```\n"
    .. output
    .. "\n```\n\n"
    .. "Is that what you expected? If it is, just reply with a confirmation. Don't reply with any code. If not, say so and I can plan our next step."
end
```

## Config

To enable a tool in your config:

```lua
tools = {
  ["code_runner"] = {
    name = "Code Runner",
    description = "Run code generated by the LLM",
    enabled = true,
    location = "codecompanion.tools"
  },
}
```

The `location` key resolves to `codecompanion.tools.code_runner` in the case of the example above. This allows you to point to tools locally on your machine.
