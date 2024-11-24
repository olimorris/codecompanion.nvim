local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")

---@class CodeCompanion.Actions.Provider.Default: CodeCompanion.SlashCommand.Provider
local Provider = {}

---@params CodeCompanion.Actions.ProvidersArgs
function Provider.new(args)
  log:trace("Default actions provider triggered")

  return setmetatable(args, { __index = Provider })
end

---The default picker
---@param items table The items to display in the picker
---@param opts? table The options for the picker
---@return nil
function Provider:picker(items, opts)
  opts = opts or {}
  opts.prompt = opts.prompt or "CodeCompanion actions"
  opts.columns = opts.columns or { "name", "strategy", "description" }

  ui.action_palette_selector(items, {
    prompt = opts.prompt,
    width = config.display.action_palette.width,
    height = config.display.action_palette.height,
    format = function(item)
      local formatted_item = {}
      for _, column in ipairs(opts.columns) do
        if item[column] ~= nil then
          if type(item[column]) == "function" then
            table.insert(formatted_item, item[column](self.context))
          else
            table.insert(formatted_item, item[column] or "")
          end
        end
      end
      return formatted_item
    end,
    callback = function(item)
      return self:select(item)
    end,
  })
end

---The action to take when an item is selected
---@param item table The selected item
---@return nil
function Provider:select(item)
  return require("codecompanion.providers.actions.shared").select(self, item)
end

return Provider
