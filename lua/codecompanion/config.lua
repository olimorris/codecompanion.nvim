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
        show_defaults = true, -- Show default adapters
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
        show_defaults = true, -- Show default adapters
      },
    },
  },
  constants = constants,
  interactions = {
    -- BACKGROUND INTERACTION -------------------------------------------------
    background = {
      adapter = "copilot",
      -- Callbacks within the plugin that you can attach background actions to
      chat = {
        callbacks = {
          ["on_ready"] = {
            actions = {
              "interactions.background.catalog.chat_make_title",
            },
            enabled = true,
          },
        },
        opts = {
          enabled = false, -- Enable ALL background chat interactions?
        },
      },
    },
  },
  strategies = {
    -- CHAT STRATEGY ----------------------------------------------------------
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
          callback = "strategies.chat.tools.catalog.cmd_runner",
          description = "Run shell commands initiated by the LLM",
          opts = {
            requires_approval = true,
          },
        },
        ["insert_edit_into_file"] = {
          callback = "strategies.chat.tools.catalog.insert_edit_into_file",
          description = "Robustly edit existing files with multiple automatic fallback strategies",
          opts = {
            requires_approval = { -- Require approval before the tool is executed?
              buffer = false, -- For editing buffers in Neovim
              file = false, -- For editing files in the current working directory
            },
            user_confirmation = true, -- Require confirmation from the user before accepting the edit?
            file_size_limit_mb = 2, -- Maximum file size in MB
          },
        },
        ["create_file"] = {
          callback = "strategies.chat.tools.catalog.create_file",
          description = "Create a file in the current working directory",
          opts = {
            requires_approval = true,
          },
        },
        ["delete_file"] = {
          callback = "strategies.chat.tools.catalog.delete_file",
          description = "Delete a file in the current working directory",
          opts = {
            requires_approval = true,
          },
        },
        ["fetch_webpage"] = {
          callback = "strategies.chat.tools.catalog.fetch_webpage",
          description = "Fetches content from a webpage",
          opts = {
            adapter = "jina",
          },
        },
        ["file_search"] = {
          callback = "strategies.chat.tools.catalog.file_search",
          description = "Search for files in the current working directory by glob pattern",
          opts = {
            max_results = 500,
          },
        },
        ["get_changed_files"] = {
          callback = "strategies.chat.tools.catalog.get_changed_files",
          description = "Get git diffs of current file changes in a git repository",
          opts = {
            max_lines = 1000,
          },
        },
        ["grep_search"] = {
          callback = "strategies.chat.tools.catalog.grep_search",
          enabled = function()
            -- Currently this tool only supports ripgrep
            return vim.fn.executable("rg") == 1
          end,
          description = "Search for text in the current working directory",
          opts = {
            max_results = 100,
            respect_gitignore = true,
          },
        },
        ["memory"] = {
          callback = "strategies.chat.tools.catalog.memory",
          description = "The memory tool enables LLMs to store and retrieve information across conversations through a memory file directory",
          opts = {
            requires_approval = true,
          },
        },
        ["next_edit_suggestion"] = {
          callback = "strategies.chat.tools.catalog.next_edit_suggestion",
          description = "Suggest and jump to the next position to edit",
        },
        ["read_file"] = {
          callback = "strategies.chat.tools.catalog.read_file",
          description = "Read a file in the current working directory",
        },
        ["web_search"] = {
          callback = "strategies.chat.tools.catalog.web_search",
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
          callback = "strategies.chat.tools.catalog.list_code_usages",
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
          callback = "strategies.chat.variables.buffer",
          description = "Share the current buffer with the LLM",
          opts = {
            contains_code = true,
            default_params = "watch", -- watch|pin
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
          callback = "strategies.chat.variables.lsp",
          description = "Share LSP information and code for the current buffer",
          opts = {
            contains_code = true,
          },
        },
        ["viewport"] = {
          callback = "strategies.chat.variables.viewport",
          description = "Share the code that you see in Neovim with the LLM",
          opts = {
            contains_code = true,
          },
        },
      },
      slash_commands = {
        ["buffer"] = {
          callback = "strategies.chat.slash_commands.catalog.buffer",
          description = "Insert open buffers",
          opts = {
            contains_code = true,
            default_params = "watch", -- watch|pin
            provider = providers.pickers, -- telescope|fzf_lua|mini_pick|snacks|default
          },
        },
        ["compact"] = {
          callback = "strategies.chat.slash_commands.catalog.compact",
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
          callback = "strategies.chat.slash_commands.catalog.fetch",
          description = "Insert URL contents",
          opts = {
            adapter = "jina", -- jina
            cache_path = vim.fn.stdpath("data") .. "/codecompanion/urls",
            provider = providers.pickers, -- telescope|fzf_lua|mini_pick|snacks|default
          },
        },
        ["quickfix"] = {
          callback = "strategies.chat.slash_commands.catalog.quickfix",
          description = "Insert quickfix list entries",
          opts = {
            contains_code = true,
          },
        },
        ["file"] = {
          callback = "strategies.chat.slash_commands.catalog.file",
          description = "Insert a file",
          opts = {
            contains_code = true,
            max_lines = 1000,
            provider = providers.pickers, -- telescope|fzf_lua|mini_pick|snacks|default
          },
        },
        ["help"] = {
          callback = "strategies.chat.slash_commands.catalog.help",
          description = "Insert content from help tags",
          opts = {
            contains_code = false,
            max_lines = 128, -- Maximum amount of lines to of the help file to send (NOTE: Each vimdoc line is typically 10 tokens)
            provider = providers.help, -- telescope|fzf_lua|mini_pick|snacks
          },
        },
        ["image"] = {
          callback = "strategies.chat.slash_commands.catalog.image",
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
        ["memory"] = {
          callback = "strategies.chat.slash_commands.catalog.memory",
          description = "Insert a memory into the chat buffer",
          opts = {
            contains_code = true,
          },
        },
        ["mode"] = {
          callback = "strategies.chat.slash_commands.catalog.mode",
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
          callback = "strategies.chat.slash_commands.catalog.now",
          description = "Insert the current date and time",
          opts = {
            contains_code = false,
          },
        },
        ["symbols"] = {
          callback = "strategies.chat.slash_commands.catalog.symbols",
          description = "Insert symbols for a selected file",
          opts = {
            contains_code = true,
            provider = providers.pickers, -- telescope|fzf_lua|mini_pick|snacks|default
          },
        },
        ["terminal"] = {
          callback = "strategies.chat.slash_commands.catalog.terminal",
          description = "Insert terminal output",
          opts = {
            contains_code = false,
          },
        },
        ["workspace"] = {
          callback = "strategies.chat.slash_commands.catalog.workspace",
          description = "Load a workspace file",
          opts = {
            contains_code = true,
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
          description = "Completion menu",
        },
        send = {
          modes = {
            n = { "<CR>", "<C-s>" },
            i = "<C-s>",
          },
          index = 2,
          callback = "keymaps.send",
          description = "Send message",
        },
        regenerate = {
          modes = { n = "gr" },
          index = 3,
          callback = "keymaps.regenerate",
          description = "Regenerate last response",
        },
        close = {
          modes = {
            n = "<C-c>",
            i = "<C-c>",
          },
          index = 4,
          callback = "keymaps.close",
          description = "Close chat",
        },
        stop = {
          modes = { n = "q" },
          index = 5,
          callback = "keymaps.stop",
          description = "Stop request",
        },
        clear = {
          modes = { n = "gx" },
          index = 6,
          callback = "keymaps.clear",
          description = "Clear chat",
        },
        codeblock = {
          modes = { n = "gc" },
          index = 7,
          callback = "keymaps.codeblock",
          description = "Insert codeblock",
        },
        yank_code = {
          modes = { n = "gy" },
          index = 8,
          callback = "keymaps.yank_code",
          description = "Yank code",
        },
        pin = {
          modes = { n = "gp" },
          index = 9,
          callback = "keymaps.pin_context",
          description = "Pin context",
        },
        watch = {
          modes = { n = "gw" },
          index = 10,
          callback = "keymaps.toggle_watch",
          description = "Watch buffer",
        },
        next_chat = {
          modes = { n = "}" },
          index = 11,
          callback = "keymaps.next_chat",
          description = "Next chat",
        },
        previous_chat = {
          modes = { n = "{" },
          index = 12,
          callback = "keymaps.previous_chat",
          description = "Previous chat",
        },
        next_header = {
          modes = { n = "]]" },
          index = 13,
          callback = "keymaps.next_header",
          description = "Next header",
        },
        previous_header = {
          modes = { n = "[[" },
          index = 14,
          callback = "keymaps.previous_header",
          description = "Previous header",
        },
        change_adapter = {
          modes = { n = "ga" },
          index = 15,
          callback = "keymaps.change_adapter",
          description = "Change adapter",
        },
        fold_code = {
          modes = { n = "gf" },
          index = 15,
          callback = "keymaps.fold_code",
          description = "Fold code",
        },
        debug = {
          modes = { n = "gd" },
          index = 16,
          callback = "keymaps.debug",
          description = "View debug info",
        },
        system_prompt = {
          modes = { n = "gs" },
          index = 17,
          callback = "keymaps.toggle_system_prompt",
          description = "Toggle system prompt",
        },
        memory = {
          modes = { n = "gM" },
          index = 18,
          callback = "keymaps.clear_memory",
          description = "Clear memory",
        },
        fs_diff = {
          modes = { n = "gD" },
          index = 19,
          callback = "keymaps.show_fs_diff",
          description = "Show file system diff",
        },
        yolo_mode = {
          modes = { n = "gty" },
          index = 20,
          callback = "keymaps.yolo_mode",
          description = "YOLO mode toggle",
        },
        goto_file_under_cursor = {
          modes = { n = "gR" },
          index = 21,
          callback = "keymaps.goto_file_under_cursor",
          description = "Open file under cursor",
        },
        copilot_stats = {
          modes = { n = "gS" },
          index = 22,
          callback = "keymaps.copilot_stats",
          description = "Show Copilot statistics",
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
        ---strategy. It is primarily based on the GitHub Copilot Chat's prompt
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
    -- INLINE STRATEGY --------------------------------------------------------
    inline = {
      adapter = "copilot",
      keymaps = {
        accept_change = {
          modes = { n = "gda" },
          opts = { nowait = true, noremap = true },
          index = 1,
          callback = "keymaps.accept_change",
          description = "Accept change",
        },
        reject_change = {
          modes = { n = "gdr" },
          opts = { nowait = true, noremap = true },
          index = 2,
          callback = "keymaps.reject_change",
          description = "Reject change",
        },
        always_accept = {
          modes = { n = "gdy" },
          opts = { nowait = true },
          index = 3,
          callback = "keymaps.always_accept",
          description = "Accept and enable auto mode",
        },
        next_hunk = {
          modes = { n = "]h" },
          opts = { nowait = true, noremap = true },
          index = 4,
          callback = "keymaps.next_hunk",
          description = "Jump to next hunk",
        },
        prev_hunk = {
          modes = { n = "[h" },
          opts = { nowait = true, noremap = true },
          index = 5,
          callback = "keymaps.prev_hunk",
          description = "Jump to previous hunk",
        },
      },
      variables = {
        ["buffer"] = {
          callback = "strategies.inline.variables.buffer",
          description = "Share the current buffer with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["chat"] = {
          callback = "strategies.inline.variables.chat",
          description = "Share the currently open chat buffer with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["clipboard"] = {
          callback = "strategies.inline.variables.clipboard",
          description = "Share the contents of the clipboard with the LLM",
          opts = {
            contains_code = true,
          },
        },
      },
    },
    -- CMD STRATEGY -----------------------------------------------------------
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
    ["Custom Prompt"] = {
      strategy = "inline",
      description = "Prompt the LLM from Neovim",
      opts = {
        index = 3,
        is_default = true,
        is_slash_cmd = false,
        user_prompt = true,
      },
      prompts = {
        {
          role = constants.SYSTEM_ROLE,
          content = function(context)
            return fmt(
              [[I want you to act as a senior %s developer. I will ask you specific questions and I want you to return raw code only (no codeblocks and no explanations). If you can't respond with code, respond with nothing]],
              context.filetype
            )
          end,
        },
      },
    },
    ["Code workflow"] = {
      strategy = "workflow",
      description = "Use a workflow to guide an LLM in writing code",
      opts = {
        index = 4,
        is_default = true,
        short_name = "cw",
      },
      prompts = {
        {
          -- We can group prompts together to make a workflow
          -- This is the first prompt in the workflow
          {
            role = constants.SYSTEM_ROLE,
            content = function(context)
              return fmt(
                "You carefully provide accurate, factual, thoughtful, nuanced answers, and are brilliant at reasoning. If you think there might not be a correct answer, you say so. Always spend a few sentences explaining background context, assumptions, and step-by-step thinking BEFORE you try to answer a question. Don't be verbose in your answers, but do provide details and examples where it might help the explanation. You are an expert software engineer for the %s language",
                context.filetype
              )
            end,
          },
          {
            role = constants.USER_ROLE,
            content = "I want you to ",
            opts = {
              auto_submit = false,
            },
          },
        },
        -- This is the second group of prompts
        {
          {
            role = constants.USER_ROLE,
            content = "Great. Now let's consider your code. I'd like you to check it carefully for correctness, style, and efficiency, and give constructive criticism for how to improve it.",
            opts = {
              auto_submit = true,
            },
          },
        },
        -- This is the final group of prompts
        {
          {
            role = constants.USER_ROLE,
            content = "Thanks. Now let's revise the code based on the feedback, without additional explanations.",
            opts = {
              auto_submit = true,
            },
          },
        },
      },
    },
    ["Edit<->Test workflow"] = {
      strategy = "workflow",
      description = "Use a workflow to repeatedly edit then test code",
      opts = {
        index = 5,
        is_default = true,
        short_name = "et",
      },
      prompts = {
        {
          {
            name = "Setup Test",
            role = constants.USER_ROLE,
            opts = { auto_submit = false },
            content = function()
              -- Enable YOLO mode!
              vim.g.codecompanion_yolo_mode = true

              return [[### Instructions

Your instructions here

### Steps to Follow

You are required to write code following the instructions provided above and test the correctness by running the designated test suite. Follow these steps exactly:

1. Update the code in #{buffer} using the @{insert_edit_into_file} tool
2. Then use the @{cmd_runner} tool to run the test suite with `<test_cmd>` (do this after you have updated the code)
3. Make sure you trigger both tools in the same response

We'll repeat this cycle until the tests pass. Ensure no deviations from these steps.]]
            end,
          },
        },
        {
          {
            name = "Repeat On Failure",
            role = constants.USER_ROLE,
            opts = { auto_submit = true },
            -- Scope this prompt to the cmd_runner tool
            condition = function()
              return _G.codecompanion_current_tool == "cmd_runner"
            end,
            -- Repeat until the tests pass, as indicated by the testing flag
            -- which the cmd_runner tool sets on the chat buffer
            repeat_until = function(chat)
              return chat.tool_registry.flags.testing == true
            end,
            content = "The tests have failed. Can you edit the buffer and run the test suite again?",
          },
        },
      },
    },
    ["Explain"] = {
      strategy = "chat",
      description = "Explain how code in a buffer works",
      opts = {
        index = 6,
        is_default = true,
        is_slash_cmd = false,
        modes = { "v" },
        short_name = "explain",
        auto_submit = true,
        user_prompt = false,
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = constants.SYSTEM_ROLE,
          content = [[When asked to explain code, follow these steps:

1. Identify the programming language.
2. Describe the purpose of the code and reference core concepts from the programming language.
3. Explain each function or significant block of code, including parameters and return values.
4. Highlight any specific functions or methods used and their roles.
5. Provide context on how the code fits into a larger application if applicable.]],
        },
        {
          role = constants.USER_ROLE,
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

            return fmt(
              [[Please explain this code from buffer %d:

```%s
%s
```
]],
              context.bufnr,
              context.filetype,
              code
            )
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
    ["Unit Tests"] = {
      strategy = "inline",
      description = "Generate unit tests for the selected code",
      opts = {
        index = 7,
        is_default = true,
        is_slash_cmd = false,
        modes = { "v" },
        short_name = "tests",
        auto_submit = true,
        user_prompt = false,
        placement = "new",
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = constants.SYSTEM_ROLE,
          content = [[When generating unit tests, follow these steps:

1. Identify the programming language.
2. Identify the purpose of the function or module to be tested.
3. List the edge cases and typical use cases that should be covered in the tests and share the plan with the user.
4. Generate unit tests using an appropriate testing framework for the identified programming language.
5. Ensure the tests cover:
      - Normal cases
      - Edge cases
      - Error handling (if applicable)
6. Provide the generated unit tests in a clear and organized manner without additional explanations or chat.]],
        },
        {
          role = constants.USER_ROLE,
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

            return fmt(
              [[<user_prompt>
Please generate unit tests for this code from buffer %d:

```%s
%s
```
</user_prompt>
]],
              context.bufnr,
              context.filetype,
              code
            )
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
    ["Fix code"] = {
      strategy = "chat",
      description = "Fix the selected code",
      opts = {
        index = 8,
        is_default = true,
        is_slash_cmd = false,
        modes = { "v" },
        short_name = "fix",
        auto_submit = true,
        user_prompt = false,
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = constants.SYSTEM_ROLE,
          content = [[When asked to fix code, follow these steps:

1. **Identify the Issues**: Carefully read the provided code and identify any potential issues or improvements.
2. **Plan the Fix**: Describe the plan for fixing the code in pseudocode, detailing each step.
3. **Implement the Fix**: Write the corrected code in a single code block.
4. **Explain the Fix**: Briefly explain what changes were made and why.

Ensure the fixed code:

- Includes necessary imports.
- Handles potential errors.
- Follows best practices for readability and maintainability.
- Is formatted correctly.

Use Markdown formatting and include the programming language name at the start of the code block.]],
        },
        {
          role = constants.USER_ROLE,
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(context.start_line, context.end_line)

            return fmt(
              [[Please fix this code from buffer %d:

```%s
%s
```
]],
              context.bufnr,
              context.filetype,
              code
            )
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
    ["Explain LSP Diagnostics"] = {
      strategy = "chat",
      description = "Explain the LSP diagnostics for the selected code",
      opts = {
        index = 9,
        is_default = true,
        is_slash_cmd = false,
        modes = { "v" },
        short_name = "lsp",
        auto_submit = true,
        user_prompt = false,
        stop_context_insertion = true,
      },
      prompts = {
        {
          role = constants.SYSTEM_ROLE,
          content = [[You are an expert coder and helpful assistant who can help debug code diagnostics, such as warning and error messages. When appropriate, give solutions with code snippets as fenced codeblocks with a language identifier to enable syntax highlighting.]],
        },
        {
          role = constants.USER_ROLE,
          content = function(context)
            local diagnostics = require("codecompanion.helpers.actions").get_diagnostics(
              context.start_line,
              context.end_line,
              context.bufnr
            )

            local concatenated_diagnostics = ""
            for i, diagnostic in ipairs(diagnostics) do
              concatenated_diagnostics = concatenated_diagnostics
                .. i
                .. ". Issue "
                .. i
                .. "\n  - Location: Line "
                .. diagnostic.line_number
                .. "\n  - Buffer: "
                .. context.bufnr
                .. "\n  - Severity: "
                .. diagnostic.severity
                .. "\n  - Message: "
                .. diagnostic.message
                .. "\n"
            end

            return fmt(
              [[The programming language is %s. This is a list of the diagnostic messages:

%s
]],
              context.filetype,
              concatenated_diagnostics
            )
          end,
        },
        {
          role = constants.USER_ROLE,
          content = function(context)
            local code = require("codecompanion.helpers.actions").get_code(
              context.start_line,
              context.end_line,
              { show_line_numbers = true }
            )
            return fmt(
              [[
This is the code, for context:

```%s
%s
```
]],
              context.filetype,
              code
            )
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
    ["Generate a Commit Message"] = {
      strategy = "chat",
      description = "Generate a commit message",
      opts = {
        index = 10,
        is_default = true,
        is_slash_cmd = true,
        short_name = "commit",
        auto_submit = true,
      },
      prompts = {
        {
          role = constants.USER_ROLE,
          content = function()
            local diff = vim.system({ "git", "diff", "--no-ext-diff", "--staged" }, { text = true }):wait()
            return string.format(
              [[You are an expert at following the Conventional Commit specification. Given the git diff listed below, please generate a commit message for me:

````diff
%s
````
]],
              diff.stdout
            )
          end,
          opts = {
            contains_code = true,
          },
        },
      },
    },
    ["Workspace File"] = {
      strategy = "chat",
      description = "Generate a Workspace file/group",
      opts = {
        index = 11,
        ignore_system_prompt = true,
        is_default = true,
        short_name = "workspace",
      },
      context = {
        {
          type = "file",
          path = {
            vim.fs.joinpath(vim.fn.getcwd(), "codecompanion-workspace.json"),
          },
        },
      },
      prompts = {
        {
          role = constants.SYSTEM_ROLE,
          content = function()
            local schema = require("codecompanion").workspace_schema()
            return fmt(
              [[## CONTEXT

A workspace is a JSON configuration file that organizes your codebase into related groups to help LLMs understand your project structure. Each group contains files, symbols, or URLs that provide context about specific functionality or features.

The workspace file follows this structure:

```json
%s
```

## OBJECTIVE

Create or modify a workspace file that effectively organizes the user's codebase to provide optimal context for LLM interactions.

## RESPONSE

You must create or modify a workspace file through a series of prompts over multiple turns:

1. First, ask the user about the project's overall purpose and structure if not already known
2. Then ask the user to identify key functional groups in your codebase
3. For each group, ask the user select relevant files, symbols, or URLs to include. Or, use your own knowledge to identify them
4. Generate the workspace JSON structure based on the input
5. Review and refine the workspace configuration together with the user]],
              schema
            )
          end,
        },
        {
          role = constants.USER_ROLE,
          content = function()
            local prompt = ""
            if vim.fn.filereadable(vim.fs.joinpath(vim.fn.getcwd(), "codecompanion-workspace.json")) == 1 then
              prompt = [[Can you help me add a group to an existing workspace file?]]
            else
              prompt = [[Can you help me create a workspace file?]]
            end

            local ok, _ = pcall(require, "vectorcode")
            if ok then
              prompt = prompt .. " Use the @{vectorcode_toolbox} tool to help identify groupings of files"
            end
            return prompt
          end,
        },
      },
    },
  },
  -- MEMORY -------------------------------------------------------------------
  memory = {
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
      is_default = true,
    },
    CodeCompanion = {
      description = "CodeCompanion plugin memory files",
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
        ["workflows"] = {
          description = "The workflow implementation",
          files = {
            ".codecompanion/workflows.md",
          },
        },
      },
      is_default = true,
    },
    parsers = {
      claude = "claude", -- Parser for CLAUDE.md files
      none = "none", -- No parsing, just raw text
    },
    opts = {
      chat = {
        enabled = false, -- Automatically add memory to new chat buffers?

        ---Function to determine if memory should be added to a chat buffer
        ---This requires `enabled` to be true
        ---@param chat CodeCompanion.Chat
        ---@return boolean
        condition = function(chat)
          return chat.adapter.type ~= "acp"
        end,

        default_memory = "default", -- The memory groups to load
        default_params = "watch", -- watch|pin - when adding a buffer to the chat
      },
      show_defaults = true, -- Show the default memory files in the action palette?
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
        show_default_actions = true, -- Show the default actions in the action palette?
        show_default_prompt_library = true, -- Show the default prompt library in the action palette?
        title = "CodeCompanion actions", -- The title of the action palette
      },
    },
    chat = {
      icons = {
        buffer_pin = " ",
        buffer_watch = "󰂥 ",
        --chat_context = " ",
        chat_fold = " ",
        tool_pending = "  ",
        tool_in_progress = "  ",
        tool_failure = "  ",
        tool_success = "  ",
      },
      -- Window options for the chat buffer
      window = {
        layout = "vertical", -- float|vertical|horizontal|buffer
        position = nil, -- left|right|top|bottom (nil will default depending on vim.opt.splitright|vim.opt.splitbelow)
        border = "single",
        height = 0.8,
        ---@type number|"auto" using "auto" will allow full_height buffers to act like normal buffers
        width = 0.45,
        relative = "editor",
        full_height = true,
        sticky = false, -- chat buffer remains open when switching tabs
        opts = {
          breakindent = true,
          cursorcolumn = false,
          cursorline = false,
          foldcolumn = "0",
          linebreak = true,
          list = false,
          numberwidth = 1,
          signcolumn = "no",
          spell = false,
          wrap = true,
        },
      },
      -- Options for any windows that open within the chat buffer
      child_window = {
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
        opts = {
          wrap = false,
          number = false,
          relativenumber = false,
        },
      },
      -- Extend/override the child_window options for a diff
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

      auto_scroll = true, -- Automatically scroll down and place the cursor at the end?
      intro_message = "Welcome to CodeCompanion ✨! Press ? for options",

      show_header_separator = false, -- Show header separators in the chat buffer? Set this to false if you're using an external markdown formatting plugin
      separator = "─", -- The separator between the different messages in the chat buffer

      show_context = true, -- Show context (from slash commands and variables) in the chat buffer?
      fold_context = false, -- Fold context in the chat buffer?

      show_reasoning = true, -- Show reasoning content in the chat buffer?
      fold_reasoning = true, -- Fold the reasoning content in the chat buffer?

      show_settings = false, -- Show LLM settings at the top of the chat buffer?
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

  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), args)

  M.config.strategies.chat.keymaps = remove_disabled_keymaps(M.config.strategies.chat.keymaps)
  M.config.strategies.inline.keymaps = remove_disabled_keymaps(M.config.strategies.inline.keymaps)

  -- TODO: Add a deprecation warning at some point
  if M.config.opts and M.config.opts.system_prompt then
    M.config.strategies.chat.opts.system_prompt = M.config.opts.system_prompt
    M.config.opts.system_prompt = nil
  end
end

M.can_send_code = function()
  if type(M.config.opts.send_code) == "boolean" then
    return M.config.opts.send_code
  elseif type(M.config.opts.send_code) == "function" then
    return M.config.opts.send_code()
  end
  return false
end

---Resolve a config value that might be a function or static value
---@param value any
---@return any
function M.resolve_value(value)
  return type(value) == "function" and value() or value
end

return setmetatable(M, {
  __index = function(_, key)
    if key == "setup" then
      return M.setup
    end
    return rawget(M.config, key)
  end,
})
