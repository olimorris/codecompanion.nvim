local config = require("codecompanion.config")
local curl = require("plenary.curl")
local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.openai")
local utils = require("codecompanion.utils.adapters")

-- Reference: https://github.com/yetone/avante.nvim/blob/22418bff8bcac4377ebf975cd48f716823867979/lua/avante/providers/copilot.lua#L5-L26
---
---@class CopilotToken
---@field annotations_enabled boolean
---@field chat_enabled boolean
---@field chat_jetbrains_enabled boolean
---@field code_quote_enabled boolean
---@field codesearch boolean
---@field copilotignore_enabled boolean
---@field endpoints {api: string, ["origin-tracker"]: string, proxy: string, telemetry: string}
---@field expires_at integer
---@field individual boolean
---@field nes_enabled boolean
---@field prompt_8k boolean
---@field public_suggestions string
---@field refresh_in integer
---@field sku string
---@field snippy_load_test_enabled boolean
---@field telemetry string
---@field token string
---@field tracking_id string
---@field vsc_electron_fetcher boolean
---@field xcode boolean
---@field xcode_chat boolean

local _cached_adapter
local _cache_expires
local _cache_file = vim.fn.tempname()
local _cached_models

---@alias CopilotOAuthToken string|nil
local _oauth_token

---@type CopilotToken|nil
local _github_token

---Finds the configuration path
---@return string|nil
local function find_config_path()
  if os.getenv("CODECOMPANION_TOKEN_PATH") then
    return os.getenv("CODECOMPANION_TOKEN_PATH")
  end

  local path = vim.fs.normalize("$XDG_CONFIG_HOME")

  if path and vim.fn.isdirectory(path) > 0 then
    return path
  elseif vim.fn.has("win32") > 0 then
    path = vim.fs.normalize("~/AppData/Local")
    if vim.fn.isdirectory(path) > 0 then
      return path
    end
  else
    path = vim.fs.normalize("~/.config")
    if vim.fn.isdirectory(path) > 0 then
      return path
    end
  end
end

---The function first attempts to load the token from the environment variables,
---specifically for GitHub Codespaces. If not found, it then attempts to load
---the token from configuration files located in the user's configuration path.
---@return CopilotOAuthToken
local function get_token()
  if _oauth_token then
    return _oauth_token
  end

  local token = os.getenv("GITHUB_TOKEN")
  local codespaces = os.getenv("CODESPACES")
  if token and codespaces then
    return token
  end

  local config_path = find_config_path()
  if not config_path then
    return nil
  end

  local file_paths = {
    config_path .. "/github-copilot/hosts.json",
    config_path .. "/github-copilot/apps.json",
  }

  for _, file_path in ipairs(file_paths) do
    if vim.uv.fs_stat(file_path) then
      local userdata = vim.fn.readfile(file_path)

      if vim.islist(userdata) then
        userdata = table.concat(userdata, " ")
      end

      local userdata = vim.json.decode(userdata)
      for key, value in pairs(userdata) do
        if string.find(key, "github.com") then
          return value.oauth_token
        end
      end
    end
  end

  return nil
end

---Authorize the GitHub OAuth token
---@return CopilotToken
local function authorize_token()
  if _github_token and _github_token.expires_at > os.time() then
    log:trace("Reusing GitHub Copilot token")
    return _github_token
  end

  log:debug("Authorizing GitHub Copilot token")

  local request = curl.get("https://api.github.com/copilot_internal/v2/token", {
    headers = {
      Authorization = "Bearer " .. _oauth_token,
      ["Accept"] = "application/json",
    },
    insecure = config.adapters.opts.allow_insecure,
    proxy = config.adapters.opts.proxy,
    on_error = function(err)
      log:error("Copilot Adapter: Token request error %s", err)
    end,
  })

  _github_token = vim.json.decode(request.body)
  return _github_token
end

---Get and authorize a GitHub Copilot token
---@param self CodeCompanion.Adapter
---@return boolean success
local function get_and_authorize_token(self)
  _oauth_token = get_token()
  if not _oauth_token then
    log:error("Copilot Adapter: No token found. Please refer to https://github.com/github/copilot.vim")
    return false
  end

  _github_token = authorize_token()
  if not _github_token or vim.tbl_isempty(_github_token) then
    log:error("Copilot Adapter: Could not authorize your GitHub Copilot token")
    return false
  end
  self.url = _github_token.endpoints.api .. "/chat/completions"

  return true
end

---Reset the cached adapter
---@return nil
local function reset()
  _cached_adapter = nil
end

---Get a list of available Copilot models
---@param self CodeCompanion.Adapter
---@param opts? table
---@return table
local function get_models(self, opts)
  if _cached_models and _cache_expires and _cache_expires > os.time() then
    return _cached_models
  end

  if not _cached_adapter then
    if not self then
      return {}
    end
    _cached_adapter = self
  end

  get_and_authorize_token(self)
  local url = _github_token.endpoints.api or "https://api.githubcopilot.com"
  local headers = vim.deepcopy(_cached_adapter.headers)
  headers["Authorization"] = "Bearer " .. _github_token.token

  local ok, response = pcall(function()
    return curl.get(url .. "/models", {
      sync = true,
      headers = headers,
      insecure = config.adapters.opts.allow_insecure,
      proxy = config.adapters.opts.proxy,
    })
  end)
  if not ok then
    log:error("Could not get the Copilot models from " .. url .. "/models.\nError: %s", response)
    return {}
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Error parsing the response from " .. url .. "/models.\nError: %s", response.body)
    return {}
  end

  local models = {}
  for _, model in ipairs(json.data) do
    if model.model_picker_enabled and model.capabilities.type == "chat" then
      local choice_opts = {}

      if model.capabilities.supports.streaming then
        choice_opts.can_stream = true
      end
      if model.capabilities.supports.tool_calls then
        choice_opts.can_use_tools = true
      end
      if model.capabilities.supports.vision then
        choice_opts.has_vision = true
      end

      models[model.id] = { opts = choice_opts }
    end
  end

  _cached_models = models
  _cache_expires = utils.refresh_cache(_cache_file, config.adapters.opts.cache_models_for)

  return models
end

---Get Copilot usage statistics
---@return table|nil
local function get_copilot_stats()
  local dummy_adapter = { url = "" }
  if not get_and_authorize_token(dummy_adapter) then
    return nil
  end

  log:debug("Fetching Copilot usage statistics")

  local ok, response = pcall(function()
    return curl.get("https://api.github.com/copilot_internal/user", {
      sync = true,
      headers = {
        Authorization = "Bearer " .. _oauth_token,
        Accept = "*/*",
        ["User-Agent"] = "CodeCompanion.nvim",
      },
      insecure = config.adapters.opts.allow_insecure,
      proxy = config.adapters.opts.proxy,
    })
  end)
  if not ok then
    log:error("Could not get Copilot stats: %s", response)
    return nil
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Error parsing Copilot stats response: %s", response.body)
    return nil
  end

  return json
end

---Show Copilot usage statistics in a floating window
---@return nil
local function show_copilot_stats()
  local stats = get_copilot_stats()
  if not stats then
    return vim.notify("Could not retrieve Copilot stats", vim.log.levels.ERROR)
  end

  local lines = {}
  local ui = require("codecompanion.utils.ui")
  table.insert(lines, "# 󰾞  GitHub Copilot Usage Statistics 󰾞 ")
  table.insert(lines, "")

  if stats.quota_snapshots.premium_interactions then
    local premium = stats.quota_snapshots.premium_interactions
    table.insert(lines, "##  Premium Interactions")
    local used = premium.entitlement - premium.remaining
    local usage_percent = premium.entitlement > 0 and (used / premium.entitlement * 100) or 0
    table.insert(lines, string.format("   - Used: %d / %d (%.1f%%)", used, premium.entitlement, usage_percent))
    table.insert(lines, string.format("   - Remaining: %d", premium.remaining))
    table.insert(lines, string.format("   - Percentage: %.1f%%", premium.percent_remaining))
    if premium.unlimited then
      table.insert(lines, "   - Status: Unlimited ✨")
    else
      table.insert(lines, "   - Status: Limited")
    end
    table.insert(lines, "")
  end

  if stats.quota_snapshots.chat then
    local chat = stats.quota_snapshots.chat
    table.insert(lines, "## 󰭹 Chat")
    if chat.unlimited then
      table.insert(lines, "   - Status: Unlimited ✨")
    else
      local used = chat.entitlement - chat.remaining
      local usage_percent = chat.entitlement > 0 and (used / chat.entitlement * 100) or 0
      table.insert(lines, string.format("   - Used: %d / %d (%.1f%%)", used, chat.entitlement, usage_percent))
    end
    table.insert(lines, "")
  end

  if stats.quota_snapshots.completions then
    local completions = stats.quota_snapshots.completions
    table.insert(lines, "##  Completions")
    if completions.unlimited then
      table.insert(lines, "   - Status: Unlimited ✨")
    else
      local used = completions.entitlement - completions.remaining
      local usage_percent = completions.entitlement > 0 and (used / completions.entitlement * 100) or 0
      table.insert(lines, string.format("   - Used: %d / %d (%.1f%%)", used, completions.entitlement, usage_percent))
    end
  end
  if stats.quota_reset_date then
    table.insert(lines, "")
    table.insert(lines, string.format("> Quota resets on: %s", stats.quota_reset_date))
    table.insert(lines, "")
  end

  -- Create floating window
  local float_opts = {
    title = "󰍘 Copilot Stats",
    lock = true,
    relative = "editor",
    row = "center",
    col = "center",
    window = {
      width = 43,
      height = math.min(#lines + 2, 20),
    },
    ignore_keymaps = false,
  }
  local _, winnr = ui.create_float(lines, float_opts)

  local function get_usage_highlight(usage_percent)
    if usage_percent >= 80 then
      return "Error"
    else
      return "MoreMsg"
    end
  end
  vim.api.nvim_win_call(winnr, function()
    -- Usage percentages with color coding
    local premium = stats.quota_snapshots.premium_interactions
    if premium and not premium.unlimited then
      local used = premium.entitlement - premium.remaining
      local usage_percent = premium.entitlement > 0 and (used / premium.entitlement * 100) or 0
      local highlight = get_usage_highlight(usage_percent)
      vim.fn.matchadd(highlight, string.format("   - Used: %d / %d (%.1f%%)", used, premium.entitlement, usage_percent))
    end
  end)
end

---@class Copilot.Adapter: CodeCompanion.Adapter
return {
  name = "copilot",
  formatted_name = "Copilot",
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
  url = "https://api.githubcopilot.com/chat/completions",
  env = {
    ---@return string|nil
    api_key = function()
      return authorize_token().token
    end,
  },
  headers = {
    Authorization = "Bearer ${api_key}",
    ["Content-Type"] = "application/json",
    ["Copilot-Integration-Id"] = "vscode-chat",
    ["Editor-Version"] = "Neovim/" .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
  },
  get_copilot_stats = function()
    return get_copilot_stats()
  end,
  show_copilot_stats = function()
    return show_copilot_stats()
  end,
  handlers = {
    ---Check for a token before starting the request
    ---@param self CodeCompanion.Adapter
    ---@return boolean
    setup = function(self)
      local model = self.schema.model.default
      local choices = self.schema.model.choices
      if type(model) == "function" then
        model = model(self)
      end
      if type(choices) == "function" then
        choices = choices(self)
      end
      local model_opts = choices[model]

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

      return get_and_authorize_token(self)
    end,

    --- Use the OpenAI adapter for the bulk of the work
    form_parameters = function(self, params, messages)
      return openai.handlers.form_parameters(self, params, messages)
    end,
    form_messages = function(self, messages)
      -- Ensure we send over the correct headers for image requests
      for _, m in ipairs(messages) do
        if m.opts and m.opts.tag == "image" and m.opts.mimetype then
          self.headers["Copilot-Vision-Request"] = "true"
          break
        end
      end
      return openai.handlers.form_messages(self, messages)
    end,
    form_tools = function(self, tools)
      return openai.handlers.form_tools(self, tools)
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
    chat_output = function(self, data, tools)
      return openai.handlers.chat_output(self, data, tools)
    end,
    tools = {
      format_tool_calls = function(self, tools)
        return openai.handlers.tools.format_tool_calls(self, tools)
      end,
      output_response = function(self, tool_call, output)
        return openai.handlers.tools.output_response(self, tool_call, output)
      end,
    },
    inline_output = function(self, data, context)
      return openai.handlers.inline_output(self, data, context)
    end,
    on_exit = function(self, data)
      reset()
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
      default = "gpt-4.1",
      choices = function(self)
        return get_models(self)
      end,
    },
    ---@type CodeCompanion.Schema
    temperature = {
      order = 3,
      mapping = "parameters",
      type = "number",
      default = 0.1,
      condition = function(self)
        local model = self.schema.model.default
        if type(model) == "function" then
          model = model()
        end
        return not vim.startswith(model, "o1")
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
