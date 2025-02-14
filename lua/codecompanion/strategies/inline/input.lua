--[[
Inputs to the Inline Assistant are handled here
--]]

local config = require("codecompanion.config")

---@class CodeCompanion.InlineInput
---@field adapter CodeCompanion.Adapter
---@field context table
---@field inline CodeCompanion.Inline
---@field prompt string[]
local Input = {}

---@param inline CodeCompanion.Inline
---@param args string|table The arguments passed to the inline assistant
---@return string|nil
function Input.new(inline, args)
  if not args then
    return
  end

  local self = setmetatable({
    adapter = nil,
    context = {},
    inline = inline,
    prompt = args.fargs or {},
  }, { __index = Input })

  if not vim.tbl_isempty(self.prompt) then
    -- The first word in the user prompt must be an adapter or a prompt library item
    local adapter = config.adapters[self.prompt[1]]
    if adapter then
      self.inline:set_adapter(adapter)
      table.remove(self.prompt, 1) -- Remove the adapter name from the prompt
    end

    -- Move on to the next first word and see if it contains a prompt library item
  end

  -- Now scan the whole prompt for any variables

  return vim.trim(table.concat(self.prompt, " "))
end

-- If the user has supplied a slash command then we need to process it
-- if string.sub(opts.args, 1, 1) == "/" then
--   local user_prompt = nil
--   -- Remove the leading slash
--   local prompt = string.sub(opts.args, 2)
--
--   local user_prompt_pos = string.find(prompt, " ")
--
--   if user_prompt_pos then
--     -- Extract the user_prompt first
--     user_prompt = string.sub(prompt, user_prompt_pos + 1)
--     prompt = string.sub(prompt, 1, user_prompt_pos - 1)
--
--     log:trace("Prompt library call: %s", prompt)
--     log:trace("User prompt: %s", user_prompt)
--   end
--
--   local prompts = vim
--     .iter(config.prompt_library)
--     :filter(function(_, v)
--       return v.opts and v.opts.short_name and v.opts.short_name:lower() == prompt:lower()
--     end)
--     :map(function(k, v)
--       v.name = k
--       return v
--     end)
--     :nth(1)
--
--   if prompts then
--     if user_prompt then
--       opts.user_prompt = user_prompt
--     end
--     return codecompanion.run_inline_prompt(prompts, opts)
--   end
-- end
return Input
