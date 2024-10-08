local log = require("codecompanion.utils.log")

---@class CodeCompanionCommandOpts:table
---@field desc string

---@class CodeCompanionCommand
---@field cmd string
---@field callback fun(args:table)
---@field opts CodeCompanionCommandOpts

local codecompanion = require("codecompanion")

---@type CodeCompanionCommand[]
return {
  {
    cmd = "CodeCompanion",
    callback = function(opts)
      if #vim.trim(opts.args or "") == 0 then
        vim.ui.input({ prompt = require("codecompanion").config.display.action_palette.prompt }, function(input)
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
            .iter(require("codecompanion").config.prompt_library)
            :filter(function(k, v)
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
      desc = "Start a custom prompt",
      range = true,
      nargs = "*",
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
