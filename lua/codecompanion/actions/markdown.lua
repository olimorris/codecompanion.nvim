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
    log:trace("Directory `%s` does not exist or is not a directory", dir)
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

  local frontmatter = M.parse_frontmatter(content)
  if not frontmatter or not frontmatter.strategy or not frontmatter.name then
    log:warn("[Prompt Library] Missing frontmatter, name or strategy in `%s`", path)
    return nil
  end

  local prompts = M.parse_prompt(content, frontmatter)

  return {
    description = frontmatter.description or "",
    name = frontmatter.name,
    opts = frontmatter.opts or {},
    path = path,
    prompts = prompts,
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

---Extract options from a YAML options code block
---@param code_block_content string The content of the code block
---@return table|nil
local function parse_options_block(code_block_content)
  local ok, parser = pcall(vim.treesitter.get_string_parser, code_block_content, "yaml")
  if not ok then
    return nil
  end

  local tree = parser:parse()
  local root = tree[1]:root()

  if root:has_error() then
    return log:warn("[Prompt Library] YAML parse error in options block")
  end

  return yaml.decode_node(code_block_content, root)
end

---Extract prompt definitions from markdown content
---@param content string The full markdown file content
---@param frontmatter table The parsed frontmatter
---@return table|nil
function M.parse_prompt(content, frontmatter)
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
  local current_opts = nil

  local function store_prompt()
    if current_role and #current_content > 0 then
      local prompt_content = vim.trim(table.concat(current_content, "\n"))
      if prompt_content ~= "" then
        local prompt = {
          role = current_role,
          content = prompt_content,
        }
        if current_opts then
          prompt.opts = current_opts
        end
        table.insert(prompts, prompt)
      end
    end
  end

  for capture_id, node in query:iter_captures(root, content, 0, -1) do
    local capture_name = query.captures[capture_id]

    if capture_name == "role" then
      store_prompt()
      current_role = vim.trim(get_node_text(node, content):lower())
      current_content = {}
      current_opts = nil
    elseif capture_name == "content" and current_role and vim.tbl_contains(allowed_roles, current_role) then
      -- For workflows: check if the user has a yaml options block
      if node:type() == "fenced_code_block" then
        local info_string = nil
        local code_fence_content = nil

        for child in node:iter_children() do
          if child:type() == "info_string" then
            info_string = get_node_text(child, content)
          elseif child:type() == "code_fence_content" then
            code_fence_content = get_node_text(child, content)
          end
        end

        if info_string and info_string:match("^yaml%s+options?$") and code_fence_content then
          current_opts = parse_options_block(code_fence_content)
          goto continue
        end
      end

      table.insert(current_content, get_node_text(node, content))
      ::continue::
    end
  end

  store_prompt()

  if #prompts == 0 then
    return nil
  end

  if frontmatter and frontmatter.opts and frontmatter.opts.is_workflow then
    local workflow = {}
    local first_prompt = {}
    local is_first_prompt = true

    for _, prompt in ipairs(prompts) do
      if prompt.role == config.constants.SYSTEM_ROLE then
        -- All system prompts get added to the first group
        table.insert(first_prompt, prompt)
      elseif prompt.role == config.constants.USER_ROLE then
        if is_first_prompt then
          table.insert(first_prompt, prompt)
          is_first_prompt = false
        else
          table.insert(workflow, { prompt })
        end
      end
    end

    if #first_prompt > 0 then
      table.insert(workflow, 1, first_prompt)
    end

    return workflow
  end

  return prompts
end

---Execute functions to resolve placeholders
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
        log:error("[Prompt Library] File `%s` must return a table", file_path)
      else
        log:error("[Prompt Library] Failed to load `%s`", file_path)
      end
    end
    return nil
  end

  local replacements = {}
  for _, placeholder in ipairs(placeholders) do
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
      log:warn("[Prompt Library] Could not resolve `${%s}` in `%s`", placeholder, item.path)
    end
  end

  if vim.tbl_count(replacements) > 0 then
    utils.replace_placeholders(item.prompts, replacements)
  end

  return item
end

return M
