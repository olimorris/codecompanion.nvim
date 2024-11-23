local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local action_state = require("telescope.actions.state")
local telescope_actions = require("telescope.actions")

local log = require("codecompanion.utils.log")

---@class CodeCompanion.Actions.Provider.Telescop: CodeCompanion.SlashCommand.Provider
local Provider = {}

---@params CodeCompanion.Actions.ProvidersArgs
function Provider.new(args)
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
  return require("codecompanion.providers.actions.shared").select(self, item)
end

return Provider
