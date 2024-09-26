local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local action_state = require("telescope.actions.state")
local telescope_actions = require("telescope.actions")

local config = require("codecompanion").config

local log = require("codecompanion.utils.log")

---@class CodeCompanion.Actions.Providers.Telescope
---@field validate table Validate an item
---@field resolve table Resolve an item into an action
---@field context table Store all arguments in this table
local Provider = {}

---@class CodeCompanion.Actions.Providers.Telescope.Args Arguments that can be injected into the chat
---@field validate table Validate an item
---@field resolve table Resolve an item into an action
---@field context table The buffer context
function Provider.new(args)
  local ok = pcall(require, "telescope")
  if not ok then
    return log:error("Telescope is not installed")
  end

  log:trace("Telescope actions provider triggered")
  return setmetatable(args, { __index = Provider })
end

---The Telescope picker
---@param items table The items to display in the picker
---@param opts? table The options for the picker
---@return nil
function Provider:picker(items, opts)
  opts = opts or {}

  return pickers
    .new(opts, {
      prompt_title = opts.prompt or "CodeCompanion actions",
      finder = finders.new_table({
        results = items,
        entry_maker = function(entry)
          local description = entry.description and " - " .. entry.description or ""
          return {
            value = entry,
            display = entry.name .. description,
            ordinal = entry.name,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(bufnr, _)
        telescope_actions.select_default:replace(function()
          local selected = action_state.get_selected_entry()
          if not selected or vim.tbl_isempty(selected) then
            return
          end
          telescope_actions.close(bufnr)

          self:select(selected.value)
        end)
        return true
      end,
    })
    :find()
end

---The action to take when an item is selected
---@param item table The selected item
---@return nil
function Provider:select(item)
  return require("codecompanion.actions.providers.shared").select(self, item)
end

return Provider
