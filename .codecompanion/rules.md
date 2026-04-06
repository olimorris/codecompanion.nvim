# Rules

In CodeCompanion, rules enable a user to quickly share context with an LLM or an agent.

Rules files are markdown files that contain context about a specific feature or behaviour, generally. They can be parsed by a parser which can extract text and file paths from them, adding them to the chat buffer as it goes.

## Init

@./lua/codecompanion/interactions/chat/rules/init.lua

This picks up the rules from a users config and contains methods which allows them to be added to the chat buffer's context.

## Helpers

@./lua/codecompanion/interactions/chat/rules/helpers.lua

This contains some helper functions that allow rules files to add context to the chat buffer.

## Parsers

@./lua/codecompanion/interactions/chat/rules/parsers/init.lua
@./lua/codecompanion/interactions/chat/rules/parsers/claude.lua
@./lua/codecompanion/interactions/chat/rules/parsers/codecompanion.lua
@./lua/codecompanion/interactions/chat/rules/parsers/none.lua

These are the files that allow CodeCompanion to read a user's markdown rule file and extract its content according to the parser, ready for sharing in the chat buffer. For example, with the Claude parser, file paths are extracted and those files are then shared as buffer or file context with the LLM, alongside any text.

## Slash Command

@./lua/codecompanion/interactions/chat/slash_commands/builtin/rules.lua

This slash command allows users to select a given rule and load it into the chat buffer

## Config

The default config for rules is:

````lua
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
        ["rules"] = {
          description = "Rules in the plugin",
          files = {
            ".codecompanion/rules.md",
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
````
