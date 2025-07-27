local Path = require("plenary.path")

local api = vim.api

local M = {}

---@param direction string
---@param count integer
---@return nil
function M.goto_heading(direction, count)
  local bufnr = api.nvim_get_current_buf()
  local cursor = api.nvim_win_get_cursor(0)
  local current_row = cursor[1] - 1

  local parser = vim.treesitter.get_parser(bufnr, "markdown")

  if parser == nil then
    vim.notify("Couldn't find the 'markdown' treesitter parser!")
    return
  end

  local root_tree = parser:parse()[1]:root()

  local query = vim.treesitter.query.parse("markdown", [[(atx_heading (atx_h2_marker) @heading)]])

  local from_row, to_row, found_headings
  if direction == "next" then
    from_row = current_row + 1
    to_row = -1 -- End of document
    found_headings = {}
    for id, node in query:iter_captures(root_tree, bufnr, from_row, to_row) do
      if query.captures[id] == "heading" then
        local node_start, _, _, _ = node:range()
        if node_start >= from_row then
          table.insert(found_headings, node) -- Collect valid headings in a table
          if #found_headings == count then -- Check if we have reached the desired count
            M.goto_node(found_headings[count], false, true)
            return
          end
        end
      end
    end
  elseif direction == "prev" then
    from_row = 0
    to_row = current_row
    found_headings = {}
    for id, node in query:iter_captures(root_tree, bufnr, from_row, to_row) do
      if query.captures[id] == "heading" then
        local _, _, node_end, _ = node:range()
        if node_end < current_row then
          table.insert(found_headings, node)
        end
      end
    end
    if #found_headings >= count then
      M.goto_node(found_headings[#found_headings - count + 1], false, true)
    end
  end

  -- If we haven't found the desired heading, we can stay at current position,
  -- or implement some behavior like wrapping around or signaling an error.
end

-- From nvim-treesitter @ 'master', not the 'main' rewrite.
function M.goto_node(node, goto_end, avoid_set_jump)
  if not node then
    return
  end

  if not avoid_set_jump then
    vim.cmd("normal! m'")
  end

  local range = { M.get_vim_range({ node:range() }) }

  ---@type table<number>
  local position
  if not goto_end then
    position = { range[1], range[2] }
  else
    position = { range[3], range[4] }
  end

  -- Enter visual mode if we are in operator pending mode
  -- If we don't do this, it will miss the last character.
  local mode = vim.api.nvim_get_mode()

  if mode.mode == "no" then
    vim.cmd("normal! v")
  end

  -- Position is 1, 0 indexed.
  api.nvim_win_set_cursor(0, { position[1], position[2] - 1 })
end

-- Get a compatible vim range (1 index based) from a TS node range.
--
-- TS nodes start with 0 and the end col is ending exclusive.
-- They also treat a EOF/EOL char as a char ending in the first
-- col of the next row.
---comment
---@param range integer[]
---@param buf integer|nil
---@return integer, integer, integer, integer
function M.get_vim_range(range, buf)
  ---@type integer, integer, integer, integer
  local srow, scol, erow, ecol = unpack(range)
  srow = srow + 1
  scol = scol + 1
  erow = erow + 1

  if ecol == 0 then
    -- Use the value of the last col of the previous row instead.
    erow = erow - 1
    if not buf or buf == 0 then
      ecol = vim.fn.col({ erow, "$" }) - 1
    else
      ecol = #api.nvim_buf_get_lines(buf, erow - 1, erow, false)[1]
    end
    ecol = math.max(ecol, 1)
  end

  return srow, scol, erow, ecol
end

---Get the range of two nodes
---@param start_node TSNode
---@param end_node TSNode
local function range_from_nodes(start_node, end_node)
  local row, col = start_node:start()
  local end_row, end_col = end_node:end_()
  return {
    lnum = row + 1,
    end_lnum = end_row + 1,
    col = col,
    end_col = end_col,
  }
end

---Extract symbols from a file using Tree-sitter
---@param filepath string The path to the file
---@param target_kinds? string[] Optional list of symbol kinds to include (default: all)
---@return table[]|nil symbols Array of symbols with name, kind, start_line, end_line
---@return string|nil content File content if successful
function M.extract_file_symbols(filepath, target_kinds)
  local ft = vim.filetype.match({ filename = filepath })
  if not ft then
    local base_name = vim.fs.basename(filepath)
    local split_name = vim.split(base_name, "%.")
    if #split_name > 1 then
      local ext = split_name[#split_name]
      if ext == "ts" then
        ft = "typescript"
      end
    end
  end

  if not ft then
    return nil, nil
  end

  local ok, content = pcall(function()
    return Path.new(filepath):read()
  end)

  if not ok then
    return nil, nil
  end

  local query = vim.treesitter.query.get(ft, "symbols")
  if not query then
    return nil, content
  end

  local parser = vim.treesitter.get_string_parser(content, ft)
  local tree = parser:parse()[1]

  local symbols = {}
  for _, matches, metadata in query:iter_matches(tree:root(), content) do
    local match = vim.tbl_extend("force", {}, metadata)
    for id, nodes in pairs(matches) do
      local node = type(nodes) == "table" and nodes[1] or nodes
      match = vim.tbl_extend("keep", match, {
        [query.captures[id]] = {
          metadata = metadata[id],
          node = node,
        },
      })
    end

    local name_match = match.name or {}
    local symbol_node = (match.symbol or match.type or {}).node

    if not symbol_node then
      goto continue
    end

    local start_node = (match.start or {}).node or symbol_node
    local end_node = (match["end"] or {}).node or start_node
    local kind = match.kind

    -- Filter by target kinds if specified
    if target_kinds and not vim.tbl_contains(target_kinds, kind) then
      goto continue
    end

    local range = range_from_nodes(start_node, end_node)
    local symbol_name = name_match.node and vim.trim(vim.treesitter.get_node_text(name_match.node, content))
      or "<unknown>"

    table.insert(symbols, {
      name = symbol_name,
      kind = kind,
      start_line = range.lnum,
      end_line = range.end_lnum,
      -- Keep original format for symbols.lua compatibility
      range = range,
    })

    ::continue::
  end

  return symbols, content
end

return M
