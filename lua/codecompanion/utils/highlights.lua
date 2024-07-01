local M = {}

function M.combine(default, target)
  local target_hl = vim.api.nvim_get_hl(0, { name = target })
  local combined = "CodeCompanionInline" .. target

  local opts = {
    bg = default.bg,
    fg = target_hl.fg,
    bold = target_hl.bold,
    italic = target_hl.italic,
    underline = target_hl.underline,
    undercurl = target_hl.undercurl,
    strikethrough = target_hl.strikethrough,
  }

  vim.api.nvim_set_hl(0, combined, opts)

  return combined
end

function M.get_hl_group(bufnr, line, col)
  local pos_info = vim.inspect_pos(bufnr, line - 1, col - 1)

  if pos_info.treesitter ~= nil and #pos_info.treesitter > 0 then
    local ts_hl = pos_info.treesitter[#pos_info.treesitter]
    local hl_group = ts_hl.hl_group_link or ts_hl.hl_group
    return hl_group
  elseif pos_info.syntax ~= nil and #pos_info.syntax > 0 then
    local syntax_hl = pos_info.syntax[#pos_info.syntax]
    local hl_group = syntax_hl.hl_group_link or syntax_hl.hl_group
    return hl_group
  else
    return "Normal"
  end
end

return M
