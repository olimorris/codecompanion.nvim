local M = {}

---Fold the most recent "### Reasoning" section using Tree-sitter.
---@param chat CodeCompanion.Chat
---@param opts? { include_header?: boolean, start_row?: integer, end_row?: integer }
function M.fold_latest(chat, opts)
  opts = opts or {}
  local include_header = opts.include_header
  if include_header == nil then
    include_header = true
  end

  local bufnr = chat.bufnr
  local parser = chat.parser
  if not (bufnr and parser) then
    return
  end

  local start_row = opts.start_row or 0
  local end_row = opts.end_row or -1

  local ok, query = pcall(
    vim.treesitter.query.parse,
    "markdown",
    [[
    (section
      (atx_heading
        (atx_h3_marker)
        heading_content: (_) @block_name
      )
      (#eq? @block_name "Reasoning")
    ) @reasoning
  ]]
  )
  if not ok or not query then
    return
  end

  local tree = parser:parse({ start_row, end_row })[1]
  if not tree then
    return
  end
  local root = tree:root()

  local latest_node, latest_sr = nil, -1
  for id, node in query:iter_captures(root, bufnr, start_row, end_row) do
    if query.captures[id] == "reasoning" then
      local sr = node:range()
      if sr >= latest_sr then
        latest_node, latest_sr = node, sr
      end
    end
  end
  if not latest_node then
    return
  end

  local sr, _, er = latest_node:range()
  local fold_start = include_header and sr or (sr + 1)
  local fold_end = math.max(fold_start, er - 2)

  -- Use the new reasoning fold API
  chat.ui.folds:create_reasoning_fold(bufnr, fold_start, fold_end, "Reasoning")
end

return M
