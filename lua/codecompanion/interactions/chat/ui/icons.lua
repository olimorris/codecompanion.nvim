local api = vim.api

---@class CodeCompanion.Chat.UI.Icons
local Icons = {}

local CONSTANTS = {
  NS_ICONS = api.nvim_create_namespace("CodeCompanion-icons"),
}

---@class CodeCompanion.Chat.UI.IconOpts
---@field icon? string The icon text to display
---@field icon_hl_group? string Highlight group for the icon
---@field line_hl_group? string Highlight group for the entire line
---@field priority? number Extmark priority (floor of 200)
---@field virt_text_pos? string Virtual text position

---Apply an icon extmark with optional line text highlighting
---@param bufnr number
---@param line number 0-based line number
---@param opts? CodeCompanion.Chat.UI.IconOpts
---@return number|nil The extmark id
function Icons.apply(bufnr, line, opts)
  opts = vim.tbl_deep_extend("force", {
    icon = "",
    icon_hl_group = "Comment",
    priority = 100,
    virt_text_pos = "overlay",
  }, opts or {})

  -- Clear any existing icons on this line to prevent duplicates
  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_ICONS, line, line + 1)

  local line_text = api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""

  return api.nvim_buf_set_extmark(bufnr, CONSTANTS.NS_ICONS, line, 0, {
    virt_text = { { opts.icon, opts.icon_hl_group } },
    virt_text_pos = opts.virt_text_pos,
    priority = math.max(opts.priority, 200),
    hl_group = opts.line_hl_group,
    end_col = #line_text,
  })
end

---Clear a specific tool icon from buffer
---@param bufnr number
---@param extmark_id number
---@return nil
function Icons.clear_icon(bufnr, extmark_id)
  if not extmark_id then
    return
  end
  api.nvim_buf_del_extmark(bufnr, CONSTANTS.NS_ICONS, extmark_id)
end

---Clear tool icons on a specific line
---@param bufnr number
---@param line number 0-based line number
function Icons.clear_line(bufnr, line)
  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_ICONS, line, line + 1)
end

---Clear all tool icons from buffer
---@param bufnr number
function Icons.clear_icons(bufnr)
  api.nvim_buf_clear_namespace(bufnr, CONSTANTS.NS_ICONS, 0, -1)
end

---Return the tool icons namespace ID
---@return number
function Icons.ns()
  return CONSTANTS.NS_ICONS
end

return Icons
