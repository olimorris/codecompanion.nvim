# Tools

In CodeCompanion, tools offer pre-defined ways for LLMs to execute actions and act as an Agent. Tools are added to chat buffers as participants. This guide walks you through the implementation of tools, enabling you to create your own.

## Introduction

In the plugin, tools work by sharing a system prompt with an LLM. This instructs them how to produce an XML markdown code block which can, in turn, be interpreted by the plugin to execute a command or function.

The plugin has a tools class `CodeCompanion.Tools` which will call individual `CodeCompanion.Tool` such as the `code_runner` or the `editor`. The calling of tools is orchestrated by the `CodeCompanion.Chat` class which parses an LLM's response and looks to identify the XML code block.

## Tool Types

There are two types of tools within the plugin:

1. **Command-based**: These tools can execute a series of commands in the background using a `plenary.job`. They're non-blocking, meaning you can carry out other activities in Neovim whilst they run. Useful for heavy/time-consuming tasks.

2. **Function-based**: These tools, like the `editor` one, execute Lua functions directly in Neovim within the main process.

## The Interface

Tools must implement the following interface:

```lua
---@class CodeCompanion.Tool
---@field name string The name of the tool
---@field cmds table The commands to execute
---@field schema table The schema that the LLM must use in its response to execute a tool
---@field system_prompt fun(schema: table): string The system prompt to the LLM explaining the tool and the schema
---@field opts? table The options for the tool
---@field env? fun(xml: table): table|nil Any environment variables that can be used in the *_cmd fields. Receives the parsed schema from the LLM
---@field pre_cmd? fun(env: table, xml: table): table|nil Function to call before the cmd table is executed
---@field output_error_prompt? fun(error: table): string The prompt to share with the LLM if an error is encountered
---@field output_prompt? fun(output: table): string The prompt to share with the LLM if the cmd is successful
---@field request table The request from the LLM to use the Tool
```

### `cmds`

The `cmds` table contains the list of commands or functions that will be executed by the `CodeCompanion.Tools` in succession.

**Command-Based Tools**

The `cmds` table is a collection of commands which the agent will execute one after another. It's also possible to pass in environment variables (from the `env` function) by calling them in `${}` brackets.

The `code_runner` tool is defined as:

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

In this example, the `CodeCompanion.Tools` class will call each table in order and replace the variables with output from the `env` function (more on that below).

**Function-based Tools**

Function-based tools use the `cmds` table to define functions that will be executed one after another:

```lua
  cmds = {
    ---@param self CodeCompanion.Tools The Tools object
    ---@param input any The output from the previous function call
    function(self, input)
      return "Hello, World"
    end,
    ---Ensure the final function returns the status and the output
    ---@param self CodeCompanion.Tools The Tools object
    ---@param input any The output from the previous function call
    ---@return table { status: string, output: string }
    function(self, input)
     print(input) -- prints "Hello, World"
    end,
  }
```

In this example, the first function will be called by the `CodeCompanion.Tools` class and its output will be captured and passed onto the final function call. It should be noted that the last function call in the `cmds` block should return a table with the status (either `success` or `error`) and an output string.

### `schema`

The schema represents the structure of the response that the LLM must follow in order to call the tool.

In the `code_runner` tool, the schema is defined as a Lua table and then converted into XML in the chat buffer:

```lua
schema = {
  name = "code_runner",
  parameters = {
    inputs = {
      lang = "python",
      code = "print('Hello World')",
    },
  },
},
```

### `env`

You can setup environment variables that other functions can access in the `env` function. This function receives the parsed schema which is requested by the LLM when it follows the schema's structure.

For the Code Runner agent, the environment has been setup as:

```lua
---@param schema table
env = function(schema)
  local temp_input = vim.fn.tempname()
  local temp_dir = temp_input:match("(.*/)")
  local lang = schema.parameters.inputs.lang
  local code = schema.parameters.inputs.code

  return {
    code = code,
    lang = lang,
    temp_dir = temp_dir,
    temp_input = temp_input,
  }
end
```

Note that a table has been returned that can then be used in other functions.

### `system_prompt`

In the plugin, LLMs are given knowledge about a tool via a system prompt. This gives the LLM knowledge of the tool alongside the instructions (via the schema) required to execute it.

For the Code Runner agent, the `system_prompt` table is:

````lua
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
- Ensure the code you're executing will be able to parsed as valid XML
- Ensure the code you're executing is safe
- Ensure the code you're executing is concise
- Ensure the code you're executing is relevant to the conversation
- Ensure the code you're executing is not malicious]],
      xml2lua.toXml(schema, "tool")
    )
````

### `pre_cmd`

A `pre_cmd` function can also be used in tools to do some pre-processing prior to the `cmds` table being executed. It receives the `env` table and the LLM's requested `schema`.

### `output_error_prompt`

The `output_error_prompt` is a function that is called by the `CodeCompanion.Tools` class to inform the LLM of an error should it arise from executing one of the cmds in the `cmds` table.

From the `code_runner` tool:

```lua
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
```

### `output_prompt`

Finally, the `output_prompt` function is called by the `CodeCompanion.Tools` class to send a response to the LLM with the output from the tool's execution.

From the `code_runner` tool:

```lua
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
```
