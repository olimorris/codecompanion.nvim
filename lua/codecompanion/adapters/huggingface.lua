local log = require("codecompanion.utils.log")

---@class HuggingFace.Adapter: CodeCompanion.Adapter
return {
  name = "huggingface",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    stream = true,
  },
  features = {
    text = true,
    tokens = false,
    vision = true,
  },
  url = "${url}/models/${model}/v1/chat/completions",
  env = {
    api_key = "HUGGINGFACE_API_KEY",
    url = "https://api-inference.huggingface.co",
    model = "schema.model.default",
  },
  raw = {
    "--no-buffer",
    "--silent",
  },
  headers = {
    ["Content-Type"] = "application/json",
    Authorization = "Bearer ${api_key}",
  },
  -- NOTE: currently, decided to not implment the tokens counter handle, since the API infernce docs
  -- says it is supported, yet, the usage is returning null when the stream is enabled
  handlers = {
    ---@param self CodeCompanion.Adapter
    ---@return boolean
    setup = function(self)
      if self.opts and self.opts.stream then
        self.parameters.stream = true
      end
      -- Set model in env_replaced for URL construction
      self.env_replaced = self.env_replaced or {}
      self.env_replaced.model = self.parameters.model or self.schema.model.default

      -- Add headers with string values
      if self.parameters.use_cache then
        self.headers["x-use-cache"] = self.parameters.use_cache -- Already a string
      end
      if self.parameters.wait_for_model then
        self.headers["x-wait-for-model"] = self.parameters.wait_for_model -- Already a string
      end

      return true
    end,

    ---Set the parameters
    ---@param self CodeCompanion.Adapter
    ---@param params table
    ---@param messages table
    ---@return table
    form_parameters = function(self, params, messages)
      params.model = self.parameters.model or self.schema.model.default
      return params
    end,

    ---Set the format of the role and content for the messages from the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param messages table
    ---@return table
    form_messages = function(self, messages)
      return { messages = messages }
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param data string
    ---@return table|nil
    chat_output = function(self, data)
      local output = {}

      if data and data ~= "" then
        local data_mod = (self.opts and self.opts.stream) and data:sub(7) or data.body
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

        if ok and json.choices and #json.choices > 0 then
          local choice = json.choices[1]
          local delta = (self.opts and self.opts.stream) and choice.delta or choice.message

          if delta then
            if delta.role then
              output.role = delta.role
            else
              output.role = nil
            end

            if delta.content then
              output.content = delta.content
            else
              output.content = ""
            end

            return {
              status = "success",
              output = output,
            }
          end
        end
      end
    end,

    ---Output the data from the API ready for inlining into the current buffer
    ---@param self CodeCompanion.Adapter
    ---@param data table
    ---@param context table
    ---@return string|table|nil
    inline_output = function(self, data, context)
      if data and data ~= "" then
        data = (self.opts and self.opts.stream) and data:sub(7) or data.body
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if ok then
          if not json.choices or #json.choices == 0 then
            return
          end

          local choice = json.choices[1]
          local delta = (self.opts and self.opts.stream) and choice.delta or choice.message
          if delta and delta.content then
            return delta.content
          end
        end
      end
    end,

    ---Function to run when the request has completed
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
      desc = "ID of the model to use from Hugging Face.",
      default = "Qwen/Qwen2.5-72B-Instruct",
      choices = {
        "meta-llama/Llama-3.2-1B-Instruct",
        "Qwen/Qwen2.5-72B-Instruct",
        "google/gemma-2-2b-it",
        "mistralai/Mistral-Nemo-Instruct-2407",
      },
    },
    temperature = {
      order = 2,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0.5,
      desc = "What sampling temperature to use, between 0 and 2.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    max_tokens = {
      order = 3,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = 2048,
      desc = "The maximum number of tokens to generate.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    top_p = {
      order = 4,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0.7,
      desc = "Nucleus sampling parameter.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    -- caveat to using the cache: https://huggingface.co/docs/api-inference/parameters#caching
    ["x-use-cache"] = {
      order = 5,
      mapping = "headers",
      type = "string",
      optional = true,
      default = "true",
      desc = "Whether to use the cache layer on the inference API...",
      choices = { "true", "false" },
    },
    ["x-wait-for-model"] = {
      order = 6,
      mapping = "headers",
      type = "string",
      optional = true,
      default = "false",
      desc = "Whether to wait for the model to be loaded...",
      choices = { "true", "false" },
    },
  },
}
