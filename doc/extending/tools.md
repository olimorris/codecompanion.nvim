# Creating Tools

In CodeCompanion, tools offer pre-defined ways for LLMs to execute actions and act as an Agent. Tools are added to chat buffers as participants. This guide walks you through the implementation of tools, enabling you to create your own.

## Introduction

In the plugin, tools work by sharing a system prompt with an LLM. This instructs them how to produce an XML markdown code block which can, in turn, be interpreted by the plugin to execute a command or function.

The plugin has a tools class `CodeCompanion.Agent.Tools` which will call tools such as the [@cmd_runner](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/strategies/chat/tools/cmd_runner.lua) or the [@editor](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/strategies/chat/tools/editor.lua). The calling of tools is orchestrated by the `CodeCompanion.Chat` class which parses an LLM's response and looks to identify any XML code blocks.

## Architecture

In order to create tools, you do not need to understand the underlying architecture. However, for those who are curious about the implementation, please see the diagram below:

```mermaid
sequenceDiagram
    participant C as Chat Buffer
    participant L as LLM
    participant A as Agent
    participant E as Tool Executor
    participant T as Tool

    C->>L: Prompt
    L->>C: Response with Tool(s) request

    C->>A: Parse response

    loop For each detected tool
        A<<->>T: Resolve Tool config
        A->>A: Add Tool to queue
    end

    A->>E: Begin executing Tools

    loop While queue not empty
        E<<->>T: Fetch Tool implementation

        E->>E: Setup handlers and output functions
        T<<->>E: handlers.setup()

        alt
        Note over C,E: Some Tools require human approvals
            E->>C: Prompt for approval
            C->>E: User decision
        end


        alt
        Note over E,T: If Tool runs with success
            E<<->>T: output.success()
            T-->>C: Update chat buffer
        else
        Note over E,T: If Tool runs with errors
            E<<->>T: output.error()
            T-->>C: Update chat buffer
        end

        Note over E,T: When Tool completes
        E<<->>T: handlers.on_exit()
    end

    E-->>A: Fire autocmd

    A->>A: reset()
```

## Tool Types

There are two types of tools within the plugin:

1. **Command-based**: These tools can execute a series of commands in the background using a [plenary.job](https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/job.lua). They're non-blocking, meaning you can carry out other activities in Neovim whilst they run. Useful for heavy/time-consuming tasks.

2. **Function-based**: These tools, like the [@editor](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/strategies/chat/tools/editor.lua) one, execute Lua functions directly in Neovim within the main process.

## The Interface

Tools must implement the following interface:

```lua
---@class CodeCompanion.Agent.Tool
---@field name string The name of the tool
---@field cmds table The commands to execute
---@field schema table The schema that the LLM must use in its response to execute a tool
---@field system_prompt fun(schema: table): string The system prompt to the LLM explaining the tool and the schema
---@field opts? table The options for the tool
---@field env? fun(schema: table): table|nil Any environment variables that can be used in the *_cmd fields. Receives the parsed schema from the LLM
---@field handlers table Functions which can be called during the execution of the tool
---@field handlers.setup? fun(self: CodeCompanion.Tools): any Function used to setup the tool. Called before any commands
---@field handlers.approved? fun(self: CodeCompanion.Tools): boolean Function to call if an approval is needed before running a command
---@field handlers.on_exit? fun(self: CodeCompanion.Tools): any Function to call at the end of all of the commands
---@field output? table Functions which can be called after the command finishes
---@field output.rejected? fun(self: CodeCompanion.Tools, cmd: table): any Function to call if the user rejects running a command
---@field output.error? fun(self: CodeCompanion.Tools, cmd: table, error: table|string): any Function to call if the tool is unsuccessful
---@field output.success? fun(self: CodeCompanion.Tools, cmd: table, output: table|string): any Function to call if the tool is successful
---@field request table The request from the LLM to use the Tool
```

### `cmds`

The `cmds` table contains the list of commands or functions that will be executed by the `CodeCompanion.Tools` in succession.

**Command-Based Tools**

The `cmds` table is a collection of commands which the agent will execute one after another, asynchronously, using [plenary.job](https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/job.lua). It's also possible to pass in environment variables (from the `env` function) by calling them in `${}` brackets.

The now removed `code_runner` tool was setup as:

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

Using the `handlers.setup()` function, it's also possible to create commands dynamically like in the `cmd_runner` tool.

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
    ---@return { status: string, msg: string }
    function(self, input)
     print(input) -- prints "Hello, World"
    end,
  }
```

In this example, the first function will be called by the `CodeCompanion.Tools` class and its output will be captured and passed onto the final function call. It should be noted that the last function call in the `cmds` block should return a table with the status (either `success` or `error`) and a msg.

### `schema`

The schema represents the structure of the response that the LLM must follow in order to call the tool.

In the _@coderunner_ tool, the schema was defined as a Lua table and then converted into XML in the chat buffer:

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

For the _@coderunner_ agent, the environment was setup as:

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

For the now archived _@coderunner_ tool, the `system_prompt` table was:

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

### `handlers`

The _handlers_ table consists of two methods:

1. `setup` - Is called before any of the commands/functions are. This is useful if you wish to set the cmds dynamically on the tool itself, like in the _@cmd_runner_ tool.
3. `on_exit` - Is called after all of the commands/function have executed.

### `output`

The _output_ table consists of four methods:

1. `success` - Is called after _every_ successful execution of a command/function. This can be a useful handler to use to notfiy the LLM of the success.
2. `error` - Is called when an error occurs whilst executing a command/function. It will only ever be called once as the whole execution for the group of commands/function is halted. This is a useful handler to use to notify the LLM of the failure.
3. `prompt` - Is called when user approval is required. It forms the message prompt which the user is asked to confirm or reject.
3. `rejected` - Is called when a user rejects the approval to run a command/function. This method is used to inform the LLM of the rejection.

### `request`

The request table is populated at runtime and contains the parsed XML that the LLM has requested to run.

