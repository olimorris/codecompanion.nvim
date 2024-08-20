local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.adapters")

local curl = require("plenary.curl")

---Get a list of available Ollama models
---@params self CodeCompanion.Adapter
---@params opts? table
---@return table
local function get_models(self, opts)
  local url = self.args.env.url

  -- Check that Ollama is running
  local ping = vim.fn.system('curl -s -o /dev/null -w "%{http_code}" ' .. url)
  if ping ~= "200" then
    log:warn("Ollama is not running or cannot be found on localhost:11434")
    return {}
  end

  local response = curl.get(url .. "/v1/models", {
    sync = true,
  })
  if not response then
    return {}
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
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

---@class CodeCompanion.AdapterArgs
return {
  name = "ollama",
  roles = {
    llm = "assistant",
    user = "user",
  },
  features = {
    text = true,
    tokens = true,
    vision = false,
  },
  url = "${url}/api/chat",
  env = {
    url = "http://localhost:11434",
  },
  handlers = {
    ---Set the parameters
    ---@param params table
    ---@param messages table
    ---@return table
    form_parameters = function(params, messages)
      return params
    end,

    ---Set the format of the role and content for the messages from the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param messages table Format is: { { role = "user", content = "Your prompt here" } }
    ---@return table
    form_messages = function(self, messages)
      messages = utils.merge_messages(messages)
      return { messages = messages }
    end,

    ---Returns the number of tokens generated from the LLM
    ---@param data table The data from the LLM
    ---@return number|nil
    tokens = function(data)
      if data then
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if not ok then
          return
        end

        if json.eval_count then
          log:debug("Done! %s", json.eval_count)
          return json.eval_count
        end
      end
    end,

    ---Output the data from the API ready for insertion into the chat buffer
    ---@param data table The streamed JSON data from the API, also formatted by the format_data callback
    ---@return table|nil
    chat_output = function(data)
      local output = {}

      if data and data ~= "" then
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if not ok then
          return {
            status = "error",
            output = string.format("Error malformed json: %s", json),
          }
        end

        local message = json.message

        if message.content then
          output.content = message.content
          output.role = message.role or nil
        end

        -- log:trace("----- For Adapter test creation -----\nOutput: %s\n ---------- // END ----------", output)

        return {
          status = "success",
          output = output,
        }
      end

      return nil
    end,

    ---Function to call when the stream ends and there is standard output
    ---Ollama will return a code 0 if no model is found which we need
    ---to handle and then alert the user to.
    ---@param data table
    ---@return nil
    on_stdout = function(data)
      local ok, json = pcall(vim.json.decode, data._stdout_results[1], { luanil = { object = true } })
      if ok then
        log:trace("stdout: %s", json)
        if json.error then
          log:error("Error: %s", json.error)
        end
      end
    end,

    ---Output the data from the API ready for inlining into the current buffer
    ---@param data table The streamed JSON data from the API, also formatted by the format_data handler
    ---@param context table Useful context about the buffer to inline to
    ---@return table|nil
    inline_output = function(data, context)
      if data and data ~= "" then
        local ok, json = pcall(vim.json.decode, data, { luanil = { object = true } })

        if not ok then
          log:error("Error malformed json: %s", json)
          return
        end

        return json.message.content
      end
    end,
  },
  schema = {
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use.",
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
  },
}
