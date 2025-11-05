local api = vim.api
local fn = vim.fn

local buffers = require("codecompanion.utils.buffers")
local mru = require("codecompanion.utils.mru")

local function safe_buf_get_lines(bufnr, start, finish)
  local ok, res = pcall(api.nvim_buf_get_lines, bufnr, start, finish, false)
  if ok and res then return res end
  return {}
end

local function choose_buf()
  local ok, candidate = pcall(function() return mru.find_mru_file_buffer() end)
  if ok and candidate and type(candidate) == "number" and candidate > 0 then
    return candidate
  end
  return api.nvim_get_current_buf()
end

local function get_cursor_for_buf(bufnr)
  -- Try to find a window showing that buffer and read its cursor
  local row, col
  for _, win in ipairs(api.nvim_list_wins()) do
    local okb, b = pcall(api.nvim_win_get_buf, win)
    if okb and b == bufnr then
      local okc, cur = pcall(api.nvim_win_get_cursor, win)
      if okc and cur then
        row, col = cur[1], cur[2]
        break
      end
    end
  end

  -- Fallback: try buffer-local mark '"' (last cursor) or current window
  if not row then
    local okm, mark = pcall(api.nvim_buf_get_mark, bufnr, '"')
    if okm and mark and type(mark) == 'table' and mark[1] then
      row, col = mark[1], mark[2]
    else
      local okc, cur = pcall(api.nvim_win_get_cursor, api.nvim_get_current_win())
      if okc and cur then
        row, col = cur[1], cur[2]
      else
        row, col = 1, 0
      end
    end
  end

  local line = (pcall(function() return api.nvim_buf_get_lines(bufnr, math.max(0, row - 1), row, false)[1] end) and api.nvim_buf_get_lines(bufnr, math.max(0, row - 1), row, false)[1]) or ""
  return { row = row, col = col, line = line }
end

local function run()
  local bufnr = choose_buf()

  local ok_info, info = pcall(function() return buffers.get_info(bufnr) end)
  if not ok_info then info = nil end

  local path = ""
  pcall(function()
    path = buffers.name_from_bufnr(bufnr) or ""
  end)

  local filetype = ""
  pcall(function() filetype = vim.bo[bufnr] and vim.bo[bufnr].filetype or "" end)

  local line_count = 0
  pcall(function() line_count = api.nvim_buf_line_count(bufnr) end)

  local cursor = get_cursor_for_buf(bufnr)

  -- Visible ranges and their text
  local ok_vis, visible = pcall(buffers.get_visible_lines)
  local visible_ranges = {}
  local visible_text = {}
  if ok_vis and type(visible) == "table" then
    local ranges = visible[bufnr] or {}
    for i, r in ipairs(ranges) do
      local start_row = r[1]
      local end_row = r[2]
      table.insert(visible_ranges, { start = start_row, ["end"] = end_row })
      -- collect text for this range (inclusive)
      local text = safe_buf_get_lines(bufnr, math.max(0, start_row - 1), end_row)
      table.insert(visible_text, table.concat(text, "\n"))
    end
  end

  -- Surrounding lines window (5 before/after default)
  local surround_before = {}
  local surround_after = {}
  pcall(function()
    local before_start = math.max(0, cursor.row - 1 - 5)
    local before_end = math.max(0, cursor.row - 1)
    surround_before = safe_buf_get_lines(bufnr, before_start, before_end)
    local after_start = math.min(line_count, cursor.row)
    local after_end = math.min(line_count, cursor.row + 5)
    surround_after = safe_buf_get_lines(bufnr, after_start, after_end)
  end)

  local data = {
    bufnr = bufnr,
    path = tostring(path),
    filename = (info and info.path) and fn.fnamemodify(info.path, ":t") or fn.fnamemodify(tostring(path), ":t"),
    filetype = tostring(filetype),
    line_count = line_count,
    cursor = cursor,
    current_line = cursor and cursor.line or "",
    visible_ranges = visible_ranges,
    visible_text = visible_text,
    surrounding = { before = surround_before, after = surround_after },
  }

  return { status = "success", data = data }
end

return {
  name = "get_editing_context",
  cmds = { function(self, args, input) return run() end },
  schema = {
    type = "function",
    ["function"] = {
      name = "get_editing_context",
      description = "Return a combined editor context for the most relevant buffer (bufnr, path, filename, filetype, line_count, cursor, visible_ranges, visible_text, surrounding).",
    },
  },
  output = {
    prompt = function()
      return "Return a machine-friendly editor context for the most relevant buffer: bufnr, path, filename, filetype, line_count, cursor (row,col,line), visible_ranges and their text, and surrounding lines."
    end,
    success = function(self, tools, cmd, stdout)
      -- unwrap similar to other tools
      local function unwrap(s)
        if type(s) ~= "table" then return s end
        if s.data and type(s.data) == "table" then return s.data end
        if #s and #s > 0 then return s[#s] end
        return s
      end

      local out = unwrap(stdout)
      if type(out) ~= "table" then
        return tools.chat:add_tool_output(self, tostring(out or ""))
      end

      local ok, inspected = pcall(vim.inspect, out)
      local for_llm = (ok and inspected) or tostring(out)

      -- Build a concise, user-friendly summary including a short preview of the current line
      local bufnr = tostring(out.bufnr or -1)
      local path = tostring(out.path or "")
      local filename = tostring(out.filename or path)
      local crow = tostring(out.cursor and out.cursor.row or "-")
      local ccol = tostring(out.cursor and out.cursor.col or "-")
      local current_line = tostring(out.current_line or "")
      local function truncate(s, n)
        if not s then return "" end
        if #s > n then return s:sub(1, n) .. "…" end
        return s
      end
      local line_preview = truncate(current_line:gsub("\n", " "), 120)
      local visible_summary = "none"
      if out.visible_ranges and #out.visible_ranges > 0 then
        local parts = {}
        for _, r in ipairs(out.visible_ranges) do
          table.insert(parts, string.format("%d-%d", r.start, r["end"]))
        end
        visible_summary = table.concat(parts, ", ")
      end

      local for_user = string.format("Buffer: %s | File: %s | Cursor: %s:%s | Line: %s | Visible: %s", bufnr, filename, crow, ccol, line_preview, visible_summary)

      tools.chat:add_tool_output(self, for_llm, for_user)
    end,
    error = function(self, tools, cmd, stderr)
      tools.chat:add_tool_output(self, tostring(stderr or "error"))
    end,
    rejected = function(self, tools, cmd, opts)
      tools.chat:add_tool_output(self, "Tool call rejected")
    end,
  },
}
