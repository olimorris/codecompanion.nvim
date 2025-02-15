---Source:
---https://github.com/google-gemini/cookbook/blob/main/quickstarts/rest/Streaming_REST.ipynb

local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.adapters")

---@class Gemini.Adapter: CodeCompanion.Adapter
return {
  name = "gemini",
  formatted_name = "Gemini",
  roles = {
    llm = "model",
    user = "user",
  },
  opts = {
    stream = true,
  },
  features = {
    tokens = true,
    text = true,
    vision = true,
  },
  url = "https://generativelanguage.googleapis.com/v1beta/models/${model}${stream}key=${api_key}",
  env = {
    api_key = "GEMINI_API_KEY",
    model = "schema.model.default",
    stream = function(self)
      local stream = ":generateContent?"
      if self.opts.stream then
        -- NOTE: With sse each stream chunk is a GenerateContentResponse object with a portion of the output text in candidates[0].content.parts[0].text
        stream = ":streamGenerateContent?alt=sse&"
      end
      return stream
    end,
  },
  headers = {
    ["Content-Type"] = "application/json",
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
    ---@param messages table Format is: { contents = { parts { text = "Your prompt here" } }
    ---@return table
    form_messages = function(self, messages)
      local system = vim
        .iter(messages)
        :filter(function(msg)
          return msg.role == "system"
        end)
        :map(function(msg)
          return { text = msg.content }
        end)
        :totable()

      local system_instruction
      if #system > 0 then
        system_instruction = {
          role = self.roles.user,
          parts = system,
        }
      end

      -- Format messages (remove all system prompts)
      local output = vim
        .iter(messages)
        :filter(function(msg)
          return msg.role ~= "system"
        end)
        :map(function(msg)
          return {
            role = self.roles.user,
            parts = {
              { text = msg.content },
            },
          }
        end)
        :totable()

      local result = {
        contents = output,
      }

      if system_instruction then
        result.system_instruction = system_instruction
      end

      return result
    end,

    ---Returns the number of tokens generated from the LLM
    ---@param self CodeCompanion.Adapter
    ---@param data string The data from the LLM
    ---@return number|nil
    tokens = function(self, data)
      if data and data ~= "" then
        data = utils.clean_streamed_data(data)
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if ok then
          return json.usageMetadata.totalTokenCount
        end
      end
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param data string The streamed JSON data from the API, also formatted by the format_data handler
    ---@return table|nil
    chat_output = function(self, data)
      local output = {}

      if data and data ~= "" then
        data = utils.clean_streamed_data(data)
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if ok and json.candidates[1].content then
          output.role = "llm"
          output.content = json.candidates[1].content.parts[1].text

          return {
            status = "success",
            output = output,
          }
        end
      end
    end,

    ---Output the data from the API ready for inlining into the current buffer
    ---@param self CodeCompanion.Adapter
    ---@param data table The streamed JSON data from the API, also formatted by the format_data handler
    ---@param context? table Useful context about the buffer to inline to
    ---@return table|nil
    inline_output = function(self, data, context)
      if self.opts.stream then
        return log:error("Inline output is not supported for non-streaming models")
      end

      if data and data ~= "" then
        local ok, json = pcall(vim.json.decode, data.body, { luanil = { object = true } })

        if not ok then
          return { status = "error", output = json }
        end

        local text = json.candidates[1].content.parts[1].text
        if text then
          return { status = "success", output = text }
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
      type = "enum",
      desc = "The model that will complete your prompt. See https://ai.google.dev/gemini-api/docs/models/gemini#model-variations for additional details and options.",
      default = "gemini-2.0-flash",
      choices = {
        "gemini-2.0-flash",
        "gemini-1.5-flash",
        "gemini-1.5-pro",
        "gemini-1.0-pro",
      },
    },
    maxOutputTokens = {
      order = 2,
      mapping = "body.generationConfig",
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum number of tokens to include in a response candidate. Note: The default value varies by model",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    temperature = {
      order = 3,
      mapping = "body.generationConfig",
      type = "number",
      optional = true,
      default = nil,
      desc = "Controls the randomness of the output.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    topP = {
      order = 4,
      mapping = "body.generationConfig",
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum cumulative probability of tokens to consider when sampling. The model uses combined Top-k and Top-p (nucleus) sampling. Tokens are sorted based on their assigned probabilities so that only the most likely tokens are considered. Top-k sampling directly limits the maximum number of tokens to consider, while Nucleus sampling limits the number of tokens based on the cumulative probability.",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    topK = {
      order = 5,
      mapping = "body.generationConfig",
      type = "integer",
      optional = true,
      default = nil,
      desc = "The maximum number of tokens to consider when sampling",
      validate = function(n)
        return n > 0, "Must be greater than 0"
      end,
    },
    presencePenalty = {
      order = 6,
      mapping = "body.generationConfig",
      type = "number",
      optional = true,
      default = nil,
      desc = "Presence penalty applied to the next token's logprobs if the token has already been seen in the response",
    },
    frequencyPenalty = {
      order = 7,
      mapping = "body.generationConfig",
      type = "number",
      optional = true,
      default = nil,
      desc = "Frequency penalty applied to the next token's logprobs, multiplied by the number of times each token has been seen in the response so far.",
    },
  },
}
