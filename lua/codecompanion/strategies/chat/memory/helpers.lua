local chat_helpers = require("codecompanion.strategies.chat.helpers")
local config = require("codecompanion.config")

local buf_utils = require("codecompanion.utils.buffers")
local file_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")

local M = {}

---Recursively expand memory groups (supports groups of groups)
---@param picker_items string[] Flat output list to mutate
---@param group_path string Display name path (e.g. "parent/child")
---@param group_cfg table Group config to expand
---@param parent_cfg? { parser?: any, opts?: table, description?: string } Inherited values from parent
---@return nil
local function expand_memory_group(picker_items, group_path, group_cfg, parent_cfg)
  local inherited = {
    parser = group_cfg.parser or (parent_cfg and parent_cfg.parser or nil),
    opts = vim.tbl_extend("force", parent_cfg and parent_cfg.opts or {}, group_cfg.opts or {}),
    description = group_cfg.description or (parent_cfg and parent_cfg.description or nil),
  }

  local rules = group_cfg.rules or {}

  -- If this group holds a list of rules, add it as a selectable picker item
  if util.is_array(rules) then
    table.insert(picker_items, {
      name = group_path,
      description = inherited.description,
      opts = inherited.opts or {},
      parser = inherited.parser,
      rules = rules,
    })
    return
  end

  -- Otherwise, recurse into subgroups
  for subgroup_name, subgroup_config in pairs(rules) do
    if type(subgroup_config) == "table" then
      local child_path = group_path .. "/" .. subgroup_name
      expand_memory_group(picker_items, child_path, subgroup_config, inherited)
    end
  end
end

---List all of the memory from the config (flattened)
---@return table
function M.list()
  local picker_items = {}
  local exclusions = { "opts", "parsers" }

  for name, cfg in pairs(config.memory or {}) do
    if cfg.is_default and config.memory.opts.show_defaults == false then
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
      local rules = cfg.rules or {}
      if util.is_array(rules) then
        -- Memory is a singular group
        table.insert(picker_items, {
          name = name,
          description = cfg.description,
          opts = cfg.opts,
          parser = cfg.parser,
          rules = rules,
        })
      else
        -- If the memory contains multiple groups
        expand_memory_group(picker_items, name, cfg, nil)
      end
    end
    ::continue::
  end

  table.sort(picker_items, function(a, b)
    return a.name < b.name
  end)

  return picker_items
end

---Add context to the chat based on the memory rules
---@param rules CodeCompanion.Chat.Memory.ProcessedRule
---@param chat CodeCompanion.Chat
---@return nil
function M.add_context(rules, chat)
  for _, item in ipairs(rules) do
    local id = "<memory>" .. item.name .. "</memory>"
    if not chat_helpers.has_context(id, chat.messages) then
      chat:add_context({ content = item.content }, "memory", id, {
        path = item.path,
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
        return log:debug("[Memory] Could not find the file %s", path)
      end
    end

    -- Then determine if the file is open as a buffer
    local bufnr = buf_utils.get_bufnr_from_filepath(path)
    if bufnr then
      local ok, content, id, _ = pcall(chat_helpers.format_buffer_for_llm, bufnr, path)
      if not ok then
        return log:debug("[Memory] Could not add buffer %d to chat buffer", bufnr)
      end

      local buffer_opts = config.memory.opts.chat and config.memory.opts.chat.default_params
      if buffer_opts then
        if buffer_opts == "pin" then
          opts.pinned = true
        elseif buffer_opts == "watch" then
          opts.watched = true
        end
      end

      return chat:add_context({ content = content }, "memory", id, {
        bufnr = bufnr,
        path = path,
        context_opts = opts,
      })
    end

    -- Otherwise, add it as file context
    local ok, content, id, _, _, _ = pcall(chat_helpers.format_file_for_llm, path, opts)
    if ok then
      chat:add_context({ content = content }, "memory", id, {
        path = path,
      })
    end
  end)
end

return M
