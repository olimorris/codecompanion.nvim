--[[
Inputs to the Inline Assistant are handled here
--]]
---@class CodeCompanion.InlineInput
local Input = {}

function Input.new(args) end

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
