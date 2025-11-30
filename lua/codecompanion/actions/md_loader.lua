local config = require("codecompanion.config")
local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
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
function M.load_dir(dir, context)
  local prompts = {}

  dir = vim.fs.normalize(dir)

  -- Check that absolute path
  if not file_utils.is_dir(dir) then
    -- ...then the relative path
    dir = vim.fs.joinpath(vim.fn.getcwd(), dir)
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

  -- Parse the frontmatter
  local frontmatter = M.parse_frontmatter(content)
  if not frontmatter or not frontmatter.strategy then
    log:debug("[actions::md_loader] Missing frontmatter or strategy in: %s", path)
    return nil
  end

  local prompts = M.parse_prompt(content)

  return {
    strategy = frontmatter.strategy,
    description = frontmatter.description or "",
    opts = frontmatter.opts or {},
    prompts = prompts,
    context = frontmatter.context,
    condition = frontmatter.condition,
    picker = frontmatter.picker,
    name_f = frontmatter.name_f,
  }
end

---Extract YAML frontmatter from markdown content
---@param content string The full markdown file content
---@return table|nil Parsed frontmatter as a Lua table
function M.parse_frontmatter(content)
  content = content:match("^%-%-%-\n(.-)%-%-%-")
  if not content then
    log:debug("[actions::md_loader] No YAML frontmatter found")
    return nil
  end

  local ok, parser = pcall(vim.treesitter.get_string_parser, content, "yaml")
  if not ok then
    return
  end

  local query = vim.treesitter.query.get("yaml", "prompt_library")
  local tree = parser:parse()

  local root = tree[1]:root()
  if root:has_error() then
    log:warn("[Prompt Library] YAML parse error in markdown frontmatter")
    return nil
  end

  local frontmatter = {}
  local nested_values = {}

  for id, node in query:iter_captures(root, content, 0, -1) do
    local capture_name = query.captures[id]
    local text = vim.treesitter.get_node_text(node, content)

    if capture_name == "cc_top_key" then
      frontmatter._pending_key = text
    elseif capture_name == "cc_top_value" then
      if frontmatter._pending_key then
        frontmatter[frontmatter._pending_key] = yaml.decode(text)
        frontmatter._pending_key = nil
      end
    elseif capture_name == "cc_nested_parent_key" then
      if not frontmatter[text] then
        frontmatter[text] = {}
      end
      nested_values._current_parent = text
    elseif capture_name == "cc_nested_key" then
      nested_values._pending_key = text
    elseif capture_name == "cc_nested_value" then
      if nested_values._current_parent and nested_values._pending_key then
        frontmatter[nested_values._current_parent][nested_values._pending_key] = yaml.decode(text)
        nested_values._pending_key = nil
      end
    end
  end

  frontmatter._pending_key = nil

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

  -- Group prompts accordingly
  local seen_roles = {}
  local grouped_prompts = { {} }

  for _, prompt in ipairs(prompts) do
    if seen_roles[prompt.role] then
      table.insert(grouped_prompts, {})
      seen_roles = {}
    end
    table.insert(grouped_prompts[#grouped_prompts], prompt)
    seen_roles[prompt.role] = true
  end

  if vim.tbl_count(grouped_prompts[1]) == 0 then
    return nil
  end

  return grouped_prompts
end

return M
