local providers = require("codecompanion.providers")
local ui_utils = require("codecompanion.utils.ui")

local fmt = string.format

local constants = {
  LLM_ROLE = "llm",
  USER_ROLE = "user",
  SYSTEM_ROLE = "system",
}

local defaults = {
  adapters = {
    http = {
      anthropic = "anthropic",
      azure_openai = "azure_openai",
      copilot = "copilot",
      deepseek = "deepseek",
      gemini = "gemini",
      githubmodels = "githubmodels",
      huggingface = "huggingface",
      novita = "novita",
      mistral = "mistral",
      ollama = "ollama",
      openai = "openai",
      openai_responses = "openai_responses",
      xai = "xai",
      jina = "jina",
      tavily = "tavily",
      opts = {
        allow_insecure = false, -- Allow insecure connections?
        cache_models_for = 1800, -- Cache adapter models for this long (seconds)
        proxy = nil, -- [protocol://]host[:port] e.g. socks5://127.0.0.1:9999
        show_presets = true, -- Show preset adapters
        show_model_choices = true, -- Show model choices when changing adapter
      },
    },
    acp = {
      auggie_cli = "auggie_cli",
      cagent = "cagent",
      claude_code = "claude_code",
      codex = "codex",
      gemini_cli = "gemini_cli",
      goose = "goose",
      kimi_cli = "kimi_cli",
      kiro = "kiro",
      mistral_vibe = "mistral_vibe",
      opencode = "opencode",
      opts = {
        show_presets = true,
      },
    },
    opts = {
      cmd_timeout = 20e3, -- Timeout for commands that resolve env variables (milliseconds)
    },
  },
  constants = constants,
  interactions = {
    -- BACKGROUND INTERACTION -------------------------------------------------
    background = {
      adapter = {
        name = "copilot",
        model = "gpt-4.1",
      },
      -- Callbacks within the plugin that you can attach background actions to
      chat = {
        callbacks = {
          ["on_ready"] = {
            actions = {
              "interactions.background.builtin.chat_make_title",
            },
            enabled = true,
          },
        },
        opts = {
          enabled = false, -- Enable ALL background chat interactions?
        },
      },
    },
    -- CHAT INTERACTION -------------------------------------------------------
    chat = {
      adapter = "copilot",
      roles = {
        ---The header name for the LLM's messages
        ---@type string|fun(adapter: CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter): string
        llm = function(adapter)
          return "CodeCompanion (" .. adapter.formatted_name .. ")"
        end,

        ---The header name for your messages
        ---@type string
        user = "Me",
      },
      tools = {
        groups = {
          ["agent"] = {
            description = "Agent - Can run code, edit code and modify files on your behalf",
            system_prompt = function(group, ctx)
              return string.format(
                [[<instructions>
You are an expert AI coding agent, working with a user in Neovim. You have expert-level knowledge across many programming languages, frameworks and software engineering tasks including debugging, implementing features, refactoring code and providing explanations.
By default, implement changes rather than only suggesting them. When a tool call is intended, make it happen rather than describing it. If the user's intent is unclear, infer the most useful likely action and use tools to discover any missing details instead of guessing.
If you can infer the project type (languages, frameworks and libraries) from the user's query or the context that you have, keep them in mind when making changes.
If the user wants you to implement a feature and they have not specified the files to edit, first break down the request into smaller concepts and think about the kinds of files you need to grasp each concept.
If you aren't sure which tool is relevant, you can call multiple tools. You can call tools repeatedly to take actions or gather as much context as needed until you have completed the task fully. Don't give up unless you are sure the request cannot be fulfilled with the tools you have. It's YOUR RESPONSIBILITY to make sure that you have done all you can to collect necessary context.
Don't make assumptions about the situation - gather context first, then perform the task or answer the question. Think creatively and explore the workspace in order to make a complete fix.
Continue working until the user's request is completely resolved before ending your turn. Do not stop when you encounter uncertainty - research or deduce the most reasonable approach and continue.
After making changes, verify your work by reading the modified files or running relevant commands when appropriate.
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
Never say the name of a tool to a user. For example, instead of saying that you'll use the insert_edit_into_file tool, say "I'll edit the file".
If you think running multiple tools can answer the user's question, prefer calling them in parallel whenever possible.
When invoking a tool that takes a file path, always use the file path you have been given by the user or by the output of a tool.
</toolUseInstructions>
<outputFormatting>
Keep responses concise. After completing file operations, confirm briefly rather than explaining what was done. Match response length to task complexity.
Use proper Markdown formatting in your answers. When referring to a filename or symbol in the user's workspace, wrap it in backticks.
Any code block examples must be wrapped in four backticks with the programming language.
<example>
````languageId
// Your code here
````
</example>
The languageId must be the correct identifier for the programming language, e.g. python, javascript, lua, etc.
If you are providing code changes, use the insert_edit_into_file tool (if available to you) to make the changes directly instead of printing out a code block with the changes.
</outputFormatting>
<additionalContext>
All non-code text responses must be written in the %s language.
The user's current working directory is %s.
The current date is %s.
The user's Neovim version is %s.
The user is working on a %s machine. Please respond with system specific commands if applicable.
</additionalContext>]],
                ctx.language,
                ctx.cwd,
                ctx.date,
                ctx.nvim_version,
                ctx.os
              )
            end,
            tools = {
              "ask_questions",
              "create_file",
              "delete_file",
              "file_search",
              "get_changed_files",
              "get_diagnostics",
              "grep_search",
              "insert_edit_into_file",
              "read_file",
              "run_command",
            },
            opts = {
              collapse_tools = true,
              ignore_system_prompt = true,
              ignore_tool_system_prompt = true,
            },
          },
          ["files"] = {
            description = "Tools related to creating, reading and editing files",
            prompt = "I'm giving you access to ${tools} to help you perform file operations",
            tools = {
              "create_file",
              "delete_file",
              "file_search",
              "get_changed_files",
              "grep_search",
              "insert_edit_into_file",
              "read_file",
            },
            opts = {
              collapse_tools = true,
            },
          },
        },
        -- Tools
        ["ask_questions"] = {
          path = "interactions.chat.tools.builtin.ask_questions",
          description = "Ask the user questions to clarify requirements or validate assumptions",
          visible = false,
        },
        ["create_file"] = {
          path = "interactions.chat.tools.builtin.create_file",
          description = "Create a file in the current working directory",
          opts = {
            require_approval_before = true,
          },
        },
        ["delete_file"] = {
          path = "interactions.chat.tools.builtin.delete_file",
          description = "Delete a file in the current working directory",
          opts = {
            allowed_in_yolo_mode = false,
            require_approval_before = true,
          },
        },
        ["fetch_webpage"] = {
          path = "interactions.chat.tools.builtin.fetch_webpage",
          description = "Fetches content from a webpage",
          opts = {
            adapter = "jina",
          },
        },
        ["file_search"] = {
          path = "interactions.chat.tools.builtin.file_search",
          description = "Search for files in the current working directory by glob pattern",
          opts = {
            max_results = 500,
          },
        },
        ["get_changed_files"] = {
          path = "interactions.chat.tools.builtin.get_changed_files",
          description = "Get git diffs of current file changes in a git repository",
          opts = {
            max_lines = 1000,
          },
        },
        ["get_diagnostics"] = {
          path = "interactions.chat.tools.builtin.get_diagnostics",
          description = "Get LSP diagnostics for a given file",
        },
        ["grep_search"] = {
          path = "interactions.chat.tools.builtin.grep_search",
          enabled = function()
            -- Currently this tool only supports ripgrep
            return vim.fn.executable("rg") == 1
          end,
          description = "Search for text in the current working directory",
          opts = {
            max_results = 100,
            respect_gitignore = true,
            require_approval_before = true,
          },
        },
        ["insert_edit_into_file"] = {
          path = "interactions.chat.tools.builtin.insert_edit_into_file",
          description = "Robustly edit existing files with multiple automatic fallback interactions",
          opts = {
            require_approval_before = { -- Require approval before the tool is executed?
              buffer = false, -- For editing buffers in Neovim
              file = false, -- For editing files in the current working directory
            },
            require_confirmation_after = true, -- Require confirmation from the user before accepting the edit?
            file_size_limit_mb = 2, -- Maximum file size in MB
          },
        },
        ["memory"] = {
          path = "interactions.chat.tools.builtin.memory",
          description = "The memory tool enables LLMs to store and retrieve information across conversations through a memory file directory",
          opts = {
            require_approval_before = true,
          },
        },
        ["next_edit_suggestion"] = {
          path = "interactions.chat.tools.builtin.next_edit_suggestion",
          description = "Suggest and jump to the next position to edit",
        },
        ["read_file"] = {
          path = "interactions.chat.tools.builtin.read_file",
          description = "Read a file in the current working directory",
          opts = {
            require_approval_before = true,
          },
        },
        ["run_command"] = {
          path = "interactions.chat.tools.builtin.run_command",
          description = "Run shell commands initiated by the LLM",
          opts = {
            allowed_in_yolo_mode = false,
            require_approval_before = true,
            require_cmd_approval = true,
          },
        },

        ["web_search"] = {
          path = "interactions.chat.tools.builtin.web_search",
          description = "Search the web for information",
          opts = {
            adapter = "tavily", -- tavily
            opts = {
              -- Tavily options
              search_depth = "advanced",
              topic = "general",
              chunks_per_source = 3,
              max_results = 5,
            },
          },
        },
        opts = {
          auto_submit_errors = true, -- Send any errors to the LLM automatically?
          auto_submit_success = true, -- Send any successful output to the LLM automatically?
          folds = {
            enabled = true, -- Fold tool output in the buffer?
            failure_words = { -- Words that indicate an error in the tool output. Used to apply failure highlighting
              "cancelled",
              "error",
              "failed",
              "incorrect",
              "invalid",
              "rejected",
            },
          },
          ---Tools and/or groups that are always loaded in a chat buffer
          ---@type string[]
          default_tools = {},

          system_prompt = {
            enabled = true, -- Enable the tools system prompt?
            replace_main_system_prompt = false, -- Replace the main system prompt with the tools system prompt?

            ---The tool system prompt
            ---@param args { tools: string[]} The tools available
            ---@return string
            prompt = function(args)
              return [[<instructions>
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
Never say the name of a tool to a user. For example, instead of saying that you'll use the insert_edit_into_file tool, say "I'll edit the file".
If you think running multiple tools can answer the user's question, prefer calling them in parallel whenever possible.
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
If you are providing code changes, use the insert_edit_into_file tool (if available to you) to make the changes directly instead of printing out a code block with the changes.
</outputFormatting>]]
            end,
          },

          tool_replacement_message = "the ${tool} tool", -- The message to use when replacing tool names in the chat buffer
        },
      },
      editor_context = {
        opts = {
          excluded = {
            buftypes = {
              "nofile",
              "quickfix",
              "prompt",
              "popup",
            },
            fts = {
              "codecompanion",
              "help",
              "terminal",
            },
          },
        },
        ["buffer"] = {
          path = "interactions.chat.editor_context.buffer",
          description = "Share the current buffer with the LLM",
          opts = {
            contains_code = true,
            default_params = "diff", -- all|diff
            has_params = true,
          },
        },
        ["buffers"] = {
          path = "interactions.chat.editor_context.buffers",
          description = "Share all open buffers with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["diagnostics"] = {
          path = "interactions.chat.editor_context.diagnostics",
          description = "Share diagnostics and code for the current buffer",
          opts = {
            contains_code = true,
          },
        },
        ["diff"] = {
          path = "interactions.chat.editor_context.diff",
          description = "Share the current git diff with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["messages"] = {
          path = "interactions.chat.editor_context.messages",
          description = "Share Neovim's message history with the LLM",
        },
        ["quickfix"] = {
          path = "interactions.chat.editor_context.quickfix",
          description = "Share the quickfix list with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["selection"] = {
          path = "interactions.chat.editor_context.selection",
          description = "Share the current visual selection with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["terminal"] = {
          path = "interactions.chat.editor_context.terminal",
          description = "Share the latest terminal output with the LLM",
        },
        ["viewport"] = {
          path = "interactions.chat.editor_context.viewport",
          description = "Share the code that you see in Neovim with the LLM",
          opts = {
            contains_code = true,
          },
        },
      },
      slash_commands = {
        ["buffer"] = {
          path = "interactions.chat.slash_commands.builtin.buffer",
          description = "Insert open buffers",
          opts = {
            contains_code = true,
            default_params = "diff", -- all|diff
            provider = providers.pickers, -- telescope|fzf_lua|mini_pick|snacks|default
          },
        },
        ["command"] = {
          path = "interactions.chat.slash_commands.builtin.command",
          description = "Change the command used to start the ACP adapter",
          ---@param opts { adapter: CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter }
          ---@return boolean
          enabled = function(opts)
            if opts.adapter and opts.adapter.type == "acp" then
              return true
            end
            return false
          end,
          opts = {
            contains_code = false,
          },
        },
        ["compact"] = {
          path = "interactions.chat.slash_commands.builtin.compact",
          description = "Clears some of the chat history, keeping a summary in context",
          enabled = function(opts)
            if opts.adapter and opts.adapter.type == "http" then
              return true
            end
            return false
          end,
          opts = {
            contains_code = false,
          },
        },
        ["fetch"] = {
          path = "interactions.chat.slash_commands.builtin.fetch",
          description = "Insert URL contents",
          opts = {
            adapter = "jina", -- jina
            cache_path = vim.fn.stdpath("data") .. "/codecompanion/urls",
            provider = providers.pickers, -- telescope|fzf_lua|mini_pick|snacks|default
          },
        },
        ["file"] = {
          path = "interactions.chat.slash_commands.builtin.file",
          description = "Insert a file",
          opts = {
            contains_code = true,
            max_lines = 1000,
            provider = providers.pickers, -- telescope|fzf_lua|mini_pick|snacks|default
          },
        },
        ["help"] = {
          path = "interactions.chat.slash_commands.builtin.help",
          description = "Insert content from help tags",
          opts = {
            contains_code = false,
            max_lines = 128, -- Maximum amount of lines to of the help file to send (NOTE: Each vimdoc line is typically 10 tokens)
            provider = providers.help, -- telescope|fzf_lua|mini_pick|snacks
          },
        },
        ["image"] = {
          path = "interactions.chat.slash_commands.builtin.image",
          description = "Insert an image",
          ---@param opts { adapter: CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter }
          ---@return boolean
          enabled = function(opts)
            if opts.adapter and opts.adapter.opts then
              return opts.adapter.opts.vision == true
            end
            return false
          end,
          opts = {
            dirs = {}, -- Directories to search for images
            filetypes = { "png", "jpg", "jpeg", "gif", "webp" }, -- Filetypes to search for
            provider = providers.images, -- telescope|snacks|default
          },
        },
        ["mcp"] = {
          path = "interactions.chat.slash_commands.builtin.mcp",
          description = "Toggle MCP servers",
          opts = {
            contains_code = false,
            provider = "default", -- snacks|default
          },
        },
        ["mode"] = {
          path = "interactions.chat.slash_commands.builtin.mode",
          description = "Change the ACP session mode",
          ---@param opts { adapter: CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter }
          ---@return boolean
          enabled = function(opts)
            if opts.adapter and opts.adapter.type == "acp" then
              return true
            end
            return false
          end,
          opts = {
            contains_code = false,
          },
        },
        ["now"] = {
          path = "interactions.chat.slash_commands.builtin.now",
          description = "Insert the current date and time",
          opts = {
            contains_code = false,
          },
        },
        ["rules"] = {
          path = "interactions.chat.slash_commands.builtin.rules",
          description = "Insert rules into the chat buffer",
          opts = {
            contains_code = true,
          },
        },
        ["symbols"] = {
          path = "interactions.chat.slash_commands.builtin.symbols",
          description = "Insert symbols for a selected file",
          opts = {
            contains_code = true,
            provider = providers.pickers, -- telescope|fzf_lua|mini_pick|snacks|default
          },
        },
        opts = {
          acp = {
            enabled = true, -- Enable ACP command completion
          },
        },
      },
      keymaps = {
        options = {
          modes = { n = "?" },
          callback = "keymaps.options",
          description = "Options",
          hide = true,
        },
        completion = {
          modes = { i = "<C-_>" },
          index = 1,
          callback = "keymaps.completion",
          description = "[Chat] Completion menu",
        },
        send = {
          modes = {
            n = { "<CR>", "<C-s>" },
            i = "<C-s>",
          },
          index = 2,
          callback = "keymaps.send",
          description = "[Request] Send response",
        },
        regenerate = {
          modes = { n = "gr" },
          index = 3,
          callback = "keymaps.regenerate",
          description = "[Request] Regenerate",
        },
        close = {
          modes = {
            n = "<C-c>",
            i = "<C-c>",
          },
          index = 4,
          callback = "keymaps.close",
          description = "[Chat] Close",
        },
        stop = {
          modes = { n = "q" },
          index = 5,
          callback = "keymaps.stop",
          description = "[Request] Stop",
        },
        clear = {
          modes = { n = "gx" },
          index = 6,
          callback = "keymaps.clear",
          description = "[Chat] Clear",
        },
        codeblock = {
          modes = { n = "gc" },
          index = 7,
          callback = "keymaps.codeblock",
          description = "[Chat] Insert codeblock",
        },
        yank_code = {
          modes = { n = "gy" },
          index = 8,
          callback = "keymaps.yank_code",
          description = "[Chat] Yank code",
        },
        buffer_sync_all = {
          modes = { n = "gba" },
          index = 9,
          callback = "keymaps.buffer_sync_all",
          description = "[Chat] Toggle buffer syncing",
        },
        buffer_sync_diff = {
          modes = { n = "gbd" },
          index = 10,
          callback = "keymaps.buffer_sync_diff",
          description = "[Chat] Toggle buffer diff syncing",
        },
        next_chat = {
          modes = { n = "}" },
          index = 11,
          callback = "keymaps.next_chat",
          description = "[Nav] Next chat",
        },
        previous_chat = {
          modes = { n = "{" },
          index = 12,
          callback = "keymaps.previous_chat",
          description = "[Nav] Previous chat",
        },
        next_header = {
          modes = { n = "]]" },
          index = 13,
          callback = "keymaps.next_header",
          description = "[Nav] Next header",
        },
        previous_header = {
          modes = { n = "[[" },
          index = 14,
          callback = "keymaps.previous_header",
          description = "[Nav] Previous header",
        },
        change_adapter = {
          modes = { n = "ga" },
          index = 15,
          callback = "keymaps.change_adapter",
          description = "[Adapter] Change adapter and model",
        },
        fold_code = {
          modes = { n = "gf" },
          index = 15,
          callback = "keymaps.fold_code",
          description = "[Chat] Fold code",
        },
        debug = {
          modes = { n = "gd" },
          index = 16,
          callback = "keymaps.debug",
          description = "[Chat] View debug info",
        },
        system_prompt = {
          modes = { n = "gs" },
          index = 17,
          callback = "keymaps.toggle_system_prompt",
          description = "[Chat] Toggle system prompt",
        },
        rules = {
          modes = { n = "gM" },
          index = 18,
          callback = "keymaps.clear_rules",
          description = "[Chat] Clear Rules",
        },
        clear_approvals = {
          modes = { n = "gtx" },
          index = 19,
          callback = "keymaps.clear_approvals",
          description = "[Tools] Clear approvals",
        },
        yolo_mode = {
          modes = { n = "gty" },
          index = 20,
          callback = "keymaps.yolo_mode",
          description = "[Tools] Toggle YOLO mode",
        },
        goto_file_under_cursor = {
          modes = { n = "gR" },
          index = 21,
          callback = "keymaps.goto_file_under_cursor",
          description = "[Chat] Open file under cursor",
        },
        copilot_stats = {
          modes = { n = "gS" },
          index = 22,
          callback = "keymaps.copilot_stats",
          description = "[Adapter] Copilot statistics",
        },
        -- Keymaps for ACP permission requests
        _acp_allow_always = {
          modes = { n = "g1" },
          description = "Allow Always",
        },
        _acp_allow_once = {
          modes = { n = "g2" },
          description = "Allow Once",
        },
        _acp_reject_once = {
          modes = { n = "g3" },
          description = "Reject Once",
        },
        _acp_reject_always = {
          modes = { n = "g4" },
          description = "Reject Always",
        },
      },
      opts = {
        blank_prompt = "", -- The prompt to use when the user doesn't provide a prompt
        completion_provider = providers.completion, -- blink|cmp|coc|default
        debounce = 150, -- Time to debounce user input (milliseconds)

        register = "+", -- The register to use for yanking code
        wait_timeout = 2e6, -- Time to wait for user response before timing out (milliseconds)
        yank_jump_delay_ms = 400, -- Delay before jumping back from the yanked code (milliseconds )

        -- What to do when an ACP permission request times out? (allow_once|reject_once)
        acp_timeout_response = "reject_once",

        ---@type string|fun(path: string)
        goto_file_action = ui_utils.tabnew_reuse,

        ---This is the default prompt which is sent with every request in the chat
        ---interaction. It is primarily based on the GitHub Copilot Chat's prompt
        ---but with some modifications. You can choose to remove this via
        ---your own config but note that LLM results may not be as good
        ---@param ctx CodeCompanion.SystemPrompt.Context
        ---@return string
        system_prompt = function(ctx)
          return ctx.default_system_prompt
            .. fmt(
              [[Additional context:
All non-code text responses must be written in the %s language.
The user's current working directory is %s.
The current date is %s.
The user's Neovim version is %s.
The user is working on a %s machine. Please respond with system specific commands if applicable.
]],
              ctx.language,
              ctx.cwd,
              ctx.date,
              ctx.nvim_version,
              ctx.os
            )
        end,
      },
    },
    -- INLINE INTERACTION -----------------------------------------------------
    inline = {
      adapter = "copilot",
      keymaps = {
        stop = {
          callback = "keymaps.stop",
          description = "Stop request",
          index = 4,
          modes = { n = "q" },
        },
      },
      editor_context = {
        ["buffer"] = {
          path = "interactions.inline.editor_context.buffer",
          description = "Share the current buffer with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["chat"] = {
          path = "interactions.inline.editor_context.chat",
          description = "Share the currently open chat buffer with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["clipboard"] = {
          path = "interactions.inline.editor_context.clipboard",
          description = "Share the contents of the clipboard with the LLM",
          opts = {
            contains_code = true,
          },
        },
      },
    },
    -- CMD INTERACTION --------------------------------------------------------
    cmd = {
      adapter = "copilot",
      opts = {
        system_prompt = [[You are currently plugged in to the Neovim text editor on a user's machine. Your core task is to generate an command-line inputs that the user can run within Neovim. Below are some rules to adhere to:

- Return plain text only
- Do not wrap your response in a markdown block or backticks
- Do not use any line breaks or newlines in you response
- Do not provide any explanations
- Generate an command that is valid and can be run in Neovim
- Ensure the command is relevant to the user's request]],
      },
    },
    shared = {
      keymaps = {
        always_accept = {
          callback = "keymaps.always_accept",
          description = "Always accept changes in this buffer",
          index = 1,
          modes = { n = "g1" },
          opts = { nowait = true },
        },
        accept_change = {
          callback = "keymaps.accept_change",
          description = "Accept change",
          index = 2,
          modes = { n = "g2" },
          opts = { nowait = true, noremap = true },
        },
        reject_change = {
          callback = "keymaps.reject_change",
          description = "Reject change",
          index = 3,
          modes = { n = "g3" },
          opts = { nowait = true, noremap = true },
        },
        next_hunk = {
          callback = "keymaps.next_hunk",
          description = "Go to next hunk",
          modes = { n = "}" },
        },
        previous_hunk = {
          callback = "keymaps.previous_hunk",
          description = "Go to previous hunk",
          modes = { n = "{" },
        },
      },
    },
  },
  -- MCP SERVERS ----------------------------------------------------------------
  mcp = {
    add_to_chat = true,
    auto_start = true,
    servers = {},
    opts = {
      acp_enabled = true, -- Enable MCP servers with ACP adapters?
      timeout = 30e3, -- Timeout for MCP server responses (milliseconds)
    },
  },
  -- PROMPT LIBRARIES ---------------------------------------------------------
  prompt_library = {
    -- Users can define prompt library items in markdown
    markdown = {
      dirs = {},
    },
  },
  -- RULES -------------------------------------------------------------------
  rules = {
    default = {
      description = "Collection of common files for all projects",
      files = {
        ".clinerules",
        ".cursorrules",
        ".goosehints",
        ".rules",
        ".windsurfrules",
        ".github/copilot-instructions.md",
        "AGENT.md",
        "AGENTS.md",
        { path = "CLAUDE.md", parser = "claude" },
        { path = "CLAUDE.local.md", parser = "claude" },
        { path = "~/.claude/CLAUDE.md", parser = "claude" },
      },
      is_preset = true,
    },
    CodeCompanion = {
      description = "CodeCompanion rules",
      parser = "claude",
      ---@return boolean
      enabled = function()
        -- Don't show this to users who aren't working on CodeCompanion itself
        return vim.fn.getcwd():find("codecompanion", 1, true) ~= nil
      end,
      files = {
        ["adapters"] = {
          description = "The adapters implementation",
          files = {
            ".codecompanion/adapters/adapters.md",
          },
        },
        ["chat"] = {
          description = "The chat buffer",
          files = {
            ".codecompanion/chat.md",
          },
        },
        ["acp"] = {
          description = "The ACP implementation",
          files = {
            ".codecompanion/acp/acp.md",
          },
        },
        ["acp-json-rpc"] = {
          description = "The JSON-RPC output for various ACP adapters",
          files = {
            ".codecompanion/acp/claude_code_acp.md",
          },
        },
        ["tests"] = {
          description = "Testing in the plugin",
          files = {
            ".codecompanion/tests/test.md",
          },
        },
        ["tools"] = {
          description = "Tools implementation in the plugin",
          files = {
            ".codecompanion/tools.md",
          },
        },
        ["ui"] = {
          description = "The chat UI implementation",
          files = {
            ".codecompanion/ui.md",
          },
        },
      },
      is_preset = true,
    },
    parsers = {
      claude = "claude", -- Parser for CLAUDE.md files
      codecompanion = "codecompanion", -- Parser for CodeCompanion specific rules files
      none = "none", -- No parsing, just raw text
    },
    opts = {
      chat = {
        ---The rule groups to load with every chat interaction
        ---@type string|fun(): string
        autoload = "default",

        ---@type boolean | fun(chat: CodeCompanion.Chat): boolean
        enabled = true,

        ---The default parameters to use when loading buffer rules
        default_params = "diff", -- all|diff
      },

      show_presets = true, -- Show the preset rules files?
    },
  },
  -- DISPLAY OPTIONS ----------------------------------------------------------
  display = {
    action_palette = {
      width = 95,
      height = 10,
      prompt = "Prompt ", -- Title used for interactive LLM calls
      provider = providers.action_palette, -- telescope|mini_pick|snacks|default
      opts = {
        show_preset_actions = true,
        show_preset_prompts = true,
        show_preset_rules = true,
        title = "CodeCompanion actions",
      },
    },
    chat = {
      icons = {
        buffer_sync_all = "󰪴 ",
        buffer_sync_diff = " ",
        --chat_context = " ",
        chat_fold = " ",
        tool_pending = "  ",
        tool_in_progress = "  ",
        tool_failure = "  ",
        tool_success = "  ",
      },

      -- Window options for the chat buffer
      window = {
        buflisted = false, -- List the chat buffer in the buffer list?
        sticky = false, -- Chat buffer remains open when switching tabs

        layout = "vertical", -- float|vertical|horizontal|buffer
        full_height = true, -- for vertical layout
        position = nil, -- left|right|top|bottom (nil will default depending on vim.opt.splitright|vim.opt.splitbelow)

        width = 0.5, ---@return number|fun(): number
        height = 0.8, ---@return number|fun(): number
        border = "single",
        relative = "editor",

        -- Ensure that long paragraphs of markdown are wrapped
        opts = {
          breakindent = true,
          linebreak = true,
          wrap = true,
        },
      },

      -- Options for an floating windows
      floating_window = {
        width = 0.9, ---@return number|fun(): number
        height = 0.8, ---@return number|fun(): number
        border = "single",
        relative = "editor",
        opts = {},
      },

      -- Chat buffer options --------------------------------------------------
      auto_scroll = true, -- Automatically scroll down and place the cursor at the end?
      intro_message = "Welcome to CodeCompanion ✨! Press ? for options",

      separator = "─", -- The separator between the different messages in the chat buffer
      show_header_separator = false, -- Show header separators in the chat buffer? Set this to false if you're using an external markdown formatting plugin

      fold_context = false, -- Fold context in the chat buffer?
      show_context = true, -- Show context that you've shared with the LLM in the chat buffer?

      fold_reasoning = true, -- Fold the reasoning content in the chat buffer?
      show_reasoning = true, -- Show reasoning content in the chat buffer?

      show_settings = false, -- Show an LLM's settings at the top of the chat buffer?
      show_token_count = true, -- Show the token count for each response?
      show_tools_processing = true, -- Show the loading message when tools are being executed?
      start_in_insert_mode = false, -- Open the chat buffer in insert mode?

      ---The function to display the token count
      ---@param tokens number
      ---@param adapter CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter
      ---@return string
      token_count = function(tokens, adapter) -- The function to display the token count
        return " (" .. tokens .. " tokens)"
      end,
    },
    diff = {
      enabled = true,
      -- Options for any diff windows (extends from floating_window)
      window = {
        opts = {},
      },
      word_highlights = {
        additions = true,
        deletions = true,
      },
    },
    inline = {
      -- If the inline prompt creates a new buffer, how should we display this?
      layout = "vertical", -- vertical|horizontal|buffer
    },
    icons = {
      warning = " ",
    },
  },
  -- EXTENSIONS ------------------------------------------------------
  extensions = {},
  -- GENERAL OPTIONS ----------------------------------------------------------
  opts = {
    log_level = "ERROR", -- TRACE|DEBUG|ERROR|INFO
    language = "English", -- The language used for LLM responses

    per_project_config = {
      enabled = true, -- Enable per-project configuration?
      files = {}, -- Files in the cwd that contain project configuration
      paths = {}, -- Per-path config: { ["~/Code/myproject"] = { ... } }
    },

    -- If this is false then any default prompt that is marked as containing code
    -- will not be sent to the LLM. Please note that whilst I have made every
    -- effort to ensure no code leakage, using this is at your own risk
    ---@type boolean|function
    ---@return boolean
    send_code = true,

    submit_delay = 500, -- Delay in milliseconds before auto-submitting the chat buffer

    triggers = {
      acp_slash_commands = "\\",
      editor_context = "#",
      slash_commands = "/",
      tools = "@",
    },
  },
}

local M = {
  config = vim.deepcopy(defaults),
}

---Check the cwd for any per-project configuration files and load them if they exist
---@return table|nil
local function get_per_project_config()
  local file_utils = require("codecompanion.utils.files")

  local cfg = M.config.opts.per_project_config
  if not cfg or not cfg.enabled then
    return nil
  end

  local cwd = vim.fs.normalize(vim.fn.getcwd())
  local config = {}

  local function notify(msg)
    vim.notify(fmt("[CodeCompanion] %s", msg), vim.log.levels.ERROR, { title = "CodeCompanion" })
  end

  -- Collect path-based configs
  if cfg.paths then
    for path, path_cfg in pairs(cfg.paths) do
      if vim.fs.normalize(vim.fn.expand(path)) == cwd then
        if type(path_cfg) ~= "table" then
          notify(fmt("Per-project config for path `%s` must be a table", path))
        else
          config = vim.tbl_deep_extend("force", config, path_cfg)
        end
      end
    end
  end

  -- Collect file-based configs
  for _, filename in ipairs(cfg.files) do
    local path = vim.fs.joinpath(cwd, filename)
    if file_utils.exists(path) and not file_utils.is_dir(path) then
      local ok, file_cfg = pcall(dofile, path)
      if not ok then
        notify(fmt("Failed to load per-project config `%s`: %s", filename, file_cfg))
      elseif type(file_cfg) ~= "table" then
        notify(fmt("Per-project config `%s` must return a table", filename))
      else
        config = vim.tbl_deep_extend("force", config, file_cfg)
      end
    end
  end

  return next(config) ~= nil and config or nil
end

---@param keymaps table<string, table|boolean>
local function remove_disabled_keymaps(keymaps)
  local enabled = {}
  for name, keymap in pairs(keymaps) do
    if keymap ~= false then
      enabled[name] = keymap
    end
  end
  return enabled
end

---@param args? table
M.setup = function(args)
  args = args or {}

  if args.constants then
    return vim.notify(
      "Your config table cannot have the field `constants`",
      vim.log.levels.ERROR,
      { title = "CodeCompanion" }
    )
  end

  -- TODO: Remove in v20.0.0
  if args.strategies then
    args.interactions = vim.tbl_deep_extend("force", vim.deepcopy(defaults.interactions), args.strategies)
    args.strategies = nil
  end

  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), args)

  M.config.interactions.chat.keymaps = remove_disabled_keymaps(M.config.interactions.chat.keymaps)
  M.config.interactions.inline.keymaps = remove_disabled_keymaps(M.config.interactions.inline.keymaps)
  M.config.interactions.shared.keymaps = remove_disabled_keymaps(M.config.interactions.shared.keymaps)

  local project_config = get_per_project_config()
  if project_config then
    M.config = vim.tbl_deep_extend("force", M.config, project_config)
  end

  M.config.INFO_NS = vim.api.nvim_create_namespace("CodeCompanion-info")
  M.config.ERROR_NS = vim.api.nvim_create_namespace("CodeCompanion-error")

  local diagnostic_config = {
    underline = false,
    virtual_text = {
      spacing = 2,
      severity = { min = vim.diagnostic.severity.INFO },
    },
    signs = false,
  }
  vim.diagnostic.config(diagnostic_config, M.config.INFO_NS)
  vim.diagnostic.config(diagnostic_config, M.config.ERROR_NS)
end

---Determine if code can be sent to the LLM
---@return boolean
M.can_send_code = function()
  if type(M.config.opts.send_code) == "boolean" then
    return M.config.opts.send_code
  elseif type(M.config.opts.send_code) == "function" then
    return M.config.opts.send_code()
  end
  return false
end

return setmetatable(M, {
  __index = function(_, key)
    if key == "setup" then
      return M.setup
    end
    return rawget(M.config, key)
  end,
})
