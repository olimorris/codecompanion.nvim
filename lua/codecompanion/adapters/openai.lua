local log = require("codecompanion.utils.log")

---@class CodeCompanion.AdapterArgs
return {
  name = "openai",
  roles = {
    llm = "assistant",
    user = "user",
  },
  features = {
    text = true,
    tokens = true,
    vision = true,
  },
  url = "https://api.openai.com/v1/chat/completions",
  env = {
    api_key = "OPENAI_API_KEY",
  },
  raw = {
    "--no-buffer",
    "--silent",
  },
  headers = {
    ["Content-Type"] = "application/json",
    Authorization = "Bearer ${api_key}",
  },
  parameters = {
    stream = true,
    stream_options = {
      include_usage = true,
    },
  },
  handlers = {
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
        local data_mod = self.parameters.stream and data:sub(7) or data
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
        local data_mod = self.parameters.stream and data:sub(7) or data
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

        if ok then
          if #json.choices > 0 then
            local choice = json.choices[1]
            local delta = self.parameters.stream and choice.delta or choice.message

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
        data = self.parameters.stream and data:sub(7) or data
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if ok then
          --- Some third-party OpenAI forwarding services may have a return package with an empty json.choices.
          if #json.choices == 0 then
            return
          end

          local choice = json.choices[1]
          local delta = self.parameters.stream and choice.delta or choice.message
          if delta.content then
            return delta.content
          end
        end
      end
    end,

    ---Function to catch any errors from the standard output
    ---@param self CodeCompanion.Adapter
    ---@param data table
    ---@return nil
    on_stdout = function(self, data)
      local stdout = table.concat(data._stdout_results)

      local ok, json = pcall(vim.json.decode, stdout, { luanil = { object = true } })
      if ok then
        log:trace("stdout: %s", json)
        if json.error then
          log:error("Error: %s", json.error.message)
        end
      end
    end,
  },
  schema = {
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      default = "gpt-4o",
      choices = {
        "gpt-4o",
        "gpt-4o-mini",
        "gpt-4-turbo-preview",
        "gpt-4",
        "gpt-3.5-turbo",
      },
    },
    temperature = {
      order = 2,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    top_p = {
      order = 3,
      mapping = "parameters",
      type = "number",
      optional = true,
      default = 1,
      desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
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
      desc = "Up to 4 sequences where the API will stop generating further tokens.",
      validate = function(l)
        return #l >= 1 and #l <= 4, "Must have between 1 and 4 elements"
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
    user = {
      order = 9,
      mapping = "parameters",
      type = "string",
      optional = true,
      default = nil,
      desc = "A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. Learn more.",
      validate = function(u)
        return u:len() < 100, "Cannot be longer than 100 characters"
      end,
    },
  },
}
