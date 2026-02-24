---@class CodeCompanion.Inline.EditorContext
---@field config table
---@field inline CodeCompanion.Inline
---@field editor_context_items table
---@field prompt string The user prompt to check for editor context

---@class CodeCompanion.Inline.EditorContextItems
---@field context table

---@class CodeCompanion.Inline.EditorContextArgs
---@field context table

local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local regex = require("codecompanion.utils.regex")
local triggers = require("codecompanion.triggers")

local CONSTANTS = {
  PREFIX = triggers.mappings.editor_context,
}

---@class CodeCompanion.Inline.EditorContext
local EditorContext = {}

function EditorContext.new(args)
  local self = setmetatable({
    config = config.interactions.inline.editor_context,
    inline = args.inline,
    prompt = args.prompt,
    editor_context_items = {},
  }, { __index = EditorContext })

  return self
end

---Creates a regex pattern to match editor context in a message
---@param item string The editor_context name to create a pattern for
---@param include_params? boolean Whether to include parameters in the pattern
---@return string The compiled regex pattern
function EditorContext:_pattern(item, include_params)
  local escaped_ec = vim.pesc(item)
  return CONSTANTS.PREFIX .. "{" .. escaped_ec .. "}" .. (include_params and "{[^}]*}" or "")
end

---Check a prompt for editor context
---@return CodeCompanion.Inline.EditorContext
function EditorContext:find()
  for item, _ in pairs(self.config) do
    if regex.find(self.prompt, self:_pattern(item)) then
      table.insert(self.editor_context_items, item)
    end
  end

  return self
end

---Replace editor context in the prompt
---@return CodeCompanion.Inline.EditorContext
function EditorContext:replace()
  for item, _ in pairs(self.config) do
    self.prompt = vim.trim(regex.replace(self.prompt, self:_pattern(item), ""))
  end
  return self
end

---Add the editor context to the inline class as prompts
---@return table
function EditorContext:output()
  local outputs = {}

  -- Loop through the found editor context items
  for _, item in ipairs(self.editor_context_items) do
    if not self.config[item] then
      return log:error("[EditorContext] `%s` is not defined in the config", item)
    end

    local ec_output
    local ec_config = self.config[item]

    if type(ec_config.callback) == "function" then
      local ok, output = pcall(ec_config.callback, self)
      if not ok then
        log:error("[EditorContext] %s could not be resolved: %s", item, output)
      else
        if output then
          table.insert(outputs, output)
        end
      end
      goto skip
    end

    -- Resolve them and add them to the outputs
    local path = ec_config.path
    local ok, module = pcall(require, "codecompanion." .. path)
    if ok then
      ec_output = module --[[@type CodeCompanion.Inline.EditorContext]]
      goto append
    end

    do
      local err
      module, err = loadfile(vim.fs.normalize(path))
      if err then
        log:error("[EditorContext] %s could not be resolved", item)
        goto skip
      end
      if module then
        ec_output = module() --[[@type CodeCompanion.Inline.EditorContext]]
      end
    end

    if (ec_config.opts and ec_config.opts.contains_code) and not config.can_send_code() then
      log:warn("Sending of code has been disabled")
      goto skip
    end

    ::append::

    local output = ec_output.new({ context = self.inline.buffer_context }):output()
    if output then
      table.insert(outputs, output)
    end

    ::skip::
  end

  return outputs
end

return EditorContext
