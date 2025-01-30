---@class CodeCompanion.PromptConfig
---@field strategy string The strategy to use (chat/inline/workflow)
---@field description string Description of what the prompt does
---@field opts? CodeCompanion.PromptOpts Configuration options
---@field prompts CodeCompanion.Prompt|CodeCompanion.Prompt[] Single prompt or array of prompts
---@field references? CodeCompanion.Reference[] Optional array of references
---@field condition? function Optional condition function
---@field picker? table Optional picker configuration

---@class CodeCompanion.PromptOpts
---@field index? integer The index for sorting prompts
---@field is_default? boolean Whether this is a default prompt
---@field is_slash_cmd? boolean Whether this is a slash command
---@field modes? string[] Valid modes for the prompt
---@field short_name? string Short name identifier
---@field auto_submit? boolean Whether to auto-submit the prompt
---@field user_prompt? boolean Whether this requires user input
---@field stop_context_insertion? boolean Whether to stop context insertion
---@field contains_code? boolean Whether the prompt contains code
---@field visible? boolean Whether the prompt is visible
---@field tag? string Custom tag for the prompt

---@class CodeCompanion.Reference
---@field type string The type of reference (file/symbols/url)
---@field path? string|string[] Path to the file or files
---@field url? string URL for web references

---@class CodeCompanion.Prompt
---@field role string The role of the prompt (system/user/assistant)
---@field content string|function Content or function returning content
---@field opts? CodeCompanion.PromptOpts Additional options for the prompt
---@field condition? function Function determining if prompt should be shown

local M = {}


---Resolve the prompts in the prompt library with a view to displaying them in
---the action palette.
---@param config table
---@param context table
---@return table
function M.resolve(context, config)
  local _prompts = {}
  local sort_index = true

  --TODO: Replace with vim.iter()
  for name, prompt in pairs(config.prompt_library) do
    if
      not config.display.action_palette.opts.show_default_prompt_library and (prompt.opts and prompt.opts.is_default)
    then
      goto continue
    end

    if not prompt.opts or not prompt.opts.index then
      sort_index = false
    end

    --TODO: Can we refactor this to name?!
    if type(prompt.name_f) == "function" then
      name = prompt.name_f(context)
    end

    local description = prompt.description
    if type(prompt.description) == "function" then
      description = prompt.description(context)
    end
    if prompt.opts and prompt.opts.slash_cmd then
      description = description
    end

    table.insert(_prompts, {
      condition = prompt.condition,
      description = description,
      name = name,
      opts = prompt.opts,
      references = prompt.references,
      picker = prompt.picker,
      prompts = prompt.prompts,
      strategy = prompt.strategy,
    })

    ::continue::
  end

  if sort_index then
    table.sort(_prompts, function(a, b)
      return a.opts.index < b.opts.index
    end)
  end

  return _prompts
end

return M
