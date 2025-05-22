local builtin = require("fzf-lua.previewer.builtin")
local fzf = require("fzf-lua")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.Actions.Provider.FZF: CodeCompanion.SlashCommand.Provider
---@field context table
---@field resolve function
local FZF = {}

---@param args CodeCompanion.SlashCommand.ProviderArgs
function FZF.new(args)
  return setmetatable(args, { __index = FZF })
end

---@param items table The items to display in the picker
---@param opts? table The options for the picker
---@return nil
function FZF:picker(items, opts)
  opts = opts or {}
  opts.prompt = opts.prompt or "CodeCompanion actions"

  local item_names = {}
  local name_to_item = {}

  for _, item in ipairs(items) do
    table.insert(item_names, item.name)
    name_to_item[item.name] = item
  end

  fzf.fzf_exec(item_names, {
    prompt = opts.prompt,
    preview = {
      fn = function(it)
        return name_to_item[it[1]].description
      end,
    },
    actions = {
      ["default"] = function(selected)
        if selected or vim.tbl_count(selected) ~= 0 then
          for _, selection in ipairs(selected) do
            return require("codecompanion.providers.actions.shared").select(self, name_to_item[selection])
          end
        end
      end,
    },
  })
end

return FZF
