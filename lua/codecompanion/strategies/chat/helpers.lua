local base64 = require("codecompanion.utils.base64")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local path = require("plenary.path")
local get_node_text = vim.treesitter.get_node_text

local M = {}

---Format the given role without any separator
---@param role string
---@return string
function M.format_role(role)
  if config.display.chat.show_header_separator then
    role = vim.trim(role:gsub(config.display.chat.separator, ""))
  end
  return role
end

---Strip any references from the messages
---@param messages table
---@return table
function M.strip_references(messages)
  local i = 1
  while messages[i] and messages[i]:sub(1, 1) == ">" do
    table.remove(messages, i)
    -- we do not increment i, since removing shifts everything down
  end
  return messages
end

---Get the keymaps from the slash commands
---@param slash_commands table
---@return table
function M.slash_command_keymaps(slash_commands)
  local keymaps = {}
  for k, v in pairs(slash_commands) do
    if v.keymaps then
      keymaps[k] = {}
      keymaps[k].description = v.description
      keymaps[k].callback = "keymaps." .. k
      keymaps[k].modes = v.keymaps.modes
    end
  end

  return keymaps
end

---Base64 encode the given image
---@param image table The image object containing the path and other metadata.
---@return {base64: string, mimetype: string}|string The base64 encoded image string
function M.encode_image(image)
  local b64_content, b64_err = base64.encode(image.path)
  if b64_err then
    return b64_err
  end

  image.base64 = b64_content

  if not image.mimetype then
    image.mimetype = base64.get_mimetype(image.path)
  end

  return image
end

---Add an image to the chat buffer
---@param Chat CodeCompanion.Chat The chat instance
---@param image table The image object containing the path and other metadata
---@param opts table Options for adding the image
---@return nil
function M.add_image(Chat, image, opts)
  opts = opts or {}

  local id = "<image>" .. (image.id or image.path) .. "</image>"

  Chat:add_message({
    role = opts.role or config.constants.USER_ROLE,
    content = image.base64,
  }, { reference = id, mimetype = image.mimetype, tag = "image", visible = false })

  Chat.references:add({
    bufnr = opts.bufnr or image.bufnr,
    id = id,
    path = image.path,
    source = opts.source or "codecompanion.strategies.chat.slash_commands.image",
  })
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
    return path.new(filepath):read()
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
    local symbol_name = name_match.node and vim.trim(get_node_text(name_match.node, content)) or "<unknown>"

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
