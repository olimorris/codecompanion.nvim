local api = vim.api
local get_node_text = vim.treesitter.get_node_text --[[@as function]]
local get_query = vim.treesitter.query.get --[[@as function]]

local M = {}

---@type table<number, { lines: number, headers: number[] }>
local _cache = {}

---Add an event handler to ensure that the cache is cleared
api.nvim_create_autocmd({ "User" }, {
  pattern = { "CodeCompanionChatCleared", "CodeCompanionChatClosed" },
  callback = function(request)
    pcall(function()
      _cache[request.data.bufnr] = nil
    end)
  end,
})

---Remove the separator from any heading text
---@param text string
---@return string
local function strip_separator(text)
  local config = require("codecompanion.config")

  --INFO: This mirrors helpers.format_role
  if config.display.chat.show_header_separator then
    text = vim.trim(text:gsub(config.display.chat.separator, ""))
  end
  return text
end

---Use Tree-sitter to scan the buffer for role headers (not just H2 headers)
---@param args { bufnr: number, roles: string[], from_row: number }
---@return number[] 0-based row numbers of headers
local function scan_headers(args)
  local parser = vim.treesitter.get_parser(args.bufnr, "markdown")
  local tree = parser:parse({ args.from_row, -1 })[1]
  local root = tree:root()

  local query = get_query("markdown", "chat")
  if not query then
    return {}
  end

  local headers = {}
  for id, node in query:iter_captures(root, args.bufnr, args.from_row, -1) do
    local capture = query.captures[id]
    if capture == "role" or capture == "role_only" then
      local text = strip_separator(get_node_text(node, args.bufnr))
      for _, role in ipairs(args.roles) do
        if string.find(text, role, 1, true) == 1 then
          local row = node:parent():range()
          table.insert(headers, row)
          break
        end
      end
    end
  end

  return headers
end

---Get cached or new headers for a given buffer
---@param args { bufnr: number, roles: string[] }
---@return number[]
local function get_headers(args)
  local line_count = api.nvim_buf_line_count(args.bufnr)
  local cached = _cache[args.bufnr]

  if not cached or line_count < cached.lines then
    local headers = scan_headers({ bufnr = args.bufnr, roles = args.roles, from_row = 0 })
    _cache[args.bufnr] = { lines = line_count, headers = headers }
    return headers
  end

  if line_count == cached.lines then
    return cached.headers
  end

  -- If there are more lines than before, scan only the new lines and append to the cache
  local new_headers = scan_headers({ bufnr = args.bufnr, roles = args.roles, from_row = cached.lines })
  vim.list_extend(cached.headers, new_headers)
  cached.lines = line_count

  return cached.headers
end

---Navigate to the next or previous role header
---@param args { direction: string, count: number, roles: string[] }
---@return nil
function M.goto_heading(args)
  local bufnr = api.nvim_get_current_buf()
  local headers = get_headers({ bufnr = bufnr, roles = args.roles })
  if #headers == 0 then
    return
  end

  local cursor_row = api.nvim_win_get_cursor(0)[1] - 1
  local target = nil

  if args.direction == "next" then
    local remaining = args.count
    for _, row in ipairs(headers) do
      if row > cursor_row then
        remaining = remaining - 1
        if remaining == 0 then
          target = row
          break
        end
      end
    end
  else
    local remaining = args.count
    for i = #headers, 1, -1 do
      if headers[i] < cursor_row then
        remaining = remaining - 1
        if remaining == 0 then
          target = headers[i]
          break
        end
      end
    end
  end

  if target then
    api.nvim_win_set_cursor(0, { target + 1, 0 })
  end
end

return M
