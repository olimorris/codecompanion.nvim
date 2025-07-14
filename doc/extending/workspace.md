# Creating Workspaces

Workspaces act as a context management system for your project. This context sits in a `codecompanion-workspace.json` file in the root of the current working directory. For the purposes of this guide, the file will be referred to as the _workspace file_.

For the origin of workspaces in CodeCompanion, and why I settled on this design, please see the [original](https://github.com/olimorris/codecompanion.nvim/discussions/705) announcement.

## Structure

The workspace file primarily consists of a groups array and data objects. A group defines a specific feature or functionality within the code base, which is made up of a number of individual data objects. These objects are simply a reference to code, which could be in the form of a file, a symbolic outline, or a URL.

The exact JSON schema for a workspace file can be seen [here](https://github.com/olimorris/codecompanion.nvim/blob/main/lua/codecompanion/workspace-schema.json) and below is an extract of CodeCompanion's own workspace file:

```json
{
  "name": "CodeCompanion.nvim",
  "version": "1.0.0",
  "system_prompt": "CodeCompanion.nvim is an AI-powered productivity tool integrated into Neovim, designed to enhance the development workflow by seamlessly interacting with various large language models (LLMs). It offers features like inline code transformations, code creation, refactoring, and supports multiple LLMs such as OpenAI, Anthropic, and Google Gemini, among others. With tools for variable management, agents, and custom workflows, CodeCompanion.nvim streamlines coding tasks and facilitates intelligent code assistance directly within the Neovim editor.",
  "groups": [
    {
      "name": "Chat Buffer",
      "system_prompt": "I've grouped a number of files together into a group I'm calling \"${group_name}\". The chat buffer is a Neovim buffer which allows a user to interact with an LLM. The buffer is formatted as Markdown with a user's content residing under a H2 header. The user types their message, saves the buffer and the plugin then uses Tree-sitter to parse the buffer, extracting the contents and sending to an adapter which connects to the user's chosen LLM. The response back from the LLM is streamed into the buffer under another H2 header. The user is then free to respond back to the LLM.\n\nBelow are the relevant files which we will be discussing:\n\n${group_files}",
      "opts": {
        "remove_config_system_prompt": true
      },
      "data": ["chat-buffer-init", "chat-references", "chat-watchers"]
    },
  ],
  "data": {
    "chat-buffer-init": {
      "type": "file",
      "path": "lua/codecompanion/strategies/chat/init.lua",
      "description": "The `${filename}` file is the entry point for the chat strategy. All methods directly relating to the chat buffer reside here."
    },
    "chat-references": {
      "type": "symbols",
      "path": "lua/codecompanion/strategies/chat/references.lua",
      "description": "References are files, buffers, symbols or URLs that are shared with an LLM to provide additional context. The `${filename}` is where this logic sits and I've shared its symbolic outline below."
    },
    "chat-watchers": {
      "type": "symbols",
      "path": "lua/codecompanion/strategies/chat/watchers.lua",
      "description": "A watcher is when a user has toggled a specific buffer to be watched. When a message is sent to the LLM by the user, any changes made to the watched buffer are also sent, giving the LLM up to date context. The `${filename}` is where this logic sits and I've shared its symbolic outline below."
    },
  }
}
```

- The `system_prompt` value contains the prompt that will be sent to the LLM as a system prompt
- The `groups` array contains the grouping of data that will be shared with the LLM.
- The `data` object contains the files that will be shared as part of the group

When a user leverages the workspace slash command in the chat buffer, the high-level system prompt is added as a message, followed by the system prompt from the group. After that, the individual items in the data array on the group are added along with their descriptions as a regular user prompt.

## Groups

Groups are the core of the workspace file. They are where logical groupings of data are defined. Exploring the _Chat Buffer_ group in detail:

```json
{
  "name": "Chat Buffer",
  "system_prompt": "I've grouped a number of files together into a group I'm calling \"${group_name}\". The chat buffer is a Neovim buffer which allows a user to interact with an LLM. The buffer is formatted as Markdown with a user's content residing under a H2 header. The user types their message, saves the buffer and the plugin then uses Tree-sitter to parse the buffer, extracting the contents and sending to an adapter which connects to the user's chosen LLM. The response back from the LLM is streamed into the buffer under another H2 header. The user is then free to respond back to the LLM.\n\nBelow are the relevant files which we will be discussing:\n\n${group_files}",
  "opts": {
    "remove_config_system_prompt": true
  },
  "data": ["chat-buffer-init", "chat-references", "chat-watchers"]
}
```

There's a lot going on in there:

- Firstly, the `system_prompt` within the group is a way of adding to the main, workspace system prompt
- The `remove_config_system_prompt` is a way of telling the plugin to exclude its own, default system prompt

Let's also explore one of the `data` objects in detail:

```json
{
  "data": {
    "chat-buffer-init": {
      "type": "file",
      "path": "lua/codecompanion/strategies/chat/init.lua",
      "description": "The `${filename}` file is the entry point for the chat strategy. All methods directly relating to the chat buffer reside here."
    }
  }
}
```

- We're specifying a [type](/extending/workspace.html#data-types) of `file` which is explained in more detail below. The type can be one of `file`, `symbols` or `url`
- We're outlining the `path` to the file within the current working directory
- We're providing description which gets sent alongside the contents of the file as part of a user prompt. We're also leveraging a `${filename}` variable which is explained in more detail in the [variables](/extending/workspace.html#variables) section below

## Data Types

### Files

When _files_ are defined, their entire content is shared with the LLM alongside the description. This is useful for files where a deep understanding of how they function is required. Of course, this can consume significant tokens. CodeCompanion will automatically detect if a file is open in Neovim, as a buffer, and load it as such. This makes it more convenient to leverage watchers and pins and keep an LLM updated when you modify the contents.

### Symbols

The plugin uses Tree-sitter [queries](https://github.com/olimorris/codecompanion.nvim/tree/main/queries) to create a symbolic outline of files, capturing:

- Classes, methods, and interfaces
- Function names
- File/library imports
- Start/end lines for each symbol

Alongside the `@files` tool group, the LLM can request specific line ranges from these symbols - a cost-effective alternative to sharing entire files.

### URLs

Workspace files also support the loading of data from URLs. When loading a URL, the `/fetch` slash command adapter retrieves the data. The plugin:

- Caches URL data to disk by default
- Prompts before restoring from cache
- Can be configured with:
  - `"ignore_cache": true` to never use cache
  - `"auto_restore_cache": true` to always use cache without prompting

An example of using the configuration options:

```json
{
  "minitest-docs": {
    "type": "url",
    "path": "https://raw.githubusercontent.com/echasnovski/mini.nvim/refs/heads/main/TESTING.md",
    "description": "Below is the Mini.Test documentation:",
    "opts": {
      "auto_restore_cache": true
    }
  }
}
```


## Variables

A list of all the variables available in workspace files:

- `${workspace_name}` - The name of the workspace file
- `${group_name}` - The name of the group that is being processed by the slash command
- `${filename}` - The name of the current file/symbol that is being processed
- `${cwd}` - The current working directory
- `${path}` - The path to the current file/symbol/url

When building your workspace file, you can create a `vars` object which contains custom variables for use elsewhere in file. For example:

```json
{
  "name": "CodeCompanion.nvim",
  "version": "1.0.0",
  "system_prompt": "Workspace system prompt",
  "vars": {
    "test_desc": "This is a test description",
    "stubs": "tests/stubs"
  },
  "groups": [
    {
      "name": "Test",
      "description": "${test_desc}",
      "system_prompt": "Test group system prompt",
      "data": ["stub-go"]
    }
  ],
  "data": {
    "stub-go": {
      "type": "file",
      "path": "${stubs}/example.go",
      "description": "An example Go file"
    },
  }
}
```

## Generating a Workspace File

The plugin comes with an [Action Palette](/usage/action-palette.html#default-prompts) prompt to help you generate a workspace file. It will open up a chat buffer and add the workspace JSON schema as part of a prompt. It will also determine if you have a workspace file in your current working directory, and if you do, the prompts will be altered to ask the LLM to help you in adding a group, rather than generating a whole workspace file.

Whilst this approach is helpful, you'll still need to manually share a lot of context for the LLM to be able to understand the intricacies of your codebase. A more optimal way is to leverage [VectorCode](https://github.com/Davidyz/VectorCode). The prompt will determine if you have this installed and add it to the chat as a tool.

Remember, the key objective with a workspace file is to rapidly share context with an LLM, making it's response more accurate and more useful.
