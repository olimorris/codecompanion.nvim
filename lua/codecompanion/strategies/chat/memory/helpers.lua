local chat_helpers = require("codecompanion.strategies.chat.helpers")
local config = require("codecompanion.config")
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
      chat:add_context({
        content = item.content,
      }, item.name, id, { tag = "memory" })
    end
  end
end

return M
