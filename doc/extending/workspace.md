# Creating Workspaces

Workspaces act as a context management system for your project. This context sits in a `codecompanion-workspace.json` file in the root of the current working directory. For the purposes of this guide, the file will be referred to as the _workspace file_.

## Structure

Below is an example workspace file for this plugin:

```json
{
  "name": "CodeCompanion.nvim",
  "version": "1.0.0",
  "workspace_spec": "1.0",
  "description": "An example workspace file",
  "system_prompt": "CodeCompanion.nvim is an AI-powered productivity tool integrated into Neovim, designed to enhance the development workflow by seamlessly interacting with various large language models (LLMs). It offers features like inline code transformations, code creation, refactoring, and supports multiple LLMs such as OpenAI, Anthropic, and Google Gemini, among others. With tools for variable management, agents, and custom workflows, CodeCompanion.nvim streamlines coding tasks and facilitates intelligent code assistance directly within the Neovim editor",
  "groups": [
    {
      "name": "Chat Buffer",
      "system_prompt": "...",
      "opts": {
        "remove_config_system_prompt": true
      },
      "files": [
        {
          "description": "...",
          "path": "..."
        }
      ],
      "symbols": [
        {
          "description": "...",
          "path": "..."
        },
      ]
    },
  ]
}
```

- The `description` value contains the high-level description of the workspace file. This is **not** sent to the LLM by default
- The `system_prompt` value contains text that will be sent to the LLM as a system prompt
- The `remove_config_system_prompt` key ensures the plugin's default system prompt (as defined in the user's config) is
removed from the chat buffer
- The `groups` array contains the grouping of files and symbols that can be shared with the LLM. In this example we just have one group, the _Chat Buffer_
- The `version` and `workspace_spec` are currently unused

> [!INFO]
> When a user selects a group to load, the workspace slash command will iterate through the group adding the description first and then sequentially adding the files and symbols. For the latter two, their description is added first, before their content.

### System Prompts

Currently, workspaces allow for system prompts to exist at the top-level of the workspace file and at a group level. The plugin will always insert top-level system prompts at the first index in the messages table in the chat buffer. Any group system prompts will be added afterwards.

## Groups

Groups are the core of the workspace file. They are where logical groupings of files and/or symbols are defined. Exploring the _Chat Buffer_ group in detail:

```json
{
  "name": "Chat Buffer",
  "system_prompt": "I've grouped a number of files together into a group I'm calling \"${group_name}\". The chat buffer is a Neovim buffer which allows a user to interact with an LLM. The buffer is formatted as Markdown with a user's content residing under a H2 header. The user types their message, saves the buffer and the plugin then uses Tree-sitter to parse the buffer, extracting the contents and sending to an adapter which connects to the user's chosen LLM. The response back from the LLM is streamed into the buffer under another H2 header. The user is then free to respond back to the LLM.\n\nBelow are the relevant files which we will be discussing:\n\n${group_files}",
  "description": "You could also add a description here which will be added as a user prompt",
  "opts": {
    "remove_config_system_prompt": true
  },
  "vars": {
    "base_dir": "lua/codecompanion/strategies/chat"
  },
  "files": [
    {
      "description": "The `${filename}` file is the entry point for the chat strategy. All methods directly relating to the chat buffer reside here.",
      "path": "${base_dir}/init.lua"
    }
  ],
  "symbols": [
    {
      "description": "References are files, buffers, symbols or URLs that are shared with an LLM to provide additional context. The `${filename}` is where this logic sits and I've shared its symbolic outline below.",
      "path": "${base_dir}/references.lua"
    },
    {
      "description": "A watcher is when a user has toggled a specific buffer to be watched. When a message is sent to the LLM by the user, any changes made to the watched buffer are also sent, giving the LLM up to date context. The `${filename}` is where this logic sits and I've shared its symbolic outline below.",
      "path": "${base_dir}/watchers.lua"
    }
  ],
  "urls": [
    {
      "ignore_cache": false,
      "description": "The plugin uses Mini.test for its testing. Below is the Mini.Test documentation:",
      "url": "https://raw.githubusercontent.com/echasnovski/mini.nvim/refs/heads/main/TESTING.md"
    },
    {
      "auto_restore_cache": true,
      "description": "I've also included a link to my README:",
      "url": "https://raw.githubusercontent.com/olimorris/codecompanion.nvim/refs/heads/main/doc/codecompanion.txt"
    }
  ],
}
```

There's a lot going on in there:

- Firstly, the `system_prompt` within the group is a way of adding to the main, workspace system prompt
- The `${group_name}` variable provides the name of the current group
- The `${group_files}` variable contains a list of all the files and symbols in the group
- The `vars` object is a way of creating variables that can be referenced throughout the files and symbols arrays
- Each object in the files/symbols array can be a string which defaults to a path, or can be an object containing a
description and the path

### Files

When _files_ are defined, their entire content is shared with the LLM alongside the description. This is useful for files where a deep understanding of how they function is required. Of course, this can consume significant tokens.

### Symbols

The plugin uses Tree-sitter [queries](https://github.com/olimorris/codecompanion.nvim/tree/main/queries) to create a symbolic outline of files, capturing:

- Classes, methods, and interfaces
- Function names
- File/library imports
- Start/end lines for each symbol

By tagging the `files` tool, the LLM can request specific line ranges from these symbols - a cost-effective alternative to sharing entire files.

### URLs

Workspace files support URLs. When loading a URL, the `fetch` adapter retrieves the data. The plugin:

- Caches URL data to disk by default
- Prompts before restoring from cache
- Can be configured with:
  - `"ignore_cache": true` to never use cache
  - `"auto_restore_cache": true` to always use cache without prompting

## Variables

A list of all the variables available in workspace files:

- `${workspace_description}` - The description at the top of the workspace file
- `${workspace_name}` - The name of the workspace file
- `${group_name}` - The name of the group that is being processed by the slash command
- `${group_files}` - A list of all the files and symbols in the group
- `${filename}` - The name of the current file/symbol that is being processed
- `${cwd}` - The current working directory of the workspace file
- `${path}` - The path to the current file/symbol

