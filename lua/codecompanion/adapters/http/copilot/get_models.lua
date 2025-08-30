local Curl = require("plenary.curl")

local adapters = require("codecompanion.utils.adapters")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local token = require("codecompanion.adapters.http.copilot.token")

local CONSTANTS = {
  TIMEOUT = 3000, -- 3 seconds
  POLL_INTERVAL = 10,
}

local M = {}

---@class CopilotModels
---@field nice_name string
---@field vendor string
---@field opts {can_stream: boolean, can_use_tools: boolean, has_vision: boolean}

-- Cache / state
local _cached_models
local _cached_adapter
local _cache_expires
local _cache_file = vim.fn.tempname()
local _fetch_in_progress = false

---Reset the cache
---@return nil
function M.reset_cache()
  _cached_adapter = nil
end

---Return cached models if the cache is still valid.
---@return CopilotModels|nil
local function get_cached_models()
  if _cached_models and _cache_expires and _cache_expires > os.time() then
    log:trace("Copilot Adapter: Using cached Copilot models")
    return _cached_models
  end

  return nil
end

---Asynchronously fetch the list of available Copilot
---@param adapter table
---@return boolean
local function fetch_async(adapter)
  _cached_models = get_cached_models()
  if _cached_models then
    return true
  end
  if _fetch_in_progress then
    return true
  end
  _fetch_in_progress = true

  if not _cached_adapter then
    _cached_adapter = adapter
  end

  local fresh_token = token.fetch()

  local base_url = (fresh_token.endpoints and fresh_token.endpoints.api) or "https://api.githubcopilot.com"
  local url = base_url .. "/models"
  local headers = vim.deepcopy(_cached_adapter.headers or {})
  headers["Authorization"] = "Bearer " .. fresh_token.copilot_token

  -- Async request via plenary.curl with a callback
  local ok, err = pcall(function()
    Curl.get(url, {
      headers = headers,
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
      callback = vim.schedule_wrap(function(response)
        _fetch_in_progress = false

        if not response or not response.body then
          log:error("Could not get the Copilot models from " .. url .. ". Empty response")
          return
        end

        local ok_json, json = pcall(vim.json.decode, response.body)
        if not ok_json or type(json) ~= "table" or not json.data then
          log:error("Error parsing the response from " .. url .. ".\nError: %s", response.body)
          return
        end

        local models = {}
        for _, model in ipairs(json.data) do
          if model.model_picker_enabled and model.capabilities and model.capabilities.type == "chat" then
            local choice_opts = {}

            if model.capabilities.supports and model.capabilities.supports.streaming then
              choice_opts.can_stream = true
            end
            if model.capabilities.supports and model.capabilities.supports.tool_calls then
              choice_opts.can_use_tools = true
            end
            if model.capabilities.supports and model.capabilities.supports.vision then
              choice_opts.has_vision = true
            end

            models[model.id] = { vendor = model.vendor, nice_name = model.name, opts = choice_opts }
          end
        end

        _cached_models = models
        _cache_expires = adapters.refresh_cache(_cache_file, config.adapters.http.opts.cache_models_for)
      end),
    })
  end)

  if not ok then
    _fetch_in_progress = false
    log:error("Could not start async request for Copilot models: %s", err)
    return false
  end

  return true
end

---Fetch the list of available Copilot models synchronously.
---@param adapter table
---@return CopilotModels|nil
local function fetch(adapter)
  local _ = fetch_async(adapter)

  -- Block until models are cached or timeout (milliseconds)
  local ok = vim.wait(CONSTANTS.TIMEOUT, function()
    return get_cached_models() ~= nil
  end, CONSTANTS.POLL_INTERVAL)

  if not ok then
    return log:error("Copilot Adapter: Timeout waiting for models")
  end

  return _cached_models
end

---Canonical interface used by adapter.schema.model.choices implementations.
---@param adapter table
---@param opts? { async: boolean }
---@return CopilotModels|nil
function M.choices(adapter, opts)
  opts = opts or { async = true }
  if not opts.async or opts.async == false then
    return fetch(adapter)
  end

  -- Non-blocking: start async fetching (if possible) and return whatever is cached
  fetch_async(adapter)
  return get_cached_models()
end

return M
