local context_utils = require("codecompanion.utils.context")

local M = {}

---Get prompts from the prompt library
---@return table
function M.get_prompts()
  local context = context_utils.get(vim.api.nvim_get_current_buf())
  return require("codecompanion.actions").get_cached_items(context)
end

---Get short names of prompts from the prompt library
---@return string[]
function M.get_prompt_aliases()
  local prompts = M.get_prompts()
  local aliases = {}
  vim.iter(prompts):each(function(k, _)
    if k.opts and k.opts.alias then
      table.insert(aliases, k.opts.alias)
    end
  end)
  return aliases
end

---Create and show a diff in a floating window
---@param args { from_lines: string[], to_lines: string[], ft: string, banner?: string, skip_action_keymaps?: boolean, chat_bufnr?: number, tool_name?: string, title?: string, diff_id: number }
---@return CodeCompanion.DiffUI
function M.show_diff(args)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("filetype", args.ft, { buf = bufnr })

  local Diff = require("codecompanion.diff")
  local diff_obj = Diff.create({
    bufnr = bufnr,
    ft = args.ft,
    from_lines = args.from_lines,
    to_lines = args.to_lines,
  })

  local diff_ui = require("codecompanion.diff.ui")
  return diff_ui.show(diff_obj, {
    banner = args.banner,
    chat_bufnr = args.chat_bufnr,
    diff_id = args.diff_id,
    skip_action_keymaps = args.skip_action_keymaps,
    title = args.title,
    tool_name = args.tool_name,
  })
end

return M
