local chat_helpers = require("codecompanion.strategies.chat.helpers")
local config = require("codecompanion.config")

local buf_utils = require("codecompanion.utils.buffers")
local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local M = {}

---Recursively expand rules groups (supports groups of groups)
---@param picker_items string[] Flat output list to mutate
---@param group_path string Display name path (e.g. "parent/child")
---@param group_cfg table Group config to expand
---@param parent_cfg? { parser?: any, opts?: table, description?: string } Inherited values from parent
---@return nil
local function expand_rules_group(picker_items, group_path, group_cfg, parent_cfg)
  local inherited = {
    parser = group_cfg.parser or (parent_cfg and parent_cfg.parser or nil),
    opts = vim.tbl_extend("force", parent_cfg and parent_cfg.opts or {}, group_cfg.opts or {}),
    description = group_cfg.description or (parent_cfg and parent_cfg.description or nil),
  }

  local files = group_cfg.files or {}

  -- If this group holds a list of files, add it as a selectable picker item
  if utils.is_array(files) then
    table.insert(picker_items, {
      name = group_path,
      description = inherited.description,
      opts = inherited.opts or {},
      parser = inherited.parser,
      files = files,
    })
    return
  end

  -- Otherwise, recurse into subgroups
  for subgroup_name, subgroup_config in pairs(files) do
    if type(subgroup_config) == "table" then
      local child_path = group_path .. "/" .. subgroup_name
      expand_rules_group(picker_items, child_path, subgroup_config, inherited)
    end
  end
end

---List all of the rules from the config (flattened)
---@return table
function M.list()
  local picker_items = {}
  local exclusions = { "opts", "parsers" }

  for name, cfg in pairs(config.rules or {}) do
    if cfg.is_default and config.rules.opts.show_defaults == false then
      goto continue
    end
    if cfg.enabled == false then
      goto continue
    end
    if cfg.enabled and type(cfg.enabled) == "function" then
      if not cfg.enabled() then
        goto continue
      end
    end
    if not vim.tbl_contains(exclusions, name) and type(cfg) == "table" then
      local files = cfg.files or {}
      if utils.is_array(files) then
        -- Rules is a singular group
        table.insert(picker_items, {
          name = name,
          description = cfg.description,
          opts = cfg.opts,
          parser = cfg.parser,
          files = files,
        })
      else
        -- If the rules contains multiple groups
        expand_rules_group(picker_items, name, cfg, nil)
      end
    end
    ::continue::
  end

  table.sort(picker_items, function(a, b)
    return a.name < b.name
  end)

  return picker_items
end

---Add callbacks to a chat creation request
---@param args table
---@param rules_name? string The name of the rules instance to use (if any)
---@return table|nil
function M.add_callbacks(args, rules_name)
  local rules = config.rules and config.rules.opts and config.rules.opts.chat
  if not rules_name and not (rules and rules.enabled and rules.default_rules) then
    return args.callbacks
  end

  local defaults = rules_name or rules.default_rules
  local memories = {}
  if type(defaults) == "string" then
    memories = { defaults }
  elseif type(defaults) == "table" then
    memories = vim.deepcopy(defaults)
  else
    return args.callbacks
  end

  for _, name in ipairs(memories) do
    local current = config.rules[name]
    if current then
      -- Ensure that we extend any existing callbacks
      args.callbacks = utils.callbacks_extend(args.callbacks, "on_created", function(chat)
        require("codecompanion.strategies.chat.rules").add_to_chat({
          name = name,
          opts = current.opts,
          parser = current.parser,
          files = current.files,
        }, chat)
      end)
    else
      log:warn("Could not find `%s` rules", name)
    end
  end

  return args.callbacks
end

---Add context to the chat based on the rules files
---@param files CodeCompanion.Chat.Rules.ProcessedFile
---@param chat CodeCompanion.Chat
---@return nil
function M.add_context(files, chat)
  for _, file in ipairs(files) do
    local id = "<rules>" .. file.name .. "</rules>"
    local context_exists = chat_helpers.has_context(id, chat.messages)
    if not context_exists then
      if file.system_prompt and file.system_prompt ~= "" then
        chat:add_message(
          { role = "system", content = file.system_prompt },
          { visible = false, context = { id = id }, _meta = { tag = "rules" } }
        )
      end
      chat:add_context({ content = file.content }, "rules", id, {
        path = file.path,
      })
    end
  end
end

---Add a file or buffer as context to the chat
---@param included_files string[]
---@param chat CodeCompanion.Chat
---@return nil
function M.add_files_or_buffers(included_files, chat)
  vim.iter(included_files):each(function(f)
    local opts = {}

    local path = vim.fs.normalize(f)

    -- Check if the file exists in the current working directory
    if file_utils.exists(vim.fs.joinpath(vim.fn.getcwd(), path)) then
      path = vim.fs.joinpath(vim.fn.getcwd(), path)
    else
      -- Otherwise, check the wider filesystem
      if not file_utils.exists(path) then
        return log:warn("Could not find the rules file `%s`", path)
      end
    end

    -- Then determine if the file is open as a buffer
    local bufnr = buf_utils.get_bufnr_from_path(path)
    if bufnr then
      local ok, content, id, _ = pcall(chat_helpers.format_buffer_for_llm, bufnr, path)
      if not ok then
        return log:debug("[Rules] Could not add buffer %d to chat buffer", bufnr)
      end

      local context_exists = chat_helpers.has_context(id, chat.messages)
      if context_exists then
        return
      end

      local buffer_opts = config.rules.opts.chat and config.rules.opts.chat.default_params
      if buffer_opts then
        if buffer_opts == "all" then
          opts.sync_all = true
        elseif buffer_opts == "diff" then
          opts.sync_diff = true
        end
      end

      return chat:add_context({ content = content }, "rules", id, {
        bufnr = bufnr,
        path = path,
        context_opts = opts,
      })
    end

    -- Otherwise, add it as file context
    local ok, content, id, _, _, _ = pcall(chat_helpers.format_file_for_llm, path, opts)
    if ok then
      local context_exists = chat_helpers.has_context(id, chat.messages)
      if not context_exists then
        chat:add_context({ content = content }, "rules", id, {
          path = path,
        })
      end
    end
  end)
end

return M
