# Using Slash Commands

<p>
  <img src="https://github.com/user-attachments/assets/02b4d5e2-3b40-4044-8a85-ccd6dfa6d271" />
</p>

Slash Commands enable you to quickly add context to the chat buffer. They are comprised of values present in the `strategies.chat.slash_commands` table alongside the `prompt_library` table where individual prompts have `opts.is_slash_cmd = true`.

## /buffer

<p>
<img src="https://github.com/user-attachments/assets/1be7593b-f77f-44f9-a418-1d04b3f46785" />
</p>

> [!NOTE]
> As of [v16.2.0](https://github.com/olimorris/codecompanion.nvim/releases/tag/v16.2.0), buffers are now watched by default

The _buffer_ slash command enables you to add the contents of any open buffers in Neovim to the chat buffer. The command has native, _Telescope_, _mini.pick_, _fzf.lua_ and _snacks.nvim_ providers available. Also, multiple buffers can be selected and added to the chat buffer as per the video above.

## /fetch

> [!TIP]
> To better understand a Neovim plugin, send its `config.lua` to your LLM via the _fetch_ command alongside a prompt

The _fetch_ slash command allows you to add the contents of a URL to the chat buffer. By default, the plugin uses the awesome and powerful [jina.ai](https://jina.ai) to parse the page's content and convert it into plain text. For convenience, the slash command will cache the output to disk and prompt the user if they wish to restore from the cache, should they look to fetch the same URL.

## /file

<p>
  <video controls muted src="https://github.com/user-attachments/assets/3359c752-e5e0-41bf-8952-557edf11efdf"></video>
</p>

The _file_ slash command allows you to add the contents of a file in the current working directory to the chat buffer. The command has native, _Telescope_, _mini.pick_, _fzf.lua_ and _snacks.nvim_ providers available. Also, multiple files can be selected and added to the chat buffer:

- Select a single file: `⏎ enter`
- Select multiple files: `⇥ tab`

Please note that these mappings may be different depending on your provider.

## /quickfix

The `quickfix` slash command adds entries from the Neovim quickfix list to the chat buffer.

- For search patterns or file entries, the whole file is shared.
- For diagnostics, the context of the function/method/class is shared if possible; otherwise, 10 lines around the diagnostic are included.

## /help

The _help_ slash command allows you to add content from a vim help file (`:h helpfile`), to the chat buffer, by searching for help tags. Currently this is only available for _Telescope_, _mini.pick_, _fzf_lua_ and _snacks.nvim_ providers. By default, the slash command will prompt you to trim a help file that is over 1,000 lines in length.

## /image

The _image_ slash command allows you to add images into a chat buffer via remote URLs and through your file system. In the config for the slash command, you can specify a group of directories (with `opts.dirs`) that the image picker will always search in, alongside the current working directory. Currently the image picker is only available with _snacks.nvim_ and the `vim.ui.select`.

## /now

The _now_ slash command simply inserts the current datetime stamp into the chat buffer.

## /symbols

> [!NOTE]
> If a filetype isn't supported please consider making a PR to add the corresponding Tree-sitter queries from
> [aerial.nvim](https://github.com/stevearc/aerial.nvim)

The _symbols_ slash command uses Tree-sitter to create a symbolic outline of a file to share with the LLM. This can be a useful way to minimize token consumption whilst sharing the basic outline of a file. The plugin utilizes the amazing work from **aerial.nvim** by using their Tree-sitter symbol queries as the basis. The list of filetypes that the plugin currently supports can be found [here](https://github.com/olimorris/codecompanion.nvim/tree/main/queries).

The command has native, _Telescope_, _mini.pick_, _fzf.lua_ and _snacks.nvim_ providers available. Also, multiple symbols can be selected and added to the chat buffer.

## /terminal

The _terminal_ slash command shares the latest output from the last terminal buffer with the chat buffer. This can be useful for sharing the outputs of test runs with your LLM.

## /workspace

The _workspace_ slash command allows users to share defined groups of files and/or symbols with an LLM, alongside some pre-written context. The slash command uses a [codecompanion-workspace.json](https://github.com/olimorris/codecompanion.nvim/blob/main/codecompanion-workspace.json) file, stored in the current working directory, to house this context. It is, in essence, a context management system for your repository.

Whilst LLMs are incredibly powerful, they have no knowledge of the architectural decisions yourself or your team have made on a project. They have no context as to why you've selected the dependencies that you have. And, they can't see how your codebase has evolved over time. To help you create your own workspace file, leverage the [workspace file](/usage/action-palette.html#default-prompts) prompt in the action palette and install the amazing [VectorCode](https://github.com/Davidyz/VectorCode/tree/main) tool.

Please see the [Creating Workspaces](/extending/workspace) guide to learn how to build your own.
