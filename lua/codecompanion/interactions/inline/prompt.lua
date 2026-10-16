local config = require("codecompanion.config")

local fmt = string.format

local SYSTEM_PROMPT =
  [[You are a knowledgeable developer working in the Neovim text editor. You edit %s code on behalf of a user, directly in their active Neovim buffer.

- Follow the user's prompt, enclosed in <prompt></prompt> tags
- %s
- Only edit the code you have been told you can edit
- Preserve the exact indentation (tabs/spaces) of the surrounding code
- A request phrased as a question ("Can we...", "Could you...") is still a change to make
- Only reply, in %s and without editing, when the user wants an explanation rather than a change]]

local M = {}

---The system prompt, with the one rule that differs between HTTP and ACP adapters
---@param opts { filetype: string, edit_rule: string }
---@return string
function M.build(opts)
  return fmt(SYSTEM_PROMPT, opts.filetype, opts.edit_rule, config.opts.language)
end

return M
