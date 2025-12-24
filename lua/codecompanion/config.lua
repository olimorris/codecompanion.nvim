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
      opencode = "opencode",
      opts = {
        show_presets = true,
      },
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
          ["full_stack_dev"] = {
            description = "Full Stack Developer - Can run code, edit code and modify files",
            prompt = "I'm giving you access to the ${tools} to help you perform coding tasks",
            tools = {
              "cmd_runner",
              "create_file",
              "delete_file",
              "file_search",
              "get_changed_files",
              "grep_search",
              "insert_edit_into_file",
              "list_code_usages",
              "read_file",
            },
            opts = {
              collapse_tools = true,
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
        ["cmd_runner"] = {
          callback = "interactions.chat.tools.builtin.cmd_runner",
          description = "Run shell commands initiated by the LLM",
          opts = {
            allowed_in_yolo_mode = false,
            require_approval_before = true,
            require_cmd_approval = true,
          },
        },
        ["insert_edit_into_file"] = {
          callback = "interactions.chat.tools.builtin.insert_edit_into_file",
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
        ["create_file"] = {
          callback = "interactions.chat.tools.builtin.create_file",
          description = "Create a file in the current working directory",
          opts = {
            require_approval_before = true,
            require_cmd_approval = true,
          },
        },
        ["delete_file"] = {
          callback = "interactions.chat.tools.builtin.delete_file",
          description = "Delete a file in the current working directory",
          opts = {
            allowed_in_yolo_mode = false,
            require_approval_before = true,
            require_cmd_approval = true,
          },
        },
        ["fetch_webpage"] = {
          callback = "interactions.chat.tools.builtin.fetch_webpage",
          description = "Fetches content from a webpage",
          opts = {
            adapter = "jina",
          },
        },
        ["file_search"] = {
          callback = "interactions.chat.tools.builtin.file_search",
          description = "Search for files in the current working directory by glob pattern",
          opts = {
            max_results = 500,
            require_cmd_approval = true,
          },
        },
        ["get_changed_files"] = {
          callback = "interactions.chat.tools.builtin.get_changed_files",
          description = "Get git diffs of current file changes in a git repository",
          opts = {
            max_lines = 1000,
          },
        },
        ["grep_search"] = {
          callback = "interactions.chat.tools.builtin.grep_search",
          enabled = function()
            -- Currently this tool only supports ripgrep
            return vim.fn.executable("rg") == 1
          end,
          description = "Search for text in the current working directory",
          opts = {
            max_results = 100,
            respect_gitignore = true,
            require_approval_before = true,
            require_cmd_approval = true,
          },
        },
        ["memory"] = {
          callback = "interactions.chat.tools.builtin.memory",
          description = "The memory tool enables LLMs to store and retrieve information across conversations through a memory file directory",
          opts = {
            require_approval_before = true,
          },
        },
        ["next_edit_suggestion"] = {
          callback = "interactions.chat.tools.builtin.next_edit_suggestion",
          description = "Suggest and jump to the next position to edit",
        },
        ["read_file"] = {
          callback = "interactions.chat.tools.builtin.read_file",
          description = "Read a file in the current working directory",
          opts = {
            require_approval_before = true,
            require_cmd_approval = true,
          },
        },
        ["web_search"] = {
          callback = "interactions.chat.tools.builtin.web_search",
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
        ["list_code_usages"] = {
          callback = "interactions.chat.tools.builtin.list_code_usages",
          description = "Find code symbol context",
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
      variables = {
        ["buffer"] = {
          callback = "interactions.chat.variables.buffer",
          description = "Share the current buffer with the LLM",
          opts = {
            contains_code = true,
            default_params = "diff", -- all|diff
            has_params = true,
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
        },
        ["lsp"] = {
          callback = "interactions.chat.variables.lsp",
          description = "Share LSP information and code for the current buffer",
          opts = {
            contains_code = true,
          },
        },
        ["viewport"] = {
          callback = "interactions.chat.variables.viewport",
          description = "Share the code that you see in Neovim with the LLM",
          opts = {
            contains_code = true,
          },
        },
      },
      slash_commands = {
        ["buffer"] = {
          callback = "interactions.chat.slash_commands.builtin.buffer",
          description = "Insert open buffers",
          opts = {
            contains_code = true,
            default_params = "diff", -- all|diff
            provider = providers.pickers, -- telescope|fzf_lua|mini_pick|snacks|default
          },
        },
        ["compact"] = {
          callback = "interactions.chat.slash_commands.builtin.compact",
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
          callback = "interactions.chat.slash_commands.builtin.fetch",
          description = "Insert URL contents",
          opts = {
            adapter = "jina", -- jina
            cache_path = vim.fn.stdpath("data") .. "/codecompanion/urls",
            provider = providers.pickers, -- telescope|fzf_lua|mini_pick|snacks|default
          },
        },
        ["quickfix"] = {
          callback = "interactions.chat.slash_commands.builtin.quickfix",
          description = "Insert quickfix list entries",
          opts = {
            contains_code = true,
          },
        },
        ["file"] = {
          callback = "interactions.chat.slash_commands.builtin.file",
          description = "Insert a file",
          opts = {
            contains_code = true,
            max_lines = 1000,
            provider = providers.pickers, -- telescope|fzf_lua|mini_pick|snacks|default
          },
        },
        ["help"] = {
          callback = "interactions.chat.slash_commands.builtin.help",
          description = "Insert content from help tags",
          opts = {
            contains_code = false,
            max_lines = 128, -- Maximum amount of lines to of the help file to send (NOTE: Each vimdoc line is typically 10 tokens)
            provider = providers.help, -- telescope|fzf_lua|mini_pick|snacks
          },
        },
        ["image"] = {
          callback = "interactions.chat.slash_commands.builtin.image",
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
        ["rules"] = {
          callback = "interactions.chat.slash_commands.builtin.rules",
          description = "Insert rules into the chat buffer",
          opts = {
            contains_code = true,
          },
        },
        ["mode"] = {
          callback = "interactions.chat.slash_commands.builtin.mode",
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
          callback = "interactions.chat.slash_commands.builtin.now",
          description = "Insert the current date and time",
          opts = {
            contains_code = false,
          },
        },
        ["symbols"] = {
          callback = "interactions.chat.slash_commands.builtin.symbols",
          description = "Insert symbols for a selected file",
          opts = {
            contains_code = true,
            provider = providers.pickers, -- telescope|fzf_lua|mini_pick|snacks|default
          },
        },
        ["terminal"] = {
          callback = "interactions.chat.slash_commands.builtin.terminal",
          description = "Insert terminal output",
          opts = {
            contains_code = false,
          },
        },
        opts = {
          acp = {
            enabled = true, -- Enable ACP command completion
            trigger = "\\", -- Trigger character for ACP commands
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
        super_diff = {
          modes = { n = "gD" },
          index = 23,
          callback = "keymaps.super_diff",
          description = "[Tools] Show Super Diff",
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
    -- INLINE INTERACTION -----------------------------------------------------
    inline = {
      adapter = "copilot",
      keymaps = {
        always_accept = {
          callback = "keymaps.always_accept",
          description = "Always accept changes in this buffer",
          index = 1,
          modes = { n = "gdy" },
          opts = { nowait = true },
        },
        accept_change = {
          callback = "keymaps.accept_change",
          description = "Accept change",
          index = 2,
          modes = { n = "gda" },
          opts = { nowait = true, noremap = true },
        },
        reject_change = {
          callback = "keymaps.reject_change",
          description = "Reject change",
          index = 3,
          modes = { n = "gdr" },
          opts = { nowait = true, noremap = true },
        },
        stop = {
          callback = "keymaps.stop",
          description = "Stop request",
          index = 4,
          modes = { n = "q" },
        },
      },
      variables = {
        ["buffer"] = {
          callback = "interactions.inline.variables.buffer",
          description = "Share the current buffer with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["chat"] = {
          callback = "interactions.inline.variables.chat",
          description = "Share the currently open chat buffer with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["clipboard"] = {
          callback = "interactions.inline.variables.clipboard",
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
      prompt = "Prompt ", -- Prompt used for interactive LLM calls
      provider = providers.action_palette, -- telescope|mini_pick|snacks|default
      opts = {
        show_preset_actions = true, -- Show the preset actions in the action palette?
        show_preset_prompts = true, -- Show the preset prompts in the action palette?
        show_preset_rules = true, -- Show the preset rules in the action palette?
        title = "CodeCompanion actions", -- The title of the action palette
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

      -- Options for any windows that open within the chat buffer
      floating_window = {
        ---@return number|fun(): number
        width = function()
          return vim.o.columns - 5
        end,
        ---@return number|fun(): number
        height = function()
          return vim.o.lines - 2
        end,
        row = "center",
        col = "center",
        relative = "editor",
        opts = {},
      },

      -- Options for diff windows that open within the chat buffer
      diff_window = {
        ---@return number|fun(): number
        width = function()
          return math.min(120, vim.o.columns - 10)
        end,
        ---@return number|fun(): number
        height = function()
          return vim.o.lines - 4
        end,
        opts = {
          number = true,
        },
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
      show_tools_processing = true, -- Show the loading message when tools are being executed?
      show_token_count = true, -- Show the token count for each response?
      start_in_insert_mode = false, -- Open the chat buffer in insert mode?

      ---The function to display the token count
      ---@param tokens number
      ---@param adapter CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter
      token_count = function(tokens, adapter) -- The function to display the token count
        return " (" .. tokens .. " tokens)"
      end,
    },
    diff = {
      enabled = true,
      provider = providers.diff, -- mini_diff|split|inline

      provider_opts = {
        -- Options for inline diff provider
        inline = {
          layout = "float", -- float|buffer - Where to display the diff

          diff_signs = {
            signs = {
              text = "▌", -- Sign text for normal changes
              reject = "✗", -- Sign text for rejected changes in super_diff
              highlight_groups = {
                addition = "DiagnosticOk",
                deletion = "DiagnosticError",
                modification = "DiagnosticWarn",
              },
            },
            -- Super Diff options
            icons = {
              accepted = " ",
              rejected = " ",
            },
            colors = {
              accepted = "DiagnosticOk",
              rejected = "DiagnosticError",
            },
          },

          opts = {
            context_lines = 3, -- Number of context lines in hunks
            show_dim = true, -- Enable dimming background for floating windows (applies to both diff and super_diff)
            dim = 25, -- Background dim level for floating diff (0-100, [100 full transparent], only applies when layout = "float")
            full_width_removed = true, -- Make removed lines span full width
            show_keymap_hints = true, -- Show "gda: accept | gdr: reject" hints above diff
            show_removed = true, -- Show removed lines as virtual text
          },
        },

        -- Options for the split provider
        split = {
          close_chat_at = 240, -- Close an open chat buffer if the total columns of your display are less than...
          layout = "vertical", -- vertical|horizontal split
          opts = {
            "internal",
            "filler",
            "closeoff",
            "algorithm:histogram", -- https://adamj.eu/tech/2024/01/18/git-improve-diff-histogram/
            "indent-heuristic", -- https://blog.k-nut.eu/better-git-diffs
            "followwrap",
            "linematch:120",
          },
        },
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

    -- If this is false then any default prompt that is marked as containing code
    -- will not be sent to the LLM. Please note that whilst I have made every
    -- effort to ensure no code leakage, using this is at your own risk
    ---@type boolean|function
    ---@return boolean
    send_code = true,

    job_start_delay = 1500, -- Delay in milliseconds between cmd tools
    submit_delay = 2000, -- Delay in milliseconds before auto-submitting the chat buffer
  },
}

local M = {
  config = vim.deepcopy(defaults),
}

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

  -- TODO: Remove in v19.0.0
  if args.strategies then
    args.interactions = vim.tbl_deep_extend("force", vim.deepcopy(defaults.interactions), args.strategies)
    args.strategies = nil
  end

  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), args)

  M.config.interactions.chat.keymaps = remove_disabled_keymaps(M.config.interactions.chat.keymaps)
  M.config.interactions.inline.keymaps = remove_disabled_keymaps(M.config.interactions.inline.keymaps)

  -- Set the diagnostic namespace for the chat buffer settings
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
