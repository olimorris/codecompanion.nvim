local config = require("codecompanion").config

local Strategy = require("codecompanion.strategies")
local context_utils = require("codecompanion.utils.context")
local api = vim.api

---@param desc table
---@return string|function|nil
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
---@return nil
local function map(config, mode)
  return api.nvim_set_keymap(mode, config.opts.mapping, "", {
    callback = function()
      local context = context_utils.get(api.nvim_get_current_buf())

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

---@return CodeCompanion.Prompts
function Prompts:setup()
  --Loop through the prompts
  for _, prompt in pairs(self.prompts) do
    if prompt.opts and prompt.opts.mapping then
      if not config.opts.use_default_prompt_library and prompt.opts.is_default then
        goto continue
      end
      if prompt.opts.modes and type(prompt.opts.modes) == "table" then
        for _, mode in ipairs(prompt.opts.modes) do
          map(prompt, mode)
        end
      else
        map(prompt, "n")
      end
    end
    ::continue::
  end

  return self
end

return Prompts
