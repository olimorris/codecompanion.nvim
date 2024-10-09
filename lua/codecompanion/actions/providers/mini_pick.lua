local MiniPick = require("mini.pick")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Actions.Providers.MiniPick
---@field validate table Validate an item
---@field resolve table Resolve an item into an action
---@field context table Store all arguments in this table
local Provider = {}

---@class CodeCompanion.Actions.Providers.MiniPick.Args Arguments that can be injected into the chat
---@field validate table Validate an item
---@field resolve table Resolve an item into an action
---@field context table The buffer context
function Provider.new(args)
  log:trace("MiniPick actions provider triggered")
  return setmetatable(args, { __index = Provider })
end

---The MiniPick picker
---@param items table The items to display in the picker
---@param opts? table The options for the picker
---@return nil
function Provider:picker(items, opts)
  opts = opts or {}

  local source = {
    items = items,
    name = opts.prompt or "CodeCompanion actions",
    choose = function(chosen_item)
      self:select(chosen_item)
    end,
    show = function(buf_id, items_to_show, query)
      local formatted_items = {}
      for _, item in ipairs(items_to_show) do
        local description = item.description and " - " .. item.description or ""
        table.insert(formatted_items, { text = string.format("%s%s", item.name, description) })
      end
      MiniPick.default_show(buf_id, formatted_items, query)
    end,
  }

  local pick_opts = {
    window = {
      config = function()
        local height = math.floor(0.618 * vim.o.lines)
        local width = math.floor(0.618 * vim.o.columns)
        return {
          border = "rounded",
          anchor = "NW",
          height = height,
          width = width,
          row = math.floor(0.5 * (vim.o.lines - height)),
          col = math.floor(0.5 * (vim.o.columns - width)),
        }
      end,
    },
  }

  MiniPick.start({
    source = source,
    options = pick_opts,
  })
end

---The action to take when an item is selected
---@param item table The selected item
---@return nil
function Provider:select(item)
  return require("codecompanion.actions.providers.shared").select(self, item)
end

return Provider
