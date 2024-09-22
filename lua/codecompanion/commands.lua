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
          local slash_cmd = string.sub(opts.args, 2)

          local user_prompt_pos = string.find(slash_cmd, " ")

          if user_prompt_pos then
            -- Extract the user_prompt first
            user_prompt = string.sub(slash_cmd, user_prompt_pos + 1)
            slash_cmd = string.sub(slash_cmd, 1, user_prompt_pos - 1)

            log:trace("Slash cmd: %s", slash_cmd)
            log:trace("User prompt: %s", user_prompt)
          end

          if codecompanion.slash_cmds[slash_cmd] then
            if user_prompt then
              opts.user_prompt = user_prompt
            end
            return codecompanion.run_inline_slash_cmds(slash_cmd, opts)
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
  {
    cmd = "CodeCompanionToggle",
    callback = function()
      codecompanion.toggle()
    end,
    opts = { desc = "Toggle a CodeCompanion chat buffer" },
  },
  {
    cmd = "CodeCompanionAdd",
    callback = function(opts)
      codecompanion.add(opts)
    end,
    opts = { desc = "Add the current selection to a chat buffer", range = true },
  },
  {
    cmd = "CodeCompanionTelescope",
    callback = function(opts)
      require("telescope").extensions.codecompanion.codecompanion()
    end,
    opts = { desc = "Select a codecompanion action with telescope" },
  },
}
