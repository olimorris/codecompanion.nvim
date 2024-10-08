local context = require("codecompanion.utils.context")
local log = require("codecompanion.utils.log")

local codecompanion = require("codecompanion")
local config = codecompanion.config

local prompt_library = vim
  .iter(config.prompt_library)
  :filter(function(_, v)
    return v.opts and v.opts.short_name
  end)
  :map(function(_, v)
    return "/" .. v.opts.short_name
  end)
  :totable()

---@class CodeCompanionCommandOpts:table
---@field desc string

---@class CodeCompanionCommand
---@field cmd string
---@field callback fun(args:table)
---@field opts CodeCompanionCommandOpts

---@type CodeCompanionCommand[]
return {
  {
    cmd = "CodeCompanion",
    callback = function(opts)
      if #vim.trim(opts.args or "") == 0 then
        vim.ui.input({ prompt = config.display.action_palette.prompt }, function(input)
          if #vim.trim(input or "") == 0 then
            return
          end
          opts.args = input
          codecompanion.inline(opts)
        end)
      else
        if string.sub(opts.args, 1, 1) == "/" then
          local user_prompt = nil
          -- Remove the leading slash
          local prompt = string.sub(opts.args, 2)

          local user_prompt_pos = string.find(prompt, " ")

          if user_prompt_pos then
            -- Extract the user_prompt first
            user_prompt = string.sub(prompt, user_prompt_pos + 1)
            prompt = string.sub(prompt, 1, user_prompt_pos - 1)

            log:trace("Prompt library call: %s", prompt)
            log:trace("User prompt: %s", user_prompt)
          end

          local prompts = vim
            .iter(config.prompt_library)
            :filter(function(_, v)
              return v.opts and v.opts.short_name and v.opts.short_name:lower() == prompt:lower()
            end)
            :map(function(k, v)
              v.name = k
              return v
            end)
            :nth(1)

          if prompts then
            if user_prompt then
              opts.user_prompt = user_prompt
            end
            return codecompanion.run_inline_prompt(prompts, opts)
          end
        end

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
            .iter(prompt_library)
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
