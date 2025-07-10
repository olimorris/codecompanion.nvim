local config = require("codecompanion.config")
local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.openai")
local utils = require("codecompanion.utils.adapters")

local _cached_adapter

---Get a list of available Ollama models
---@params self CodeCompanion.Adapter
---@params opts? table
---@return table
local function get_models(self, opts)
  -- Prevent the adapter from being resolved multiple times due to `get_models`
  -- having both `default` and `choices` functions
  if not _cached_adapter then
    local adapter = require("codecompanion.adapters").resolve(self)
    if not adapter then
      log:error("Could not resolve Ollama adapter in the `get_models` function")
      return {}
    end
    _cached_adapter = adapter
  end

  _cached_adapter:get_env_vars()
  local url = _cached_adapter.env_replaced.url

  local headers = {
    ["content-type"] = "application/json",
  }

  local auth_header = "Bearer "
  if _cached_adapter.env_replaced.authorization then
    auth_header = _cached_adapter.env_replaced.authorization .. " "
  end
  if _cached_adapter.env_replaced.api_key then
    headers["Authorization"] = auth_header .. _cached_adapter.env_replaced.api_key
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
    log:error("Could not get the Ollama models from " .. url .. "/v1/models.\nError: %s", response)
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

---@class Ollama.Adapter: CodeCompanion.Adapter
return {
  name = "ollama",
  formatted_name = "Ollama",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    stream = true,
    tools = true,
    vision = false,
    think = false,
    options = {
      -- https://github.com/ollama/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values
    },
  },
  features = {
    text = true,
    tokens = true,
  },
  url = "${url}/api/chat",
  env = {
    url = "http://localhost:11434",
  },
  handlers = {
    setup = function(self)
      local model = self.schema.model.default
      if type(model) == "function" then
        model = model(self)
      end
      local model_opts = self.schema.model.choices
      if type(model_opts) == "function" then
        model_opts = model_opts(self)
      end

      self.opts.vision = true

      if model_opts and model_opts[model] and model_opts[model].opts then
        self.opts = vim.tbl_deep_extend("force", self.opts, model_opts[model].opts)

        if not model_opts[model].opts.has_vision then
          self.opts.vision = false
        end
      end

      if self.opts then
        if self.opts.stream then
          self.stream = true
        end
        self.body = { think = self.opts.think }
        if not vim.tbl_isempty(self.opts.options) then
          self.options = self.opts.options
        end
      end

      return true
    end,
    tokens = function(self, data)
      if data and data ~= "" then
        local data_mod = utils.clean_streamed_data(data)
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

        if ok and json.prompt_eval_count ~= nil and json.eval_count ~= nil then
          local tokens = (json.prompt_eval_count or 0) + (json.eval_count or 0)
          log:trace("Tokens: %s", tokens)
          return tokens
        end
      end
    end,
    form_parameters = function(self, params, messages)
      return openai.handlers.form_parameters(self, params, messages)
    end,
    form_messages = function(self, messages)
      local model = self.schema.model.default
      if type(model) == "function" then
        model = model(self)
      end

      messages = vim
        .iter(messages)
        :map(function(m)
          if vim.startswith(model, "o1") and m.role == "system" then
            m.role = self.roles.user
          end

          -- Ensure tool_calls are clean
          if m.tool_calls then
            -- TODO: add tool_name?
            m.tool_calls = vim
              .iter(m.tool_calls)
              :map(function(tool_call)
                return {
                  id = tool_call.id,
                  ["function"] = tool_call["function"],
                  type = tool_call.type,
                }
              end)
              :totable()
          end

          -- Process any images
          if m.opts and m.opts.tag == "image" and m.opts.mimetype then
            if self.opts and self.opts.vision then
              m.images = m.images or {}
              table.insert(m.images, m.content)
            else
              -- Remove the message if vision is not supported
              return nil
            end
          end

          return {
            role = m.role,
            content = m.content,
            tool_calls = m.tool_calls,
            images = m.images,
          }
        end)
        :totable()

      return { messages = messages }
    end,
    form_tools = function(self, tools)
      return openai.handlers.form_tools(self, tools)
    end,
    chat_output = function(self, data, tools)
      if not data or data == "" then
        return nil
      end

      -- Handle both streamed data and structured response
      local data_mod = type(data) == "table" and data.body or utils.clean_streamed_data(data)
      local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

      if not ok or not json.message then
        return nil
      end

      -- Process tool calls from all choices
      if self.opts.tools and tools then
        local message = json.message

        if message and message.tool_calls and #message.tool_calls > 0 then
          for i, tool in ipairs(message.tool_calls) do
            local tool_index = tool.index and tonumber(tool.index) or i

            -- Some endpoints like Gemini do not set this (why?!)
            local id = tool.id
            if not id or id == "" then
              id = string.format("call_%s_%s", json.created, i)
            end

            if self.opts.stream then
              local found = false
              for _, existing_tool in ipairs(tools) do
                if existing_tool._index == tool_index then
                  -- no need to concat here because ollama streams the full args in one chunk.
                  found = true
                  break
                end
              end

              if not found then
                table.insert(tools, {
                  _index = tool_index,
                  id = id,
                  type = tool.type,
                  ["function"] = {
                    name = tool["function"]["name"],
                    arguments = tool["function"]["arguments"] or "",
                  },
                })
              end
            else
              table.insert(tools, {
                _index = i,
                id = id,
                type = tool.type,
                ["function"] = {
                  name = tool["function"]["name"],
                  arguments = tool["function"]["arguments"],
                },
              })
            end
          end
        end
      end

      local delta = json.message

      if not delta then
        return nil
      end

      return {
        status = "success",
        output = {
          role = delta.role,
          content = delta.content,
          reasoning = delta.thinking,
        },
      }
    end,
    tools = {
      format_tool_calls = function(self, tools)
        return openai.handlers.tools.format_tool_calls(self, tools)
      end,
      output_response = function(self, tool_call, output)
        return {
          role = self.roles.tool or "tool",
          tool_name = tool_call["function"]["name"],
          content = output,
          opts = { visible = false },
        }
      end,
    },
    inline_output = function(self, data, context)
      if self.opts.stream then
        return log:error("Inline output is not supported for non-streaming models")
      end

      if data and data ~= "" then
        local ok, json = pcall(vim.json.decode, data.body, { luanil = { object = true } })

        if not ok then
          log:error("Error decoding JSON: %s", data.body)
          return { status = "error", output = json }
        end

        local choice = json.message
        if choice.message.content then
          return { status = "success", output = choice.message.content }
        end
      end
    end,

    ---Form the reasoning output that is stored in the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param data table The reasoning output from the LLM
    ---@return nil|{ content: string, _data: table }
    form_reasoning = function(self, data)
      -- taken from anthropic adapter
      local content = vim
        .iter(data)
        :filter(function(content)
          return content ~= nil
        end)
        :join("")

      return {
        content = content,
      }
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
      desc = "ID of the model to use.",
      default = function(self)
        return get_models(self, { last = true })
      end,
      choices = function(self)
        return get_models(self)
      end,
    },
    ---@type CodeCompanion.Schema
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
    ---@type CodeCompanion.Schema
    num_ctx = {
      order = 3,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = 4096,
      desc = "The maximum number of tokens that the language model can consider at once. This determines the size of the input context window, allowing the model to take into account longer text passages for generating responses. Adjusting this value can affect the model's performance and memory usage.",
      validate = function(n)
        return n > 0, "Must be a positive number"
      end,
    },
    ---@type CodeCompanion.Schema
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
    ---@type CodeCompanion.Schema
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
    ---@type CodeCompanion.Schema
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
    ---@type CodeCompanion.Schema
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
    ---@type CodeCompanion.Schema
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
    ---@type CodeCompanion.Schema
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
    ---@type CodeCompanion.Schema
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
    ---@type CodeCompanion.Schema
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
    ---@type CodeCompanion.Schema
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
    ---@type CodeCompanion.Schema
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
