# Agents

In CodeCompanion, agents offer pre-defined ways for LLMs to execute actions. Agents are added to chat buffers as participants such as with `@code_runner`.

This guide walks you through the implementation of agents, including the default _Code Runner_ agent and the new _Buffer Editor_ agent, to enable you to create your own.

## Agent Types

CodeCompanion supports two types of agents:

1. **Command-based Agents**: These agents, like the Code Runner, use the `cmd`, `env`, `pre_cmd`, and `override_cmds` fields to execute a series of commands external to Neovim.

2. **Function-based Agents**: These agents, like the Buffer Editor, use the `execute` function to perform their actions directly within Neovim.

The choice between these two types depends on the agent's purpose and how it interacts with the system.

## The Agent Interface

Let's take a look at the interface of an agent as per the [agents.lua](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/agents.lua) file:

```lua
---@class CodeCompanion.Agent
---@field cmd table The commands to execute
---@field schema table The schema that the LLM must use in its response to execute a agent
---@field opts? table The options for the agent
---@field system_prompt fun(schema: table): string The system prompt to the LLM explaining the agent and the schema
---@field env fun(xml: table): table|nil Any environment variables that can be used in the *_cmd fields. Receives the parsed schema from the LLM
---@field pre_cmd fun(env: table, xml: table): table|nil Function to call before the cmd table is executed
---@field override_cmds fun(cmds: table): table Function to call to override the default cmds table
---@field output_error_prompt fun(error: table): string The prompt to share with the LLM if an error is encountered
---@field output_prompt fun(output: table): string The prompt to share with the LLM if the cmd is successful
---@field execute fun(chat: CodeCompanion.Chat, inputs: table): CodeCompanion.AgentExecuteResult|nil Function to execute the agent (used by Buffer Editor)
```

Note that the `execute` field is specifically used by the function-based agent's and represents a different approach to agent implementation.

### Command-based Agents (e.g., Code Runner)

Command-based agents use the `cmds` table, which is a collection of commands the agent will execute one after another. These agents typically interact with external systems or run commands in the shell.

For example, the Code Runner agent's `cmds` table is set up as:

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

### Function-based Agents (e.g., Buffer Editor)

Function-based agents use the `execute` function to perform their actions. This approach is more suitable for agents that need to interact directly with Neovim buffers or perform complex operations that are not easily expressed as a series of shell commands.

The Buffer Editor agent, for example, uses this approach to directly modify Neovim buffers based on the LLM's instructions.

## Implementing a New Agent

When creating a new agent, you need to decide which implementation type is more suitable:

1. For agents that primarily run external commands or scripts, use the command-based approach.
2. For agents that need to interact closely with Neovim or perform complex in-editor operations, use the function-based approach.

Regardless of the implementation type, all agents need to provide:

- A `schema` defining the structure of the LLM's response
- A `system_prompt` function to instruct the LLM on how to use the agent
- Both `output_error_prompt` and `output_prompt` functions to handle communication with the LLM

## Config

### Schema

The schema represents the structure of the response that the LLM must follow in order to enable the agent to be called.

In the Code Runner agent, the schema is defined as a Lua table and then converted into XML in the chat buffer:

```lua
schema = {
  agent = {
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

### System Prompt

In the plugin, LLMs are given knowledge about an agent via a system prompt. This gives the LLM knowledge of the agent alongside the instructions (via the schema) required to execute it.

For the Code Runner agent, the `system_prompt` table is:

````lua
system_prompt = function(schema)
  return "I'm giving you access to the **Code Runner** agent which enables you to run any code that you've created. You can write code and using the agent, trigger its execution and immediately see the output. This is useful to see if the code worked as you intended. Of course, not every question I ask you will need the agent so bear that in mind.\n\nTo use the agent, you need to return an XML markdown code block (with backticks) which follows the below schema:"
    .. "\n\n```xml\n"
    .. xml2lua.toXml(schema, "agent")
    .. "\n```\n\n"
    .. "You can see that the schema has input parameters where you can specify the language (e.g. Python) and the code you'd like to run.\n\n"
    .. "NOTE: If you don't conform to the schema, EXACTLY, then the agent will not run."
end
````

### Env

You can setup environment variables that other functions can access in the `env` function. This function receives the parsed XML which is returned by the LLM when it follows the schema's structure.

For the Code Runner agent, the environment has been setup as:

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

The `cmds` table is a collection of commands which the agent will execute one after another. It's also possible to pass in environment variables (from the `env` function) by calling them in `${}` brackets.

For the Code Runner agent, the `cmds` table has been setup as:

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

In this example, the agent will pull a docker image down as the first step, using the `lang` environment variable. Before calling the `docker run` command.

### Override Cmds

If you wish to override any of the default commands, the `override_cmds` function can be called, returning a table.

### Pre Cmds

A `pre_cmd` function can also be used in agents to do some pre-processing prior to the `cmds` table being executed. It receives the `env` table and al

### Execute

The `execute` function is used by the Function-based agents to perform their actions. This function receives the chat object and the inputs table.
