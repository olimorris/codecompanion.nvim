local Snacks = require("snacks")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Actions.Provider.Snacks: CodeCompanion.SlashCommand.Provider
---@field context table
---@field resolve function
local Provider = {}

---@params CodeCompanion.Actions.ProvidersArgs
function Provider.new(args)
  log:trace("Snacks actions provider triggered")
  -- Ensure we have the resolve function
  if not args.resolve then
    args.resolve = require("codecompanion.actions").resolve
  end

  return setmetatable(args, { __index = Provider })
end

---@param items table The items to display in the picker
---@param opts? table The options for the picker
---@return nil
function Provider:picker(items, opts)
  opts = opts or {}

  -- Store provider reference
  local provider = self

  -- Transform items to include both display text and original data
  local picker_items = {}
  for _, item in ipairs(items) do
    local description = item.description and " - " .. item.description or ""
    table.insert(picker_items, {
      text = string.format("%s%s", item.name, description),
      item = item,
    })
  end
  -- Create Snacks picker
  Snacks.picker({
    items = picker_items,
    title = opts.prompt or "CodeCompanion actions",
    -- Use the default layout for the picker
    layout = { preset = "select" },
    -- Define what happens when an item is confirmed
    confirm = function(picker, item)
      if item and item.item then
        -- Close the picker
        picker:close()
        -- Process the selection using the provider's resolve method or select method
        if provider.resolve then
          provider.resolve(item.item, provider.context)
        else
          provider:select(item.item)
        end
      end
    end,
    -- Format each item for display
    format = function(item)
      return { { item.text } }
    end,
  })
end

---The action to take when an item is selected
---@param item table The selected item
---@return nil
function Provider:select(item)
  if self.resolve then
    return self.resolve(item, self.context)
  end
  return require("codecompanion.providers.actions.shared").select(self, item)
end

return Provider
