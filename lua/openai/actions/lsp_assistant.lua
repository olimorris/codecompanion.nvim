local log = require("openai.utils.log")
local lsp = require("openai.utils.lsp")
local schema = require("openai.schema")

---@class openai.LSPAssistant
---@field context table
---@field client openai.Client
local LSPAssistant = {}

---@param opts openai.ChatEditArgs
---@return openai.LSPAssistant
function LSPAssistant.new(opts)
  log:debug("Initiating LSPAssistant")

  local self = setmetatable({
    context = opts.context,
    client = opts.client,
  }, { __index = LSPAssistant })
  return self
end

---@param on_complete nil|fun()
function LSPAssistant:start(on_complete)
  if not self.context.is_visual then
    vim.notify(
      "[OpenAI.nvim]\nERROR: You must select some code to send to OpenAI",
      vim.log.levels.ERROR
    )
    return
  end

  local config = schema.static.lsp_assistant_settings

  local diagnostics = lsp.get_diagnostics(self.context.start_line, self.context.end_line)
  log:trace("Diagnostics: %s", diagnostics)

  if next(diagnostics) == nil then
    vim.notify("[OpenAI.nvim]\nWARNING: No diagnostics found", vim.log.levels.WARN)
    return
  end

  local formatted_diagnostics = ""
  for i, diagnostic in ipairs(diagnostics) do
    formatted_diagnostics = formatted_diagnostics
      .. i
      .. ". Issue "
      .. i
      .. "\n\t- Location: Line "
      .. diagnostic.line_number
      .. "\n\t- Severity: "
      .. diagnostic.severity
      .. "\n\t- Message: "
      .. diagnostic.message
      .. "\n"
  end

  local code = lsp.get_code(self.context.start_line, self.context.end_line)
  log:trace("Code: %s", code)

  local settings = {
    model = config.model.default,
    messages = {
      {
        role = "system",
        content = config.prompts.choices[config.prompts.default],
      },
      {
        role = "user",
        content = "The programming language is "
          .. self.context.filetype
          .. ".\nThis is a list of the diagnostic messages:\n"
          .. formatted_diagnostics,
      },
      {
        role = "user",
        content = "This is the code, for context:\n" .. code,
      },
    },
  }

  self.client:assistant(settings, function(err, data)
    if err then
      log:error("Assistant Error: %s", err)
    end

    local output = data.choices[1].message.content

    if on_complete then
      on_complete(output)
    end
  end)
end

return LSPAssistant
