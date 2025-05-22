local Job = require("plenary.job")
local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.openai")
local utils = require("codecompanion.utils.adapters")

---@alias GhToken string|nil
local _gh_token

local function get_github_token()
  local token
  local job = Job:new({
    command = "gh",
    args = { "auth", "token", "-h", "github.com" },
    on_exit = function(j, return_val)
      if return_val == 0 then
        token = j:result()[1]
      end
    end,
  })

  job:sync()
  return token
end

---Authorize the GitHub OAuth token
---@return GhToken
local function authorize_token()
  if _gh_token then
    log:debug("Reusing gh cli token")
    return _gh_token
  end

  log:debug("Getting gh cli token")

  _gh_token = get_github_token()

  return _gh_token
end

---@class GitHubModels.Adapter: CodeCompanion.Adapter
return {
  name = "githubmodels",
  formatted_name = "GitHub Models",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    stream = true,
    vision = false,
  },
  features = {
    text = true,
    tokens = true,
  },
  url = "https://models.inference.ai.azure.com/chat/completions",
  env = {
    ---@return string|nil
    api_key = function()
      return authorize_token()
    end,
  },
  headers = {
    Authorization = "Bearer ${api_key}",
    ["Content-Type"] = "application/json",
    -- Idea below taken from : https://github.com/github/gh-models/blob/d3b8d3e1d4c5a412e9af09a43a42eb365dac5751/internal/azuremodels/azure_client.go#L69
    -- Azure would like us to send specific user agents to help distinguish
    -- traffic from known sources and other web requests
    -- send both to accommodate various Azure consumers
    ["x-ms-useragent"] = "Neovim/" .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
    ["x-ms-user-agent"] = "Neovim/" .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
  },
  handlers = {
    ---Check for a token before starting the request
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
      end

      _gh_token = authorize_token()
      if not _gh_token then
        log:error("GitHub Models Adapter: Could not authorize your GitHub token")
        return false
      end

      return true
    end,

    --- Use the OpenAI adapter for the bulk of the work
    form_parameters = function(self, params, messages)
      return openai.handlers.form_parameters(self, params, messages)
    end,
    form_messages = function(self, messages)
      return openai.handlers.form_messages(self, messages)
    end,
    tokens = function(self, data)
      if data and data ~= "" then
        local data_mod = utils.clean_streamed_data(data)
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
    chat_output = function(self, data)
      return openai.handlers.chat_output(self, data)
    end,
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
      default = "gpt-4o",
      choices = {
        ["o3-mini"] = { opts = { can_reason = true } },
        ["o1"] = { opts = { can_reason = true } },
        ["o1-mini"] = { opts = { can_reason = true } },
        "claude-3.5-sonnet",
        "gpt-4o",
        "gpt-4o-mini",
        "DeepSeek-R1",
        "Codestral-2501",
      },
    },
    ---@type CodeCompanion.Schema
    reasoning_effort = {
      order = 2,
      mapping = "parameters",
      type = "string",
      optional = true,
      condition = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model()
        end
        if self.schema.model.choices[model] and self.schema.model.choices[model].opts then
          return self.schema.model.choices[model].opts.can_reason
        end
        return false
      end,
      default = "medium",
      desc = "Constrains effort on reasoning for reasoning models. Reducing reasoning effort can result in faster responses and fewer tokens used on reasoning in a response.",
      choices = {
        "high",
        "medium",
        "low",
      },
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 3,
      mapping = "parameters",
      type = "number",
      default = 0,
      condition = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model()
        end
        return not vim.startswith(model, "o1")
      end,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
    },
    ---@type CodeCompanion.Schema
    max_tokens = {
      order = 4,
      mapping = "parameters",
      type = "integer",
      default = 4096,
      desc = "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
    },
    ---@type CodeCompanion.Schema
    top_p = {
      order = 5,
      mapping = "parameters",
      type = "number",
      default = 1,
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
