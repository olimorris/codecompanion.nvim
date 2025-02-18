local log = require("codecompanion.utils.log")

---@class CodeCompanion.SlashCommand.Provider.Telescope: CodeCompanion.SlashCommand.Provider
local Telescope = {}

---@param args CodeCompanion.SlashCommand.ProviderArgs
function Telescope.new(args)
  local ok, telescope = pcall(require, "telescope.builtin")
  if not ok then
    return log:error("Telescope is not installed")
  end

  return setmetatable({
    output = args.output,
    provider = telescope,
    title = args.title,
  }, { __index = Telescope })
end

---The function to display the provider
---@return function
function Telescope:display()
  return function(_, map)
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    actions.select_default:replace(function(bufnr, _)
      local picker = action_state.get_current_picker(bufnr)
      local selections = picker:get_multi_selection()

      if vim.tbl_isempty(selections) then
        selections = { action_state.get_selected_entry() }
      end

      actions.close(bufnr)
      vim.iter(selections):each(function(selection)
        if selection then
          self.output(selection)
        end
      end)
    end)
    map({'i', 'n'}, '<CR>', actions.select_default)
    return true
  end
end

return Telescope
