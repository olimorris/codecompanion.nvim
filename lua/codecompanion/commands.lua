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
  {
    cmd = "CodeCompanionComplete",
    callback = function(opts)
      local api = vim.api
      local buf = api.nvim_get_current_buf()
      local filetype = api.nvim_buf_get_option(buf, "filetype")
      -- Get full buffer lines
      local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
      local cursor = api.nvim_win_get_cursor(0)
      local row, col = cursor[1], cursor[2]
      local content_lines = vim.deepcopy(lines)
      local line = content_lines[row] or ""
      local prefix = line:sub(1, col)
      local suffix = line:sub(col + 1)
      content_lines[row] = prefix .. "<cursor>" .. suffix
      local buffer_with_cursor = table.concat(content_lines, "\n")
      -- Build the prompt
      local user_prompt = string.format(
        "Here is the current buffer with a <cursor> marker:\n```%s\n%s\n```\nPlease complete the code at the <cursor> position.",
        filetype,
        buffer_with_cursor
      )
      opts.args = user_prompt
      -- For CodeCompanionComplete, apply edits directly without diff approval
      opts.opts = opts.opts or {}
      opts.opts.no_diff = true
      codecompanion.inline(opts)
    end,
    opts = {
      desc = "Complete code at the cursor and auto-apply without diff",
      range = false,
      nargs = 0,
    },
  },
}
