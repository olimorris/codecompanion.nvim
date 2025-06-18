---@class CodeCompanion.Command
---@field cmd string
---@field callback fun(args:table)
---@field opts CodeCompanion.Command.Opts

---@class CodeCompanion.Command.Opts:table
---@field desc string

local codecompanion = require("codecompanion")
local config = require("codecompanion.config")

-- Create the short name prompt library items table
local prompts = vim.iter(config.prompt_library):fold({}, function(acc, key, value)
  if value.opts and value.opts.short_name then
    acc[value.opts.short_name] = value
  end
  return acc
end)

local adapters = vim
  .iter(config.adapters)
  :filter(function(k, _)
    return k ~= "non_llm" and k ~= "opts"
  end)
  :map(function(k, _)
    return k
  end)
  :totable()

local inline_subcommands = vim.deepcopy(adapters)
vim.iter(prompts):each(function(k, _)
  table.insert(inline_subcommands, "/" .. k)
end)

local chat_subcommands = vim.deepcopy(adapters)
table.insert(chat_subcommands, "Toggle")
table.insert(chat_subcommands, "Add")
table.insert(chat_subcommands, "RefreshCache")

---@type CodeCompanion.Command[]
return {
  {
    cmd = "CodeCompanion",
    callback = function(opts)
      -- Detect the user calling a prompt from the prompt library
      if opts.fargs[1] and string.sub(opts.fargs[1], 1, 1) == "/" then
        -- Get the prompt minus the slash
        local prompt = string.sub(opts.fargs[1], 2)

        if prompts[prompt] then
          if #opts.fargs > 1 then
            opts.user_prompt = table.concat(opts.fargs, " ", 2)
          end
          return codecompanion.prompt_library(prompts[prompt], opts)
        end
      end

      -- If the user calls the command with no prompt, then ask for their input
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
            .iter(inline_subcommands)
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
      desc = "Work with a CodeCompanion chat buffer",
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
