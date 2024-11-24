local log = require("codecompanion.utils.log")

---@class CodeCompanion.SlashCommand.Provider.FZF: CodeCompanion.SlashCommand.Provider
local FZF = {}

---@param args CodeCompanion.SlashCommand.ProviderArgs
function FZF.new(args)
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    return log:error("fzf-lua is not installed")
  end

  return setmetatable({
    output = args.output,
    provider = fzf,
    title = args.title,
  }, { __index = FZF })
end

---The function to display the provider
---@param transformer function
---@return table
function FZF:display(transformer)
  return {
    prompt = self.title,
    actions = {
      ["default"] = function(selected, opts)
        if selected or vim.tbl_count(selected) ~= 0 then
          for _, selection in ipairs(selected) do
            self.output(transformer(selection, opts))
          end
        end
      end,
    },
  }
end

return FZF
