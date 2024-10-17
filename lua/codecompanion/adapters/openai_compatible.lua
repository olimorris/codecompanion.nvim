local config = require("codecompanion.config")

local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.messages")

local curl = require("plenary.curl")

---Get a list of available OpenAI compatible models
---@params self CodeCompanion.Adapter
---@params opts? table
---@return table
local function get_models(self, opts)
  local adapter = require("codecompanion.adapters").resolve(self)
  if not adapter then
    log:error("Could not resolve OpenAI compatible adapter in the `get_models` function")
    return {}
  end

  adapter:get_env_vars()
  local url = adapter.env_replaced.url

  local headers = {
    ["content-type"] = "application/json",
  }
  if adapter.env_replaced.api_key then
    headers["Authorization"] = "Bearer " .. adapter.env_replaced.api_key
  end

  local ok, response = pcall(function()
    return curl.get(url .. "/v1/models", {
      sync = true,
      headers = headers,
      insecure = config.adapters.opts.allow_insecure,
      proxy = config.adapters.opts.proxy,
    })
  end)
  if not ok then
    log:error("Could not get the OpenAI compatible models from " .. url .. "/v1/models.\nError: %s", response)
    return {}
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Could not parse the response from " .. url .. "/v1/models")
    return {}
  end

  local models = {}
  for _, model in ipairs(json.data) do
    table.insert(models, model.id)
  end

  if opts and opts.last then
    return models[1]
  end
  return models
end

local function get_url(self, opts)
  local adapter = require("codecompanion.adapters").resolve(self)
  local url = adapter.env_replaced.url
  if not adapter.env_replaced.url then
    url = "http://localhost:11434"
  end
  return url
end

---@class Gemini.Adapter: CodeCompanion.Adapter
return {
  name = "openai_compatible",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    stream = true,
  },
  features = {
    text = true,
    tokens = true,
    vision = false,
  },
  url = "${url}/v1/chat/completions",
  env = {
    api_key = "OPENAI_API_KEY",
    url = function(self)
      return get_url(self)
    end,
  },
  raw = {
    "--no-buffer",
    "--silent",
  },
  headers = {
    ["Content-Type"] = "application/json",
    Authorization = "Bearer ${api_key}",
  },
  handlers = {
    ---@param self CodeCompanion.Adapter
    ---@return boolean
    setup = function(self)
      if self.opts and self.opts.stream then
        self.parameters.stream = true
        self.parameters.stream_options = { include_usage = true }
      end
      return true
    end,

    ---Set the parameters
    ---@param self CodeCompanion.Adapter
    ---@param params table
    ---@param messages table
    ---@return table
    form_parameters = function(self, params, messages)
      return params
    end,

    ---Set the format of the role and content for the messages from the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param messages table Format is: { { role = "user", content = "Your prompt here" } }
    ---@return table
    form_messages = function(self, messages)
      return { messages = messages }
    end,

    ---Returns the number of tokens generated from the LLM
    ---@param self CodeCompanion.Adapter
    ---@param data table The data from the LLM
    ---@return number|nil
    tokens = function(self, data)
      if data and data ~= "" then
        local data_mod = (self.opts and self.opts.stream) and data:sub(7) or data.body
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

        if ok then
          if json.usage then
            local tokens = json.usage.total_tokens
            log:trace("Tokens: %s", tokens)
            return tokens
          end
        end
      end
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param data table The streamed JSON data from the API, also formatted by the format_data handler
    ---@return table|nil [status: string, output: table]
    chat_output = function(self, data)
      local output = {}

      if data and data ~= "" then
        local data_mod = (self.opts and self.opts.stream) and data:sub(7) or data.body
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

        if ok then
          if json.choices and #json.choices > 0 then
            local choice = json.choices[1]
            local delta = (self.opts and self.opts.stream) and choice.delta or choice.message

            if delta.content then
              output.content = delta.content
              output.role = delta.role or nil

              return {
                status = "success",
                output = output,
              }
            end
          end
        end
      end
    end,

    ---Output the data from the API ready for inlining into the current buffer
    ---@param self CodeCompanion.Adapter
    ---@param data table The streamed JSON data from the API, also formatted by the format_data handler
    ---@param context table Useful context about the buffer to inline to
    ---@return string|table|nil
    inline_output = function(self, data, context)
      if data and data ~= "" then
        data = (self.opts and self.opts.stream) and data:sub(7) or data.body
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if ok then
          --- Some third-party OpenAI forwarding services may have a return package with an empty json.choices.
          if not json.choices or #json.choices == 0 then
            return
          end

          local choice = json.choices[1]
          local delta = (self.opts and self.opts.stream) and choice.delta or choice.message
          if delta.content then
            return delta.content
          end
        end
      end
    end,

    ---Function to run when the request has completed. Useful to catch errors
    ---@param self CodeCompanion.Adapter
    ---@param data table
    ---@return nil
    on_exit = function(self, data)
      if data.status >= 400 then
        log:error("Error: %s", data.body)
      end
    end,
  },
  schema = {
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      default = function(self)
        return get_models(self, { last = true })
      end,
      choices = function(self)
        return get_models(self)
      end,
    },
    temperature = {
      order = 2,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 0.8,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    num_ctx = {
      order = 3,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 2048,
      desc = "The maximum number of tokens that the language model can consider at once. This determines the size of the input context window, allowing the model to take into account longer text passages for generating responses. Adjusting this value can affect the model's performance and memory usage.",
      validate = function(n)
        return n > 0, "Must be a positive number"
      end,
    },
    mirostat = {
      order = 4,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 0,
      desc = "Enable Mirostat sampling for controlling perplexity. (default: 0, 0 = disabled, 1 = Mirostat, 2 = Mirostat 2.0)",
      validate = function(n)
        return n == 0 or n == 1 or n == 2, "Must be 0, 1, or 2"
      end,
    },
    mirostat_eta = {
      order = 5,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 0.1,
      desc = "Influences how quickly the algorithm responds to feedback from the generated text. A lower learning rate will result in slower adjustments, while a higher learning rate will make the algorithm more responsive. (Default: 0.1)",
      validate = function(n)
        return n > 0, "Must be a positive number"
      end,
    },
    mirostat_tau = {
      order = 6,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 5.0,
      desc = "Controls the balance between coherence and diversity of the output. A lower value will result in more focused and coherent text. (Default: 5.0)",
      validate = function(n)
        return n > 0, "Must be a positive number"
      end,
    },
    repeat_last_n = {
      order = 7,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 64,
      desc = "Sets how far back for the model to look back to prevent repetition. (Default: 64, 0 = disabled, -1 = num_ctx)",
      validate = function(n)
        return n >= -1, "Must be -1 or greater"
      end,
    },
    repeat_penalty = {
      order = 8,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 1.1,
      desc = "Sets how strongly to penalize repetitions. A higher value (e.g., 1.5) will penalize repetitions more strongly, while a lower value (e.g., 0.9) will be more lenient. (Default: 1.1)",
      validate = function(n)
        return n >= 0, "Must be a non-negative number"
      end,
    },
    seed = {
      order = 9,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 0,
      desc = "Sets the random number seed to use for generation. Setting this to a specific number will make the model generate the same text for the same prompt. (Default: 0)",
      validate = function(n)
        return n >= 0, "Must be a non-negative number"
      end,
    },
    stop = {
      order = 10,
      mapping = "parameters.options",
      type = "string",
      optional = true,
      default = nil,
      desc = "Sets the stop sequences to use. When this pattern is encountered the LLM will stop generating text and return. Multiple stop patterns may be set by specifying multiple separate stop parameters in a modelfile.",
      validate = function(s)
        return s:len() > 0, "Cannot be an empty string"
      end,
    },
    tfs_z = {
      order = 11,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 1.0,
      desc = "Tail free sampling is used to reduce the impact of less probable tokens from the output. A higher value (e.g., 2.0) will reduce the impact more, while a value of 1.0 disables this setting. (default: 1)",
      validate = function(n)
        return n >= 0, "Must be a non-negative number"
      end,
    },
    num_predict = {
      order = 12,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = -1,
      desc = "Maximum number of tokens to predict when generating text. (Default: -1, -1 = infinite generation, -2 = fill context)",
      validate = function(n)
        return n >= -2, "Must be -2 or greater"
      end,
    },
    top_k = {
      order = 13,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 40,
      desc = "Reduces the probability of generating nonsense. A higher value (e.g. 100) will give more diverse answers, while a lower value (e.g. 10) will be more conservative. (Default: 40)",
      validate = function(n)
        return n >= 0, "Must be a non-negative number"
      end,
    },
    top_p = {
      order = 14,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 0.9,
      desc = "Works together with top-k. A higher value (e.g., 0.95) will lead to more diverse text, while a lower value (e.g., 0.5) will generate more focused and conservative text. (Default: 0.9)",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    max_tokens = {
      order = 5,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    presence_penalty = {
      order = 6,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    frequency_penalty = {
      order = 7,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0,
      desc = "Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    logit_bias = {
      order = 8,
      mapping = "parameters",
      type = "map",
      optional = true,
      default = nil,
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
