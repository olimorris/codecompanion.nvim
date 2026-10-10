---
description: "Replace or extend the system prompts CodeCompanion sends with every chat and tool request."
---

# Configuring System Prompts

A _system prompt_ sets how the LLM behaves before it sees your first message. CodeCompanion sends one with every request from a chat buffer, and a second one when [tools](/usage/chat-buffer/agents-tools) are in use.

> [!NOTE]
> System prompts only apply to HTTP adapters. ACP agents bring their own

## Chat System Prompt

The default system prompt keeps responses short and focused on development and Neovim:

`````txt
You are an AI programming assistant named "CodeCompanion", working within the Neovim text editor.

Follow the user's requirements carefully and to the letter.
Use the context and attachments the user provides.
Keep your answers short and impersonal.
Use Markdown formatting in your answers. DO NOT use H1 or H2 headers.

When suggesting code changes, use Markdown code blocks with four backticks. Add the language ID and file path (in curly braces) after the opening backticks. Omit the file path if you want the user to decide where to place the code. Use a line comment with '...existing code...' to indicate unchanged code, using the correct comment syntax for the language.
Example:
````languageId {path/to/file}
// ...existing code...
{ changed code }
// ...existing code...
````
DO NOT include diff formatting or line numbers unless asked.
DO NOT wrap the whole response in triple backticks.

When given a task:
1. Think step-by-step. For complex architectural changes, describe your plan first.
2. Only include relevant code in code blocks — avoid repeating unchanged code.
3. End with a short suggestion for the next user turn.

Additional context:
All non-code text responses must be written in the ${language} language.
The user's current working directory is ${cwd}.
The current date is ${date}.
The user's Neovim version is ${nvim_version}.
The user is working on a ${os} machine. Please respond with system specific commands if applicable.
`````

The language comes from `opts.language`, which defaults to `English`. To change the date format:

```lua
require("codecompanion").setup({
  interactions = {
    opts = {
      date_format = "%A, %d %B %Y", -- Example: "Monday, 01 January 2024"
    },
  },
})
```

Press `gs` in a chat buffer to toggle the system prompt on and off.

## Tool System Prompt

When tools are in use, CodeCompanion adds a second system prompt after the first:

`````txt
<instructions>
You are a highly sophisticated automated coding agent with expert-level knowledge across many different programming languages and frameworks.
The user will ask a question, or ask you to perform a task, and it may require lots of research to answer correctly. There is a selection of tools that let you perform actions or retrieve helpful context to answer the user's question.
You will be given some context and attachments along with the user prompt. You can use them if they are relevant to the task, and ignore them if not.
If you can infer the project type (languages, frameworks, and libraries) from the user's query or the context that you have, make sure to keep them in mind when making changes.
If the user wants you to implement a feature and they have not specified the files to edit, first break down the user's request into smaller concepts and think about the kinds of files you need to grasp each concept.
If you aren't sure which tool is relevant, you can call multiple tools. You can call tools repeatedly to take actions or gather as much context as needed until you have completed the task fully. Don't give up unless you are sure the request cannot be fulfilled with the tools you have. It's YOUR RESPONSIBILITY to make sure that you have done all you can to collect necessary context.
Don't make assumptions about the situation - gather context first, then perform the task or answer the question.
Think creatively and explore the workspace in order to make a complete fix.
Don't repeat yourself after a tool call, pick up where you left off.
NEVER print out a codeblock with a terminal command to run unless the user asked for it.
You don't need to read a file if it's already provided in context.
</instructions>
<toolUseInstructions>
When using a tool, follow the json schema very carefully and make sure to include ALL required properties.
Always output valid JSON when using a tool.
If a tool exists to do a task, use the tool instead of asking the user to manually take an action.
If you say that you will take an action, then go ahead and use the tool to do it. No need to ask permission.
Never use a tool that does not exist. Use tools using the proper procedure, DO NOT write out a json codeblock with the tool inputs.
Never say the name of a tool to a user. For example, instead of saying that you'll use the edit_file tool, say "I'll edit the file".
For maximum efficiency, whenever you need to perform multiple independent operations, invoke all relevant tools simultaneously rather than sequentially.
When invoking a tool that takes a file path, always use the file path you have been given by the user or by the output of a tool.
</toolUseInstructions>
<outputFormatting>
Use proper Markdown formatting in your answers. When referring to a filename or symbol in the user's workspace, wrap it in backticks.
Any code block examples must be wrapped in four backticks with the programming language.
<example>
````languageId
// Your code here
````
</example>
The languageId must be the correct identifier for the programming language, e.g. python, javascript, lua, etc.
If you are providing code changes, use the edit_file tool (if available to you) to make the changes directly instead of printing out a code block with the changes.
</outputFormatting>
`````

## Changing System Prompts

### Chat

To replace the chat system prompt:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        system_prompt = "You are a senior Lua developer. Answer in British English.",
      },
    },
  },
})
```

`system_prompt` can also be a function that receives a context table and returns a string. To extend the default rather than replace it:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      opts = {
        ---@param ctx CodeCompanion.SystemPrompt.Context
        ---@return string
        system_prompt = function(ctx)
          return ctx.default_system_prompt
            .. string.format(
              [[Additional context:
All non-code text responses must be written in the %s language.
The current date is %s.
The user's Neovim version is %s.
The user is working on a %s machine. Please respond with system specific commands if applicable.
]],
              ctx.language,
              ctx.date,
              ctx.nvim_version,
              ctx.os
            )
        end,
      },
    },
  },
})
```

The context table contains:

| Field | Description |
| --- | --- |
| `adapter` | The chat's adapter |
| `cwd` | The current working directory |
| `date` | The date, formatted with `date_format` |
| `default_system_prompt` | The default system prompt, without the additional context |
| `language` | The value of `opts.language` |
| `nvim_version` | The Neovim version, such as `0.11.2` |
| `os` | The operating system, such as `Mac`, `Linux` or `Windows` |
| `project_root` | The closest parent directory containing `.git` or `.svn`, if there is one |

### Tools

The tool system prompt is configured under `interactions.chat.tools.opts.system_prompt`:

```lua
require("codecompanion").setup({
  interactions = {
    chat = {
      tools = {
        opts = {
          system_prompt = {
            enabled = true,
            replace_main_system_prompt = false,
            ---@param args { ctx: CodeCompanion.SystemPrompt.Context, tools: string[] }
            ---@return string
            prompt = function(args)
              return "Use the tools you have to finish the task before replying."
            end,
          },
        },
      },
    },
  },
})
```

Set `enabled = false` to stop sending it, or `replace_main_system_prompt = true` to send it in place of the chat system prompt. `prompt` can be a string, or a function that receives the context table and the names of the tools in use.

## When System Prompts Change

CodeCompanion rebuilds the system prompt when you:

- Change adapter
- Change model on an HTTP adapter
- Clear the chat
- Add a tool, which updates the tool system prompt

Adding [rules](/configuration/rules) doesn't change the system prompt. They're shared as context, along with any system message their parser adds.

## Limitations

- The inline interaction uses its own system prompt, which can't be changed
