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
function M.get_short_name_prompts()
  local prompts = M.get_prompts()
  local short_names = {}
  vim.iter(prompts):each(function(k, _)
    if k.opts and k.opts.short_name then
      table.insert(short_names, k.opts.short_name)
    end
  end)
  return short_names
end

return M
