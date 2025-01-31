local log = require("codecompanion.utils.log")

---@class CodeCompanion.SlashCommand.Provider.MiniPick: CodeCompanion.SlashCommand.Provider
local MiniPick = {}

---@param args CodeCompanion.SlashCommand.ProviderArgs
function MiniPick.new(args)
  local ok, mini_pick = pcall(require, "mini.pick")
  if not ok then
    return log:error("mini.pick is not installed")
  end

  return setmetatable({
    output = args.output,
    provider = mini_pick,
    title = args.title,
  }, { __index = MiniPick })
end

---The function to display the provider
---@param transformer? function
---@return table
function MiniPick:display(transformer)
  transformer = transformer or function(selection)
    return { path = selection.path }
  end
  return {
    source = {
      name = self.title or "CodeCompanion",
      choose = function(selected)
        local success, _ = pcall(function()
          return self.output(transformer(selected))
        end)
        if success then
          return nil
        end
      end,
      choose_marked = function(selection)
        for _, selected in ipairs(selection) do
          local success, _ = pcall(function()
            return self.output(transformer(selected))
          end)
          if not success then
            break
          end
        end
      end,
    },
  }
end

return MiniPick
