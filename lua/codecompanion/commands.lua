---@class CodeCompanionCommandOpts:table
---@field desc string

---@class CodeCompanionCommand
---@field cmd string
---@field callback fun(args:table)
---@field opts CodeCompanionCommandOpts

local codecompanion = require("codecompanion")
local config = require("codecompanion.config")

local adapters = vim
  .iter(config.adapters)
  :filter(function(k, _)
    return k ~= "non_llms" and k ~= "opts"
  end)
  :map(function(k, _)
    return k
  end)
  :totable()

local chat_subcommands = vim.deepcopy(adapters)
table.insert(chat_subcommands, "Toggle")
table.insert(chat_subcommands, "Add")

---@type CodeCompanionCommand[]
return {
  {
    cmd = "CodeCompanion",
    callback = function(opts)
      -- If the user calls the command with no prompt, then prompt them
      if #vim.trim(opts.args or "") == 0 then
        vim.ui.input({ prompt = config.display.action_palette.prompt }, function(input)
          if #vim.trim(input or "") == 0 then
            return
          end
          opts.args = input
          return codecompanion.inline(opts)
        end)
      else
        codecompanion.inline(opts)
      end
    end,
    opts = {
      desc = "Use the CodeCompanion Inline Assistant",
      range = true,
      nargs = "*",
      -- Reference:
      -- https://github.com/nvim-neorocks/nvim-best-practices?tab=readme-ov-file#speaking_head-user-commands
      complete = function(arg_lead, cmdline, _)
        if cmdline:match("^['<,'>]*CodeCompanion[!]*%s+%w*$") then
          return vim
            .iter(adapters)
            :filter(function(key)
              return key:find(arg_lead) ~= nil
            end)
            :totable()
        end
      end,
    },
  },
  {
    cmd = "CodeCompanionChat",
    callback = function(opts)
      codecompanion.chat(opts)
    end,
    opts = {
      desc = "Open a CodeCompanion chat buffer",
      range = true,
      nargs = "*",
      -- Reference:
      -- https://github.com/nvim-neorocks/nvim-best-practices?tab=readme-ov-file#speaking_head-user-commands
      complete = function(arg_lead, cmdline, _)
        if cmdline:match("^['<,'>]*CodeCompanionChat[!]*%s+%w*$") then
          return vim
            .iter(chat_subcommands)
            :filter(function(key)
              return key:find(arg_lead) ~= nil
            end)
            :totable()
        end
      end,
    },
  },
  {
    cmd = "CodeCompanionCmd",
    callback = function(opts)
      codecompanion.cmd(opts)
    end,
    opts = {
      desc = "Prompt the LLM to write a command for the command-line",
      range = false,
      nargs = "*",
    },
  },

  {
    cmd = "CodeCompanionActions",
    callback = function(opts)
      codecompanion.actions(opts)
    end,
    opts = {
      desc = "Open the CodeCompanion actions palette",
      range = true,
    },
  },
}
