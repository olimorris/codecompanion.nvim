local Strategy = require("codecompanion.strategies")
local util = require("codecompanion.utils.util")
local api = vim.api

local function resolve_description(desc)
  if type(desc) == "string" then
    return desc
  end
  if type(desc) == "function" then
    return desc()
  end
end

---@param config table
---@param mode string
local function map(config, mode)
  return api.nvim_set_keymap(mode, config.opts.mapping, "", {
    callback = function()
      local context = util.get_context(api.nvim_get_current_buf())

      return Strategy.new({
        context = context,
        selected = config,
      }):start(config.strategy)
    end,
    desc = resolve_description(config.description),
    noremap = true,
    silent = true,
  })
end

---@class CodeCompanion.Prompts
---@field prompts table
local Prompts = {}

---@class CodeCompanion.PromptsArgs
---@field prompts table
function Prompts.new(prompts)
  local self = setmetatable({
    prompts = prompts,
  }, { __index = Prompts })

  return self
end

function Prompts:setup()
  --Loop through the prompts
  for name, config in pairs(self.prompts) do
    if config.opts and config.opts.mapping then
      if config.opts.modes and type(config.opts.modes) == "table" then
        for _, mode in ipairs(config.opts.modes) do
          map(config, mode)
        end
      else
        map(config, "n")
      end
    end
  end

  return self
end

return Prompts
