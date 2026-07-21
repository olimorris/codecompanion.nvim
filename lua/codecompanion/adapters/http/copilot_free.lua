local copilot = require("codecompanion.adapters.http.copilot")
local token = require("codecompanion.adapters.http.copilot.token")

---GitHub Copilot's free plan does not allow the model to be chosen; GitHub
---selects it automatically. All other request/response handling is shared
---with the `copilot` adapter, which is model-agnostic once `schema.model.choices`
---is absent.
---@class CodeCompanion.HTTPAdapter.CopilotFree: CodeCompanion.HTTPAdapter
return {
  name = "copilot_free",
  formatted_name = "Copilot (Free)",
  roles = copilot.roles,
  opts = {
    documents = false, -- Vendor of the auto-selected model is unknown, so avoid the /chat/completions PDF translation error
    stream = true,
    tools = true,
    vision = true,
  },
  features = copilot.features,
  url = copilot.url,
  env = copilot.env,
  headers = copilot.headers,
  show_copilot_stats = copilot.show_copilot_stats,
  handlers = {
    ---Check for a token before starting the request
    ---@param self CodeCompanion.HTTPAdapter
    ---@return boolean
    setup = function(self)
      return token.init(self)
    end,

    ---@param self CodeCompanion.HTTPAdapter
    ---@param params table
    ---@param messages table
    ---@return table
    form_parameters = function(self, params, messages)
      local result = copilot.handlers.form_parameters(self, params, messages)
      -- Copilot Free/Student automatically picks the model
      if result then
        result.model = nil
      end
      return result
    end,
    form_messages = copilot.handlers.form_messages,
    form_tools = copilot.handlers.form_tools,
    form_structured_output = copilot.handlers.form_structured_output,
    form_reasoning = copilot.handlers.form_reasoning,
    parse_message_meta = copilot.handlers.parse_message_meta,
    tokens = copilot.handlers.tokens,
    chat_output = copilot.handlers.chat_output,
    tools = copilot.handlers.tools,
    inline_output = copilot.handlers.inline_output,
    on_exit = copilot.handlers.on_exit,
  },
  schema = {
    ---@type CodeCompanion.Schema
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "GitHub automatically selects the model on the Copilot Free plan; no `model` is sent in the request.",
      default = "auto",
    },
  },
}
