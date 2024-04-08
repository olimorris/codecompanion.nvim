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
        vim.ui.input({ prompt = "Prompt" }, function(input)
          if #vim.trim(input or "") == 0 then
            return
          end
          opts.args = input
          codecompanion.inline(opts)
        end)
      else
        codecompanion.inline(opts)
      end
    end,
    opts = {
      desc = "Trigger CodeCompanion inline",
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
}
