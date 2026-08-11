local fetch_models = require("codecompanion.adapters.utils.models.fetch")
local openai = require("codecompanion.adapters.http.openai")

local models_source = {
  name = "OpenRouter",
  url = "https://openrouter.ai/api/v1/models",
}

---@param self CodeCompanion.HTTPAdapter
---@return table|nil
local function model_choices(self)
  local cached_models = fetch_models.get(models_source, self)
  local model = cached_models[self.schema.model.default]
  return model and model.opts or nil
end

---@param self CodeCompanion.HTTPAdapter
---@param parameter string
---@return boolean
local function model_supports(self, parameter)
  local cached_models = fetch_models.get(models_source, self)
  local model = cached_models[self.schema.model.default]
  if not model then
    return false
  end

  return model.opts.supported_parameters[parameter] or false
end

---@class CodeCompanion.HTTPAdapter.OpenRouter: CodeCompanion.HTTPAdapter
return {
  name = "openrouter",
  formatted_name = "OpenRouter",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    documents = true,
    stream = true,
    tools = true,
    vision = true,
  },
  available_tools = {
    ["fetch_webpage"] = {
      description = "Gives any model the ability to fetch content from a specific URL",
      ---@param self CodeCompanion.HTTPAdapter.OpenRouter
      ---@param meta { tools: table }
      callback = function(self, meta)
        table.insert(meta.tools, {
          type = "web_fetch",
        })
      end,
    },
    ["web_search"] = {
      description = "Gives any model access to real-time web information",
      ---@param self CodeCompanion.HTTPAdapter.OpenRouter
      ---@param meta { tools: table }
      callback = function(self, meta)
        table.insert(meta.tools, {
          type = "web_search",
        })
      end,
    },
  },
  features = {
    text = true,
    tokens = true,
  },
  url = "https://openrouter.ai/api/v1/chat/completions",
  env = {
    api_key = "OPENROUTER_API_KEY",
  },
  headers = {
    Authorization = "Bearer ${api_key}",
    ["Content-Type"] = "application/json",
    ["HTTP-Referer"] = "https://codecompanion.olimorris.dev",
    ["X-OpenRouter-Categories"] = "ide-extension",
    ["X-OpenRouter-Title"] = "CodeCompanion",
  },
  handlers = {
    ---Check for a token before starting the request
    ---@param self CodeCompanion.HTTPAdapter
    ---@return boolean
    setup = function(self)
      local model = self.schema.model.default
      local choices = self.schema.model.choices
      if type(model) == "function" then
        model = model(self)
      end
      if type(choices) == "function" then
        choices = choices(self, { async = false })
      end
      local model_opts = choices[model]

      if self.opts and self.opts.stream then
        self.parameters.stream = true
      end
      if (self.opts and self.opts.tools) and (model_opts and model_opts.opts and not model_opts.opts.can_use_tools) then
        self.opts.tools = false
      end
      if (self.opts and self.opts.vision) and (model_opts and model_opts.opts and not model_opts.opts.has_vision) then
        self.opts.vision = false
      end
      self.opts.can_form_structured_outputs = (
        model_opts
        and model_opts.opts
        and model_opts.opts.can_form_structured_outputs
      ) or false

      -- Some models only support a subset of reasoning efforts, or, none at all
      local reasoning = model_opts and model_opts.opts and model_opts.opts.reasoning
      if reasoning and reasoning.supported and self.parameters.reasoning then
        local effort = self.parameters.reasoning.effort
        if not vim.tbl_contains(reasoning.supported, effort) then
          self.parameters.reasoning.effort = reasoning.default or reasoning.supported[1]
        end
      end

      return true
    end,

    tokens = function(self, data)
      return openai.handlers.tokens(self, data)
    end,
    ---@param self CodeCompanion.HTTPAdapter
    ---@param params table
    ---@param messages table
    ---@return table
    form_parameters = function(self, params, messages)
      params = openai.handlers.form_parameters(self, params, messages)

      -- Enable automatic caching with Anthropic
      -- Ref: https://openrouter.ai/docs/features/prompt-caching#anthropic-claude
      local model = self.schema.model.default
      if model and model:find("anthropic", 1, true) then
        params.cache_control = { type = "ephemeral" }
      end

      return params
    end,
    ---Send the chat's session ID so OpenRouter can pin sticky sessions and track cost
    ---Ref: https://openrouter.ai/docs/guides/best-practices/prompt-caching#using-session_id-for-sticky-sessions
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data table The request payload built by the chat buffer
    ---@return table|nil
    set_body = function(self, data)
      -- A user's session ID takes priority...
      if self.opts and self.opts.session_id then
        return { session_id = self.opts.session_id }
      end

      -- ...over one from the chat buffer
      if data and data.session_id then
        return { session_id = data.session_id }
      end
    end,
    ---Provides the schemas of the tools that are available to the LLM to call
    ---@param self CodeCompanion.HTTPAdapter
    ---@param tools table<string, table>
    ---@return table|nil
    form_tools = function(self, tools)
      if not self.opts.tools or not tools then
        return nil
      end
      if vim.tbl_count(tools) == 0 then
        return nil
      end

      local transformed = {}
      for _, tool in pairs(tools) do
        for _, schema in pairs(tool) do
          if schema._meta and schema._meta.adapter_tool then
            if self.available_tools[schema.name] then
              self.available_tools[schema.name].callback(self, { tools = transformed })
            end
          else
            table.insert(transformed, schema)
          end
        end
      end

      return { tools = transformed }
    end,
    ---OpenRouter passes structured outputs through to the underlying provider using OpenAI's shape
    ---@param self CodeCompanion.HTTPAdapter
    ---@param schema CodeCompanion.StructuredOutput.Schema
    ---@return table|nil
    form_structured_output = function(self, schema)
      ---Ref: https://openrouter.ai/docs/guides/features/structured-outputs#using-structured-outputs
      if not schema or not self.opts.can_form_structured_outputs then
        return nil
      end
      return openai.handlers.form_structured_output(self, schema)
    end,
    ---@param self CodeCompanion.HTTPAdapter
    ---@param messages table
    ---@return table
    form_messages = function(self, messages)
      if not self.opts.tools then
        messages = vim
          .iter(messages)
          :filter(function(m)
            return not (m.role == "tool" or (m.tools and m.tools.calls))
          end)
          :totable()
      end

      local result = openai.handlers.form_messages(self, messages)

      -- OpenRouter requires reasoning to be preserved in any subsequent requests
      -- Ref: https://openrouter.ai/docs/guides/best-practices/reasoning-tokens#preserving-reasoning
      for _, message in ipairs(result.messages) do
        if type(message.reasoning) == "table" and message.reasoning._data then
          message.reasoning_details = message.reasoning._data.reasoning_details
        end
        message.reasoning = nil
      end

      return result
    end,

    ---Surface the reasoning text and the reasoning blocks that must be sent back
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data table
    ---@param tools? table
    ---@return table|nil
    chat_output = function(self, data, tools)
      local output = openai.handlers.chat_output(self, data, tools)
      if not output then
        return output
      end

      -- To preserve reasoning, ensure it's saved to the chat buffer
      local extra = output.extra
      if extra and extra.reasoning and extra.reasoning ~= "" then
        output.output.reasoning = output.output.reasoning or {}
        output.output.reasoning.content = extra.reasoning
      end

      if extra and extra.reasoning_details then
        output.output.reasoning = output.output.reasoning or {}
        output.output.reasoning.reasoning_details = extra.reasoning_details
      end
      if output.output.content == "" then
        output.output.content = nil
      end

      return output
    end,

    ---Collapse the reasoning chunks collected while streaming into a single block
    ---@param self CodeCompanion.HTTPAdapter
    ---@param data table The reasoning items gathered by the chat buffer
    ---@return nil|{ content: string, _data: table }
    form_reasoning = function(self, data)
      local content = vim
        .iter(data)
        :map(function(item)
          return item.content
        end)
        :filter(function(content)
          return content ~= nil
        end)
        :join("")

      -- Streamed `reasoning_details` arrive as deltas: text-bearing fields for the
      -- same block are split across chunks and grouped by `index`, while complete
      -- blocks (e.g. encrypted) carry no index. Merge deltas by index, keep the rest.
      -- Metadata fields (type, format, index) repeat unchanged each chunk, so any
      -- field whose value grows across chunks is treated as streamed text and joined
      local details = {}
      local details_by_index = {}
      for _, item in ipairs(data) do
        for _, detail in ipairs(item.reasoning_details or {}) do
          local existing = detail.index ~= nil and details_by_index[detail.index]
          if existing then
            for key, value in pairs(detail) do
              if type(value) == "string" and type(existing[key]) == "string" and existing[key] ~= value then
                existing[key] = existing[key] .. value
              else
                existing[key] = value
              end
            end
          else
            local copy = vim.deepcopy(detail)
            table.insert(details, copy)
            if detail.index ~= nil then
              details_by_index[detail.index] = copy
            end
          end
        end
      end

      return {
        content = content,
        _data = {
          reasoning_details = details,
        },
      }
    end,
    tools = {
      format_tool_calls = function(self, tools)
        return openai.handlers.tools.format_tool_calls(self, tools)
      end,
      output_response = function(self, tool_call, output)
        return openai.handlers.tools.output_response(self, tool_call, output)
      end,
    },
    inline_output = function(self, data, context)
      return openai.handlers.inline_output(self, data, context)
    end,
    on_exit = function(self, data)
      return openai.handlers.on_exit(self, data)
    end,
  },
  schema = {
    ---@type CodeCompanion.Schema
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      ---@type string|fun(): string
      default = "openai/gpt-5.4-mini",
      ---@param opts? { async?: boolean }
      ---@return table
      choices = function(self, opts)
        return fetch_models.get(models_source, self, opts)
      end,
    },
    ["reasoning.effort"] = {
      order = 2,
      mapping = "parameters",
      type = "string",
      optional = true,
      ---@param self CodeCompanion.HTTPAdapter
      ---@return string
      default = function(self)
        local choices = model_choices(self)
        return (choices and choices.reasoning and choices.reasoning.default) or "medium"
      end,
      enabled = function(self)
        return model_supports(self, "reasoning")
      end,
      desc = "Constrains effort on reasoning for reasoning models. Reducing reasoning effort can result in faster responses and fewer tokens used on reasoning in a response. Not all efforts are supported by every model.",
      ---@param self CodeCompanion.HTTPAdapter
      ---@return string[]
      choices = function(self)
        local choices = model_choices(self)
        if choices and choices.reasoning and choices.reasoning.supported then
          return choices.reasoning.supported
        end
        return { "xhigh", "high", "medium", "low", "minimal", "none" }
      end,
    },
    temperature = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      enabled = function(self)
        return model_supports(self, "temperature")
      end,
      desc = "This setting influences the variety in the model’s responses. Lower values lead to more predictable and typical responses, while higher values encourage more diverse and less common responses. At 0, the model always gives the same response for a given input.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    top_p = {
      order = 4,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      enabled = function(self)
        return model_supports(self, "top_p")
      end,
      desc = "This setting limits the model’s choices to a percentage of likely tokens: only the top tokens whose probabilities add up to P. A lower value makes the model’s responses more predictable, while the default setting allows for a full range of token choices. Think of it like a dynamic Top-K.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    top_k = {
      order = 5,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      enabled = function(self)
        return model_supports(self, "top_k")
      end,
      desc = "This limits the model’s choice of tokens at each step, making it choose from a smaller set. A value of 1 means the model will always pick the most likely next token, leading to predictable results. By default this setting is disabled, making the model to consider all choices.",
      validate = function(n)
        return n >= 1, "Must be greater than or equal to 1"
      end,
    },
    min_p = {
      order = 6,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      enabled = function(self)
        return model_supports(self, "min_p")
      end,
      desc = "Represents the minimum probability for a token to be considered, relative to the probability of the most likely token. (The value changes depending on the confidence level of the most probable token.) If your Min-P is set to 0.1, that means it will only allow for tokens that are at least 1/10th as probable as the best possible option.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    stop = {
      order = 7,
      mapping = "parameters",
      type = "list",
      optional = true,
      default = nil,
      enabled = function(self)
        return model_supports(self, "stop")
      end,
      subtype = {
        type = "string",
      },
      desc = "Up to 4 sequences where the API will stop generating further tokens.",
      validate = function(l)
        return #l >= 1 and #l <= 4, "Must have between 1 and 4 elements"
      end,
    },
    presence_penalty = {
      order = 8,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      enabled = function(self)
        return model_supports(self, "presence_penalty")
      end,
      desc = "Adjusts how often the model repeats specific tokens already used in the input. Higher values make such repetition less likely, while negative values do the opposite. Token penalty does not scale with the number of occurrences. Negative values will encourage token reuse.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    frequency_penalty = {
      order = 9,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      enabled = function(self)
        return model_supports(self, "frequency_penalty")
      end,
      desc = "This setting aims to control the repetition of tokens based on how often they appear in the input. It tries to use less frequently those tokens that appear more in the input, proportional to how frequently they occur. Token penalty scales with the number of occurrences. Negative values will encourage token reuse.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    -- Ref: https://openrouter.ai/docs/guides/features/presets
    preset = {
      order = 10,
      mapping = "parameters",
      type = "string",
      optional = true,
      default = nil,
      desc = "Presets allow you to separate your LLM configuration from your code. Create and manage presets through the OpenRouter web application to control provider routing, model selection, system prompts, and other parameters, then reference them in OpenRouter API requests.",
    },
    -- Ref: https://openrouter.ai/docs/guides/routing/provider-selection
    provider = {
      order = 11,
      mapping = "parameters",
      type = "map",
      optional = true,
      default = nil,
      desc = "OpenRouter routes requests to the best available providers for your model. By default, requests are load balanced across the top providers to maximize uptime.",
    },
  },
}
