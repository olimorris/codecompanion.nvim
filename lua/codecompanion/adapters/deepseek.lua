local log = require("codecompanion.utils.log")

---Prepare data to be parsed as JSON
---@param data string | { body: string }
---@return string
local prepare_data_for_json = function(data)
  if type(data) == "table" then
    return data.body
  end
  local find_json_start = string.find(data, "{") or 1
  return string.sub(data, find_json_start)
end

--@class DeepSeek.Adapter: CodeCompanion.Adapter
return {
  name = "deepseek",
  roles = {
    llm = "system",
    user = "user",
  },
  opts = {
    stream = true,
  },
  features = {
    text = true,
    tokens = true,
    vision = true,
  },
  url = "https://api.deepseek.com/chat/completions",
  env = {
    api_key = "DEEPSEEK_API_KEY",
  },
  headers = {
    ["Content-Type"] = "application/json",
    Authorization = "Bearer ${api_key}",
  },
  handlers = {
    ---@param self CodeCompanion.Adapter
    ---@return boolean
    setup = function(self)
      local model = self.schema.model.default
      local model_opts = self.schema.model.choices[model]
      if model_opts and model_opts.opts then
        self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
      end

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
      local processed = {}
      local model = self.schema.model.default
      if type(model) == "function" then
        model = model()
      end

      ---System role is only allowed as the first message, after this we must label
      ---all system messages as assistant
      local has_system = false
      messages = vim
          .iter(messages)
          :map(function(m)
            local role = m.role
            if role == self.roles.llm then
              if not has_system then
                has_system = true
              else
                role = "assistant"
              end
            end
            return {
              role = role,
              content = m.content,
            }
          end)
          :totable()

      ---DeepSeek-R1 doesn't allow consecutive messages from the same role,
      ---so we concatenate them into a single message
      for _, msg in ipairs(messages) do
        local last = processed[#processed]
        if last and last.role == msg.role then
          last.content = last.content .. "\n\n" .. msg.content
        else
          table.insert(processed, {
            role = msg.role,
            content = msg.content
          })
        end
      end

      return { messages = processed }
    end,


    ---Returns the number of tokens generated from the LLM
    ---@param self CodeCompanion.Adapter
    ---@param data table The data from the LLM
    ---@return number|nil
    tokens = function(self, data)
      if data and data ~= "" then
        local data_mod = prepare_data_for_json(data)
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
        local data_mod = prepare_data_for_json(data)
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

            -- Some providers may return empty content
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
    ---@param data string|table The streamed JSON data from the API, also formatted by the format_data handler
    ---@param context table Useful context about the buffer to inline to
    ---@return string|table|nil
    inline_output = function(self, data, context)
      if data and data ~= "" then
        data = prepare_data_for_json(data)
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
      desc = "ID of the model to use.",
      ---@type string|fun(): string
      default = "deepseek-reasoner",
      choices = {
        "deepseek-reasoner",
        "deepseek-chat",
      },
    },
    temperature = {
      order = 2,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0.6,
      desc = "What sampling temperature to use, between 0 and 2. 0.5-0.7 is recommended by DeepSeek for coding tasks.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    top_p = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 0.95,
      desc =
      "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both. Not used for R1.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    stop = {
      order = 4,
      mapping = "parameters",
      type = "list",
      optional = true,
      default = nil,
      subtype = {
        type = "string",
      },
      desc = "Up to 16 sequences where the API will stop generating further tokens.",
      validate = function(l)
        return #l >= 1 and #l <= 16, "Must have between 1 and 16 elements"
      end,
    },
    max_tokens = {
      order = 5,
      mapping = "parameters",
      type = "integer",
      optional = true,
      default = 8192,
      desc =
      "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
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
      desc =
      "Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics. Not used for R1",
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
      desc =
      "Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim. Not used for R1, but may be specified.",
      validate = function(n)
        return n >= -2 and n <= 2, "Must be between -2 and 2"
      end,
    },
    logprobs = {
      order = 8,
      mapping = "parameters",
      type = "boolean",
      optional = true,
      default = nil,
      desc =
      "Whether to return log probabilities of the output tokens or not. If true, returns the log probabilities of each output token returned in the content of message. Not supported for R1.",
      subtype_key = {
        type = "integer",
      },
    },
    user = {
      order = 9,
      mapping = "parameters",
      type = "string",
      optional = true,
      default = nil,
      desc =
      "A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. Learn more.",
      validate = function(u)
        return u:len() < 100, "Cannot be longer than 100 characters"
      end,
    },
  },
}
