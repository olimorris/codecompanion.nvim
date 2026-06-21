local Curl = require("plenary.curl")
local adapter_utils = require("codecompanion.utils.adapters")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.http.openai")

---@class OpenRouterModels
---@field archirecture { input_modalities: string[], output_modalities: string[] } e.g. { input_modalities = { "text", "image" }, output_modalities = { "text" } }
---@field context_length number e.g. 1000000
---@field created number e.g. 1759161676
---@field default_parameters table e.g. { temperature = 1, top_p = 1, top_k = null }
---@field description string
---@field id string e.g. anthropic/claude-sonnet-4.5
---@field name string e.g. Anthropic: Claude Sonnet 4.5
---@field pricing table

local _cache_expires
local _cache_file = vim.fn.tempname()
local _cached_models

---Get a list of available models
---@params self CodeCompanion.HTTPAdapter
---@params opts? table
---@return table
local function get_models()
  if _cached_models and _cache_expires and _cache_expires > os.time() then
    return _cached_models
  end

  local url = "https://openrouter.ai/api/v1/models"

  local ok
  local response ---@type OpenRouterModels

  ok, response = pcall(function()
    return Curl.get(url, {
      headers = {
        Authorization = "Bearer ${api_key}",
      },
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
      sync = true,
    })
  end)
  if not ok then
    log:error("Could not get the OpenRouter models from " .. url .. "\nError: %s", response)
    return {}
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Error parsing the response from " .. url .. "\nError: %s", response.body)
    return {}
  end

  local models = {}
  for _, model in ipairs(json.data) do
    -- Turn the model's `supported_parameters` array into a lookup set so the
    -- schema fields can check, per model, which parameters the API accepts
    local supported = {}
    for _, parameter in ipairs(model.supported_parameters or {}) do
      supported[parameter] = true
    end

    local choice_opts = {
      supported_parameters = supported,
      can_use_tools = supported.tools or false,
      can_reason = supported.reasoning or false,
    }
    if model.architecture and model.architecture.input_modalities then
      choice_opts.has_vision = vim.tbl_contains(model.architecture.input_modalities, "image")
    end

    models[model.id] = {
      formatted_name = model.name,
      meta = model.context_length and { context_window = model.context_length } or nil,
      opts = choice_opts,
    }
  end

  _cached_models = models
  _cache_expires = adapter_utils.refresh_cache(_cache_file, config.adapters.http.opts.cache_models_for)

  return models
end

---Check whether the currently selected model supports the given parameter
---@param self CodeCompanion.HTTPAdapter
---@param parameter string
---@return boolean
local function model_supports(self, parameter)
  local cached_models = get_models()
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
    provider = {},
    stream = true,
    tools = true,
    vision = true,
  },
  available_tools = {
    ["web_fetch"] = {
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
    ["HTTP-Referer"] = "https://github.com/olimorris/codecompanion.nvim",
    ["X-OpenRouter-Categories"] = "ide-extension",
    ["X-OpenRouter-Title"] = "codecompanion.nvim",
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
        choices = choices(self)
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

      -- Enable provider routing options
      -- Ref: https://openrouter.ai/docs/guides/routing/provider-selection
      if self.opts.provider and type(self.opts.provider) == "table" and vim.tbl_count(self.opts.provider) > 0 then
        params.provider = self.opts.provider
      end

      return params
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
      ---@return table
      choices = function(self)
        return get_models()
      end,
    },
    ["reasoning.effort"] = {
      order = 2,
      mapping = "parameters",
      type = "string",
      optional = true,
      default = "medium",
      enabled = function(self)
        return model_supports(self, "reasoning")
      end,
      desc = "Constrains effort on reasoning for reasoning models. Reducing reasoning effort can result in faster responses and fewer tokens used on reasoning in a response.",
      choices = {
        "xhigh",
        "high",
        "medium",
        "low",
        "minimal",
        "none",
      },
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
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
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
      desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    top_k = {
      order = 5,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = -1,
      enabled = function(self)
        return model_supports(self, "top_k")
      end,
      desc = "Integer that controls the number of top tokens to consider. Set to -1 to consider all tokens",
      validate = function(n)
        return n >= -1, "Must be greater than or equal to -1"
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
      desc = "Float that represents the minimum probability for a token to be considered, relative to the probability of the most likely token",
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
      desc = "Float that penalizes new tokens based on whether they appear in the generated text so far. Values > 0 encourage the model to use new tokens, while values < 0 encourage the model to repeat tokens",
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
      desc = "Float that penalizes new tokens based on their frequency in the generated text so far. Values > 0 encourage the model to use new tokens, while values < 0 encourage the model to repeat tokens",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    logit_bias = {
      order = 10,
      mapping = "parameters",
      type = "map",
      optional = true,
      default = nil,
      enabled = function(self)
        return model_supports(self, "logit_bias")
      end,
      desc = "Modify the likelihood of specified tokens appearing in the completion. Maps tokens (specified by their token ID) to an associated bias value from -100 to 100. Use https://platform.openai.com/tokenizer to find token IDs.",
      subtype_key = {
        type = "integer",
      },
      subtype = {
        type = "integer",
        validate = function(n)
          return n >= -100 and n <= 100, "Must be between -100 and 100"
        end,
      },
    },
  },
}
