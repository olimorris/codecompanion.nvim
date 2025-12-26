--[[
  A large number of methods have been copied, directly, or slightly modified
  from the excellent diff module of sidekick.nvim by Folke:

  https://github.com/folke/sidekick.nvim/blob/main/lua/sidekick/treesitter.lua
--]]

local M = {}

local api = vim.api

---@type number?
M._scratch_buf = nil

---Create a scratch buffer to render content which we can then highlight
---@param content string
local function _scratch_buf(content)
  if not (M._scratch_buf and api.nvim_buf_is_valid(M._scratch_buf)) then
    M._scratch_buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(M._scratch_buf, "codecompanion://diff")
  end

  vim.bo[M._scratch_buf].fixeol = false
  vim.bo[M._scratch_buf].eol = false
  api.nvim_buf_set_lines(M._scratch_buf, 0, -1, false, vim.split(content, "\n", { plain = true }))

  return M._scratch_buf
end

---Get Tree-sitter highlights as extmarks
---@param source string|number
---@param opts? { ft: string, start_row?: number, end_row?: number }
local function _ts_highlight(source, opts)
  opts = opts or {}
  assert(type(source) == "number" or opts.ft, "Either bufnr or ft should be specified")

  local bufnr = type(source) == "number" and source or _scratch_buf(source --[[@as string]])

  local lang = vim.treesitter.language.get_lang(opts.ft or vim.bo[bufnr].filetype)

  local parser ---@type vim.treesitter.LanguageTree?
  if lang then
    lang = lang:lower()
    local ok = false
    ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    parser = ok and parser or nil
  end

  if not parser then
    return
  end

  local ret = {} ---@type CodeCompanion.diff.Extmark[]
  local skips = { spell = true, nospell = true, conceal = true }

  parser:parse(true)
  parser:for_each_tree(function(tstree, tree)
    if not tstree then
      return
    end
    local query = vim.treesitter.query.get(tree:lang(), "highlights")
    -- Some injected languages may not have highlight queries.
    if not query then
      return
    end

    for capture, node, metadata in query:iter_captures(tstree:root(), source, opts.start_row, opts.end_row) do
      ---@type string
      local name = query.captures[capture]
      if not skips[name] then
        local range = { node:range() } ---@type number[]
        local multi = range[1] ~= range[3]
        local text = multi
            and vim.split(vim.treesitter.get_node_text(node, source, metadata[capture]), "\n", { plain = true })
          or {}
        for row = range[1] + 1, range[3] + 1 do
          local first, last = row == range[1] + 1, row == range[3] + 1
          local end_col = last and range[4] or #(text[row - range[1]] or "")
          end_col = multi and first and end_col + range[2] or end_col
          ret[#ret + 1] = {
            row = row,
            col = first and range[2] or 0,
            end_col = end_col,
            priority = (tonumber(metadata.priority or metadata[capture] and metadata[capture].priority) or 100),
            conceal = metadata.conceal or metadata[capture] and metadata[capture].conceal,
            hl_group = "@" .. name .. "." .. lang,
          }
        end
      end
    end
  end)

  return ret
end

---Create the virtual lines and apply syntax highlighting via Tree-sitter
---@param source string|number
---@param opts? {ft:string, start_row?: integer, end_row?: integer, bg?: string}
---@return CodeCompanion.Text[]
function M.create_vl(source, opts)
  opts = opts or {}

  local lines = type(source) == "number"
      and api.nvim_buf_get_lines(source, opts.start_row or 0, opts.end_row or -1, false)
    or vim.split(source --[[@as string]], "\n")

  local extmarks = _ts_highlight(source, opts)
  if not extmarks then
    -- No treesitter highlighting available, but still apply background if specified
    return vim.tbl_map(function(line)
      local hl = opts.bg and { "Normal", opts.bg } or nil
      return { { line, hl } }
    end, lines)
  end

  local index = {} ---@type table<number, table<number, string>>
  for _, e in ipairs(extmarks) do
    e.row = e.row - (opts.start_row and opts.start_row or 0)
    if e.hl_group and e.end_col then
      index[e.row] = index[e.row] or {}
      for i = e.col + 1, e.end_col do
        index[e.row][i] = e.hl_group
      end
    end
  end

  local ret = {} ---@type CodeCompanion.Text[]
  for i = 1, #lines do
    local line = lines[i]
    local from = 0
    local hl_group = nil ---@type string?

    ---@param to number
    local function add(to)
      if to >= from then
        ret[i] = ret[i] or {}
        local text = line:sub(from, to)
        local hl = opts.bg and { hl_group or "Normal", opts.bg } or hl_group
        if #text > 0 then
          table.insert(ret[i], { text, hl })
        end
      end
      from = to + 1
      hl_group = nil
    end

    for col = 1, #line do
      local hl = index[i] and index[i][col]
      if hl ~= hl_group then
        add(col - 1)
        hl_group = hl
      end
    end
    add(#line)
  end

  return ret
end

---Extend virtual lines to full window width with background highlight
---@param vl CodeCompanion.Text[]
---@param hl_group string
---@return CodeCompanion.Text[]
function M.extend_vl(vl, hl_group)
  for _, vt in ipairs(vl) do
    table.insert(vt, { string.rep(" ", vim.o.columns), hl_group })
  end
  return vl
end

return M
