local MiniPick = require("mini.pick")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Actions.Provider.MiniPick: CodeCompanion.SlashCommand.Provider
---@field context table
---@field resolve function
local Provider = {}

---@params CodeCompanion.Actions.ProvidersArgs
function Provider.new(args)
  log:trace("MiniPick actions provider triggered")
  -- Ensure we have the resolve function
  if not args.resolve then
    args.resolve = require("codecompanion.actions").resolve
  end

  return setmetatable(args, { __index = Provider })
end

---The MiniPick picker
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

  local source = {
    items = picker_items,
    name = opts.prompt or "CodeCompanion actions",
    choose = function(chosen_item)
      if chosen_item and chosen_item.item then
        -- Get the target window before closing the picker
        local win_target = MiniPick.get_picker_state().windows.target
        if not vim.api.nvim_win_is_valid(win_target) then
          win_target = vim.api.nvim_get_current_win()
        end

        -- Switch to target window and perform selection
        vim.api.nvim_win_call(win_target, function()
          if provider.resolve then
            -- Try direct resolution if select fails
            provider.resolve(chosen_item.item, provider.context)
          else
            provider:select(chosen_item.item)
          end
          MiniPick.set_picker_target_window(vim.api.nvim_get_current_win())
        end)
        return false -- Close picker after selection
      end
    end,
    show = function(buf_id, items_to_show, query)
      MiniPick.default_show(buf_id, items_to_show, query)
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
  -- Handle picker actions (like "Open chats ...")
  if item.picker then
    local picker_items = {}
    local items = item.picker.items()

    for _, picker_item in ipairs(items) do
      local description = picker_item.description and " - " .. picker_item.description or ""
      table.insert(picker_items, {
        text = string.format("%s%s", picker_item.name, description),
        item = picker_item,
      })
    end

    local source = {
      items = picker_items,
      name = item.picker.prompt or item.name,
      choose = function(chosen_item)
        if chosen_item and chosen_item.item and chosen_item.item.callback then
          chosen_item.item.callback()
        end
        return false -- Close picker
      end,
      show = function(buf_id, items_to_show, query)
        MiniPick.default_show(buf_id, items_to_show, query)
      end,
    }

    MiniPick.start({ source = source })
    return
  end

  -- Handle normal actions through existing logic
  if self.resolve then
    return self.resolve(item, self.context)
  end
  return require("codecompanion.providers.actions.shared").select(self, item)
end

return Provider
