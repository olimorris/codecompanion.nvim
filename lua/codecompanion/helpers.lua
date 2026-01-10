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
---@param args { from_lines: string[], to_lines: string[], ft: string, banner?: string, skip_default_keymaps?: boolean, chat_bufnr?: number, inline?: boolean, tool_name?: string, title?: string, diff_id: number, marker_add?: string, marker_delete?: string }
---@return CodeCompanion.DiffUI
function M.show_diff(args)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("filetype", args.ft, { buf = bufnr })

  local diff = require("codecompanion.diff")
  local ui = require("codecompanion.diff.ui")

  return ui.show(
    diff.create({
      bufnr = bufnr,
      ft = args.ft,
      from_lines = args.from_lines,
      to_lines = args.to_lines,
      marker_add = args.marker_add,
      marker_delete = args.marker_delete,
    }),
    {
      banner = args.banner,
      chat_bufnr = args.chat_bufnr,
      diff_id = args.diff_id,
      inline = args.inline or false,
      skip_default_keymaps = args.skip_default_keymaps,
      title = args.title,
      tool_name = args.tool_name,
    }
  )
end

return M
