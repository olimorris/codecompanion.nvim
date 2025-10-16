local adapter_utils = require("codecompanion.utils.adapters")
local get_models = require("codecompanion.adapters.http.copilot.get_models")
local log = require("codecompanion.utils.log")
local stats = require("codecompanion.adapters.http.copilot.stats")
local token = require("codecompanion.adapters.http.copilot.token")

local _fetching_models = false
local version = vim.version()

---Resolves the options that a model has
---@param adapter CodeCompanion.HTTPAdapter
---@return table
local function resolve_model_opts(adapter)
  local model = adapter.schema.model.default
  local choices = adapter.schema.model.choices
  if type(model) == "function" then
    model = model(adapter)
  end
  if type(choices) == "function" then
    choices = choices(adapter, { async = false })
  end
  return choices[model]
end

---Return the handlers of a specific adapter, ensuring the correct endpoint is set
---@param adapter CodeCompanion.HTTPAdapter
---@return table
local function handlers(adapter)
  local model_opts = resolve_model_opts(adapter)
  if model_opts.endpoint == "responses" then
    adapter.url = "https://api.githubcopilot.com/responses"
    return require("codecompanion.adapters.http.openai_responses").handlers
  end
  adapter.url = "https://api.githubcopilot.com/chat/completions"
  return require("codecompanion.adapters.http.openai").handlers
end

---@class CodeCompanion.HTTPAdapter.Copilot: CodeCompanion.HTTPAdapter
return {
  name = "copilot",
  formatted_name = "Copilot",
  roles = {
    llm = "assistant",
    tool = "tool",
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
  url = "https://api.githubcopilot.com/chat/completions",
  env = {
    ---@return string
    api_key = function()
      return token.fetch().copilot_token
    end,
  },
  headers = {
    Authorization = "Bearer ${api_key}",
    ["Content-Type"] = "application/json",
    ["Copilot-Integration-Id"] = "vscode-chat",
    ["Editor-Version"] = "Neovim/" .. version.major .. "." .. version.minor .. "." .. version.patch,
  },
  show_copilot_stats = function()
    return stats.show()
  end,
  handlers = {
    ---Initiate fetching the models in the background as soon as the adapter is resolved
    ---@param self CodeCompanion.HTTPAdapter
    ---@return nil
    resolve = function(self)
      if _fetching_models then
        return
      end
      _fetching_models = true

      vim.schedule(function()
        pcall(function()
          get_models.choices(self, { async = true })
        end)
        _fetching_models = false
      end)
    end,

    ---Check for a token before starting the request
    ---@param self CodeCompanion.HTTPAdapter
    ---@return boolean
    setup = function(self)
      local model_opts = resolve_model_opts(self)

      if (self.opts and self.opts.stream) and (model_opts and model_opts.opts and model_opts.opts.can_stream) then
        self.parameters.stream = true
      else
        self.parameters.stream = nil
      end
      if (self.opts and self.opts.tools) and (model_opts and model_opts.opts and not model_opts.opts.can_use_tools) then
        self.opts.tools = false
      end
      if (self.opts and self.opts.vision) and (model_opts and model_opts.opts and not model_opts.opts.has_vision) then
        self.opts.vision = false
      end

      return token.init(self)
    end,

    --- Use the OpenAI adapter for the bulk of the work
    form_parameters = function(self, params, messages)
      return handlers(self).form_parameters(self, params, messages)
    end,
    form_messages = function(self, messages)
      for _, m in ipairs(messages) do
        if m.opts and m.opts.tag == "image" and m.opts.mimetype then
          self.headers["X-Initiator"] = "user"
          self.headers["Copilot-Vision-Request"] = "true"
          break
        end
      end

      local last_msg = messages[#messages]
      if last_msg and last_msg.role == self.roles.tool then
        -- NOTE: The inclusion of this header reduces premium token usage when
        -- sending tool output back to the LLM (#1717)
        self.headers["X-Initiator"] = "agent"
      end

      return handlers(self).form_messages(self, messages)
    end,
    form_tools = function(self, tools)
      return handlers(self).form_tools(self, tools)
    end,
    tokens = function(self, data)
      if data and data ~= "" then
        local data_mod = adapter_utils.clean_streamed_data(data)
        local ok, json = pcall(vim.json.decode, data_mod, { luanil = { object = true } })

        if ok then
          if json.usage then
            local total_tokens = json.usage.total_tokens or 0
            local completion_tokens = json.usage.completion_tokens or 0
            local prompt_tokens = json.usage.prompt_tokens or 0
            local tokens = total_tokens > 0 and total_tokens or completion_tokens + prompt_tokens
            log:trace("Tokens: %s", tokens)
            return tokens
          end
        end
      end
    end,
    chat_output = function(self, data, tools)
      return handlers(self).chat_output(self, data, tools)
    end,
    tools = {
      format_tool_calls = function(self, tools)
        return handlers(self).tools.format_tool_calls(self, tools)
      end,
      output_response = function(self, tool_call, output)
        return handlers(self).tools.output_response(self, tool_call, output)
      end,
    },
    inline_output = function(self, data, context)
      return handlers(self).inline_output(self, data, context)
    end,
    on_exit = function(self, data)
      get_models.reset_cache()
      return handlers(self).on_exit(self, data)
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
      default = "gpt-4.1",
      ---@type fun(self: CodeCompanion.HTTPAdapter, opts?: table): table
      choices = function(self, opts)
        -- Ensure token is available before getting models
        local fetched = token.fetch()
        if not fetched or not fetched.copilot_token then
          return { ["gpt-4.1"] = { opts = {} } }
        end
        return get_models.choices(self, opts, fetched)
      end,
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 3,
      mapping = "parameters",
      type = "number",
      default = 0.1,
      ---@type fun(self: CodeCompanion.HTTPAdapter): boolean
      condition = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model()
        end
        return not vim.startswith(model, "o1") and not model:find("codex")
      end,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
    },
    max_tokens = {
      order = 4,
      mapping = "parameters",
      type = "integer",
      default = 16384,
      desc = "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
    },
    ---@type CodeCompanion.Schema
    top_p = {
      order = 5,
      mapping = "parameters",
      type = "number",
      default = 1,
      ---@type fun(self: CodeCompanion.HTTPAdapter): boolean
      condition = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model()
        end
        return not vim.startswith(model, "o1")
      end,
      desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
    },
    ---@type CodeCompanion.Schema
    n = {
      order = 6,
      mapping = "parameters",
      type = "number",
      default = 1,
      ---@type fun(self: CodeCompanion.HTTPAdapter): boolean
      condition = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model()
        end
        return not vim.startswith(model, "o1")
      end,
      desc = "How many chat completions to generate for each prompt.",
    },
  },
}
