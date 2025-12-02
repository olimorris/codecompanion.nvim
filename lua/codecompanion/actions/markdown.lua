local config = require("codecompanion.config")
local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")
local yaml = require("codecompanion.utils.yaml")

local M = {}

local allowed_roles = {
  config.constants.SYSTEM_ROLE,
  config.constants.USER_ROLE,
}

---Load all markdown prompts from a directory
---@param dir string
---@param context CodeCompanion.BufferContext
---@return table
function M.load_from_dir(dir, context)
  local prompts = {}

  dir = vim.fs.normalize(dir)

  if not file_utils.is_dir(dir) then
    log:trace("Directory does not exist or is not a directory: %s", dir)
    return prompts
  end

  -- Scan directory for .md files
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return prompts
  end

  while true do
    local name, type = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end

    -- Only process .md files
    if type == "file" and name:match("%.md$") then
      local path = vim.fs.joinpath(dir, name)
      local ok, prompt = pcall(M.parse_file, path, context)

      if ok and prompt then
        prompt.name = prompt.name or vim.fn.fnamemodify(path, ":t:r")
        table.insert(prompts, prompt)
      end
    end
  end

  return prompts
end

---Parse a single markdown file into a prompt definition
---@param path string Path to the markdown file
---@param context CodeCompanion.BufferContext
---@return table|nil
function M.parse_file(path, context)
  local content = file_utils.read(path)
  if not content or content == "" then
    return nil
  end

  local sidecar = nil
  local sidecar_path = path:gsub("%.md$", ".lua")
  if file_utils.exists(sidecar_path) then
    sidecar = sidecar_path
  end

  local frontmatter = M.parse_frontmatter(content)
  if not frontmatter or not frontmatter.strategy or not frontmatter.name then
    log:warn("[Prompt Library] Missing frontmatter, name or strategy in: %s", path)
    return nil
  end

  local prompts = M.parse_prompt(content)

  return {
    description = frontmatter.description or "",
    name = frontmatter.name,
    opts = frontmatter.opts or {},
    path = path,
    prompts = prompts,
    sidecar = sidecar,
    strategy = frontmatter.strategy,
  }
end

---Extract YAML frontmatter from markdown content
---@param content string The full markdown file content
---@return table|nil Parsed frontmatter as a Lua table
function M.parse_frontmatter(content)
  content = content:match("^%-%-%-\n(.-)%-%-%-")
  if not content then
    return
  end

  local ok, parser = pcall(vim.treesitter.get_string_parser, content, "yaml")
  if not ok then
    return
  end

  local query = vim.treesitter.query.get("yaml", "prompt_library")
  local tree = parser:parse()

  local root = tree[1]:root()
  if root:has_error() then
    return log:warn("[Prompt Library] YAML parse error in markdown frontmatter")
  end

  local frontmatter = {}
  local pending_key = nil
  local processed_parents = {}

  for id, node in query:iter_captures(root, content, 0, -1) do
    local capture_name = query.captures[id]

    if capture_name == "cc_top_key" then
      pending_key = vim.treesitter.get_node_text(node, content)
    elseif capture_name == "cc_top_value" then
      if pending_key then
        frontmatter[pending_key] = yaml.decode_node(content, node)
        pending_key = nil
      end
    elseif capture_name == "cc_nested_parent_key" then
      local key = vim.treesitter.get_node_text(node, content)
      if not processed_parents[key] then
        processed_parents[key] = true
        -- Navigate up to the block_mapping_pair node
        -- Hierarchy: string_scalar -> plain_scalar -> flow_node -> block_mapping_pair
        local current = node
        while current and current:type() ~= "block_mapping_pair" do
          current = current:parent()
        end
        if current and current:type() == "block_mapping_pair" then
          local value_node = current:named_child(1)
          if value_node then
            frontmatter[key] = yaml.decode_node(content, value_node)
          end
        end
      end
    end
  end

  return frontmatter
end

---Extract prompt definitions from markdown content
---@param content string The full markdown file content
---@return table|nil
function M.parse_prompt(content)
  if not content then
    return nil
  end

  local parser = vim.treesitter.get_string_parser(content, "markdown")
  local query = vim.treesitter.query.get("markdown", "chat")
  if not query then
    return nil
  end

  local tree = parser:parse()
  local root = tree[1]:root()
  local get_node_text = vim.treesitter.get_node_text --[[@as function]]

  local prompts = {}
  local current_role = nil
  local current_content = {}

  local function store_prompt()
    if current_role and #current_content > 0 then
      local prompt_content = vim.trim(table.concat(current_content, "\n"))
      if prompt_content ~= "" then
        table.insert(prompts, {
          role = current_role,
          content = prompt_content,
        })
      end
    end
  end

  for capture_id, node in query:iter_captures(root, content, 0, -1) do
    local capture_name = query.captures[capture_id]

    if capture_name == "role" then
      store_prompt()
      current_role = vim.trim(get_node_text(node, content):lower())
      current_content = {}
    elseif capture_name == "content" and current_role and vim.tbl_contains(allowed_roles, current_role) then
      table.insert(current_content, get_node_text(node, content))
    end
  end

  store_prompt()

  if #prompts == 0 then
    return nil
  end

  return prompts
end

---Execute sidecar functions to resolve placeholders
---@param item table The prompts structure with placeholders
---@param context CodeCompanion.BufferContext
---@return nil
function M.resolve_placeholders(item, context)
  local placeholders = utils.extract_all_placeholders(item.prompts)
  if #placeholders == 0 then
    return item
  end

  local args = {
    context = context,
    item = item,
  }

  local sidecar = {}
  if item.sidecar then
    local ok, loaded = pcall(dofile, item.sidecar)
    if ok and type(loaded) == "table" then
      sidecar = loaded
    elseif ok then
      log:error("[Prompt Library] Sidecar file must return a table: %s", item.sidecar)
    else
      log:error("[Prompt Library] Failed to load sidecar file: %s", item.sidecar)
    end
  end

  local loaded_files = {}
  local dir = vim.fn.fnamemodify(item.path, ":p:h")

  ---Load a lua file from the same directory as the prompt
  ---@param filename string
  ---@return table|nil
  local function load_file_from_dir(filename)
    if loaded_files[filename] then
      return loaded_files[filename]
    end

    local file_path = vim.fs.joinpath(dir, filename .. ".lua")
    if file_utils.exists(file_path) then
      local ok, loaded = pcall(dofile, file_path)
      if ok and type(loaded) == "table" then
        loaded_files[filename] = loaded
        return loaded
      elseif ok then
        log:error("[Prompt Library] File must return a table: %s", file_path)
      else
        log:error("[Prompt Library] Failed to load file: %s", file_path)
      end
    end
    return nil
  end

  local replacements = {}
  for _, placeholder in ipairs(placeholders) do
    -- Replace sidecar variables first
    if type(sidecar[placeholder]) == "function" then
      local success, result = pcall(sidecar[placeholder], args)
      if success then
        replacements[placeholder] = tostring(result)
      else
        log:error("[Prompt Library] Sidecar function '%s' failed: %s", placeholder, result)
      end
    else
      -- Start resolving context or dot-notation placeholders

      -- Check if it's a dot-notation placeholder (e.g., "shared.code", "utils.helper")
      local dot_placeholder = placeholder:match("^([^.]+)%.")
      if dot_placeholder then
        -- Try to load the file from the prompt directory
        local loaded = load_file_from_dir(dot_placeholder)
        if loaded then
          args[dot_placeholder] = loaded
        end
      end

      local resolved = utils.resolve_nested_value(args, placeholder)
      if resolved ~= nil then
        if type(resolved) == "function" then
          local success, result = pcall(resolved, args)
          if success then
            replacements[placeholder] = tostring(result)
          else
            log:error("[Prompt Library] Function `%s` failed: %s", placeholder, result)
          end
        else
          replacements[placeholder] = tostring(resolved)
        end
      else
        log:warn("[Prompt Library] Could not resolve `${%s}` in %s", placeholder, item.path)
      end
    end
  end

  if vim.tbl_count(replacements) > 0 then
    utils.replace_placeholders(item.prompts, replacements)
  end

  return item
end

return M
