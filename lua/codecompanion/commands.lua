---@class CodeCompanionCommandOpts:table
---@field desc string

---@class CodeCompanionCommand
---@field cmd string
---@field callback fun(args:table)
---@field opts CodeCompanionCommandOpts

local codecompanion = require("codecompanion")

local clean_up_prompt = function(prompt)
  return prompt:match("%s(.+)")
end

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
        -- if string.sub(opts.args, 1, 1) == "@" then
        --   local prompt = string.sub(opts.args, 2)
        --
        --   if string.match(prompt, "^(%S+)") == "buffers" then
        --     opts.args = clean_up_prompt(opts.args)
        --     table.insert(opts, { send_open_buffers = true })
        --   elseif string.match(prompt, "^(%S+)") == "buffer" then
        --     opts.args = clean_up_prompt(opts.args)
        --     table.insert(opts, { send_current_buffer = true })
        --   end
        --
        --   if codecompanion.pre_defined_prompts[prompt] then
        --     return codecompanion.run_pre_defined_prompts(prompt, opts)
        --   end
        -- end

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
}
