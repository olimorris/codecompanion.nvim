--[[
Inputs to the Inline Assistant are handled here
--]]

local config = require("codecompanion.config")

---@class CodeCompanion.InlineInput
---@field adapter CodeCompanion.Adapter
---@field inline CodeCompanion.Inline
---@field user_prompt? string The user's prompt
local Input = {}

---@param inline CodeCompanion.Inline
---@param args string|table The arguments passed to the inline assistant
function Input.new(inline, args)
  if not args then
    return
  end

  local self = setmetatable({
    adapter = nil,
    inline = inline,
    user_prompt = args.user_prompt,
  }, { __index = Input })

  if self.user_prompt then
    local split = vim.split(self.user_prompt, " ")

    -- The first word in the user prompt must be an adapter
    local adapter = config.adapters[split[1]]
    if adapter then
      self.inline:set_adapter(adapter)
      table.remove(split, 1)
    end

    -- Variables can occur anywhere in the user prompt

    -- Finally, piece it together again
    self.user_prompt = table.concat(split, " ")
  end

  return self
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
