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
    return curl.get(url .. "/api/tags", {
      sync = true,
      headers = headers,
      insecure = config.adapters.opts.allow_insecure,
      proxy = config.adapters.opts.proxy,
    })
  end)
  if not ok then
    log:error("Could not get the Ollama models from " .. url .. "/api/tags.\nError: %s", response)
    return {}
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Could not parse the response from " .. url .. "/api/tags")
    return {}
  end

  local models = {}
  local jobs = {}

  for _, model_obj in ipairs(json.models) do
    -- start async requests
    local job = curl.post(url .. "/api/show", {
      headers = headers,
      insecure = config.adapters.opts.allow_insecure,
      proxy = config.adapters.opts.proxy,
      body = vim.json.encode({ model = model_obj.name }),
      callback = function(output)
        models[model_obj.name] = { opts = {} }
        if output.status == 200 then
          local ok, model_info_json = pcall(vim.json.decode, output.body, { array = true, object = true })
          if ok then
            models[model_obj.name].opts.can_reason = vim.list_contains(model_info_json.capabilities or {}, "thinking")
            models[model_obj.name].opts.has_vision = vim.list_contains(model_info_json.capabilities or {}, "vision")
          end
        end
      end,
    })
    table.insert(jobs, job)
  end

  for _, job in ipairs(jobs) do
    -- wait for the requests to finish.
    job:wait()
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
    vision = true,
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

      self.parameters.stream = true
      if self.opts then
        if self.opts.stream == false then
          self.parameters.stream = false
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
            m.images = m.images or {}
            if self.opts and self.opts.vision then
              table.insert(m.images, m.content)
              m.content = nil
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

            local id = tool.id
            if not id or id == "" then
              id = string.format("call_%s_%s", json.created_at, i)
            end

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

        if json.message.content then
          return { status = "success", output = json.message.content }
        end
      end
    end,

    ---Form the reasoning output that is stored in the chat buffer
    ---@param self CodeCompanion.Adapter
    ---@param data table The reasoning output from the LLM
    ---@return nil|{ content: string, _data: table }
    form_reasoning = function(self, data)
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
    think = {
      order = 2,
      mapping = "parameters",
      type = "boolean",
      desc = "Whether to enable thinking mode.",
      default = false,
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 3,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = nil,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
      validate = function(n)
        return n >= 0 and n <= 2, "Must be between 0 and 2"
      end,
    },
    ---@type CodeCompanion.Schema
    num_ctx = {
      order = 4,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = nil,
      desc = "The maximum number of tokens that the language model can consider at once. This determines the size of the input context window, allowing the model to take into account longer text passages for generating responses. Adjusting this value can affect the model's performance and memory usage.",
      validate = function(n)
        return n > 0, "Must be a positive number"
      end,
    },
    ---@type CodeCompanion.Schema
    repeat_last_n = {
      order = 5,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = nil,
      desc = "Sets how far back for the model to look back to prevent repetition. (Default: 64, 0 = disabled, -1 = num_ctx)",
      validate = function(n)
        return n >= -1, "Must be -1 or greater"
      end,
    },
    ---@type CodeCompanion.Schema
    repeat_penalty = {
      order = 6,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = nil,
      desc = "Sets how strongly to penalize repetitions. A higher value (e.g., 1.5) will penalize repetitions more strongly, while a lower value (e.g., 0.9) will be more lenient. (Default: 1.1)",
      validate = function(n)
        return n >= 0, "Must be a non-negative number"
      end,
    },
    ---@type CodeCompanion.Schema
    seed = {
      order = 7,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = nil,
      desc = "Sets the random number seed to use for generation. Setting this to a specific number will make the model generate the same text for the same prompt. (Default: 0)",
      validate = function(n)
        return n >= 0, "Must be a non-negative number"
      end,
    },
    ---@type CodeCompanion.Schema
    stop = {
      order = 8,
      mapping = "parameters.options",
      type = "list",
      optional = true,
      default = nil,
      desc = "Sets the stop sequences to use. When this pattern is encountered the LLM will stop generating text and return. Multiple stop patterns may be set by specifying multiple separate stop parameters in a modelfile.",
      validate = function(s)
        return s == nil
          or (vim.islist(s) and vim.iter(s):all(function(item)
            return type(item) == "string"
          end))
      end,
    },
    ---@type CodeCompanion.Schema
    top_k = {
      order = 9,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = nil,
      desc = "Reduces the probability of generating nonsense. A higher value (e.g. 100) will give more diverse answers, while a lower value (e.g. 10) will be more conservative. (Default: 40)",
      validate = function(n)
        return n >= 0, "Must be a non-negative number"
      end,
    },
    ---@type CodeCompanion.Schema
    top_p = {
      order = 10,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = nil,
      desc = "Works together with top-k. A higher value (e.g., 0.95) will lead to more diverse text, while a lower value (e.g., 0.5) will generate more focused and conservative text. (Default: 0.9)",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    ---@type CodeCompanion.Schema
    min_p = {
      order = 11,
      mapping = "parameters.options",
      type = "number",
      optional = true,
      default = nil,
      desc = "Alternative to the top_p, and aims to ensure a balance of quality and variety. The parameter p represents the minimum probability for a token to be considered, relative to the probability of the most likely token. For example, with p=0.05 and the most likely token having a probability of 0.9, logits with a value less than 0.045 are filtered out.",
      validate = function(n)
        return n >= 0 and n <= 1, "Must be between 0 and 1"
      end,
    },
    ---@type CodeCompanion.Schema
    keep_alive = {
      order = 12,
      mapping = "parameters",
      type = "string",
      optional = true,
      default = nil,
      desc = "Controls how long the model will stay loaded into memory following the request (default: 5m)",
    },
  },
}
