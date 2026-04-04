local Curl = require("plenary.curl")
local adapter_utils = require("codecompanion.utils.adapters")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local CONSTANTS = {
  TIMEOUT = 3000, -- 3 seconds
}

---@type table<string, boolean>
local _running = {}

local M = {}

---@type table<string, table<string, { formatted_name: string?, meta: { context_window: number }?, opts: {can_reason: boolean, has_vision: boolean, can_use_tools: boolean} }>>
local _cached_models = {}

---@alias OllamaGetModelsOpts {last?: boolean, async?: boolean}

---@param url string
---@param opts? OllamaGetModelsOpts
---@return table|string|nil
local function get_cached_models(url, opts)
  local models = _cached_models[url]
  if not models or vim.tbl_isempty(models) then
    return opts and opts.last and "" or {}
  end
  if opts and opts.last then
    return vim.tbl_keys(models)[1]
  end
  return models
end

---Build auth headers from adapter env vars
---@param adapter CodeCompanion.HTTPAdapter
---@return table
local function build_headers(adapter)
  local headers = adapter_utils.set_env_vars(adapter, adapter.headers) or {}

  if adapter.env_replaced.api_key then
    local prefix = adapter.env_replaced.authorization or "Bearer"
    headers["Authorization"] = prefix .. " " .. adapter.env_replaced.api_key
  end

  return headers
end

---Parse capabilities and metadata from a model info response
---@param output table The curl response
---@return { can_reason: boolean, can_use_tools: boolean, has_vision: boolean }, { context_window: number }?
local function parse_model_info(output)
  local opts = {}
  if output.status ~= 200 then
    return opts
  end

  local ok, json = pcall(vim.json.decode, output.body, { array = true, object = true })
  if not ok then
    return opts
  end

  local capabilities = json.capabilities or {}
  opts.can_reason = vim.list_contains(capabilities, "thinking")
  opts.can_use_tools = vim.list_contains(capabilities, "tools")
  opts.has_vision = vim.list_contains(capabilities, "vision")

  local meta
  if json.model_info and json.details and json.details.family then
    local context_length = json.model_info[json.details.family .. ".context_length"]
    if context_length then
      meta = { context_window = context_length }
    end
  end

  return opts, meta
end

---Fetch model list and model info.
---Aborts if there's another fetch job running for this URL.
---@param adapter CodeCompanion.HTTPAdapter Ollama adapter with env var replaced.
local function fetch_models(adapter)
  assert(adapter ~= nil)
  local url = adapter.env_replaced.url

  if _running[url] then
    return
  end
  _running[url] = true
  _cached_models[url] = _cached_models[url] or {}

  local headers = build_headers(adapter)

  pcall(function()
    Curl.get(url .. "/api/tags", {
      headers = headers,
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
      timeout = CONSTANTS.TIMEOUT,
      callback = function(response)
        if response.status ~= 200 then
          _running[url] = false
          return log:error("Could not get the Ollama models from " .. url .. "/api/tags.\nError: %s", response)
        end

        local ok, json = pcall(vim.json.decode, response.body)
        if not ok then
          _running[url] = false
          return log:error("Could not parse the response from " .. url .. "/api/tags")
        end

        local pending = {}

        for _, model_obj in ipairs(json.models) do
          pending[model_obj.name] = Curl.post(url .. "/api/show", {
            body = vim.json.encode({ model = model_obj.name }),
            headers = headers,
            insecure = config.adapters.http.opts.allow_insecure,
            proxy = config.adapters.http.opts.proxy,
            timeout = CONSTANTS.TIMEOUT,
            callback = function(output)
              local opts, meta = parse_model_info(output)
              _cached_models[url][model_obj.name] = {
                formatted_name = model_obj.name,
                meta = meta,
                opts = opts,
              }
              pending[model_obj.name] = nil
              if vim.tbl_isempty(pending) then
                _running[url] = false
              end
            end,
          })
        end
      end,
    })
    if adapter.opts.cache_adapter == false then
      vim.wait(CONSTANTS.TIMEOUT, function()
        return not _running[url]
      end)
    end
  end)
end

---Get a list of available Ollama models
---@param self CodeCompanion.HTTPAdapter.Ollama|CodeCompanion.HTTPAdapter
---@param opts? OllamaGetModelsOpts
---@return table
function M.choices(self, opts)
  local adapter = require("codecompanion.adapters.http").resolve(self) --[[@as CodeCompanion.HTTPAdapter]]
  opts = vim.tbl_deep_extend("force", { async = true }, opts or {})
  if not adapter then
    log:error("Could not resolve Ollama adapter in the `choices` function")
    return {}
  end
  adapter_utils.get_env_vars(adapter, { timeout = config.adapters.opts.cmd_timeout })
  local url = adapter.env_replaced.url
  local is_uninitialised = _cached_models[url] == nil
  local should_block = (adapter.opts.cache_adapter == false) or is_uninitialised or not opts.async

  fetch_models(adapter)

  if should_block and _running[url] then
    vim.wait(CONSTANTS.TIMEOUT, function()
      return not _running[url]
    end)
  end
  return get_cached_models(url, opts)
end

---Return `true` if the model of the adapter supports thinking.
---@param self CodeCompanion.HTTPAdapter.Ollama
---@param model? string|function
---@return boolean
function M.check_thinking_capability(self, model)
  model = model or self.schema.model.default
  if type(model) == "function" then
    model = model(self)
  end
  local choices = self.schema.model.choices
  if type(choices) == "function" then
    choices = choices(self)
  end
  if choices and choices[model] and choices[model].opts and choices[model].opts.can_reason then
    return true
  end
  return false
end

return M
