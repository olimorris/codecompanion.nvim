local Curl = require("plenary.curl")

local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local model_transformers = require("codecompanion.adapters.utils.models.transform")
local token = require("codecompanion.adapters.http.copilot.token")

local CONSTANTS = {
  TIMEOUT = 3000, -- 3 seconds
  POLL_INTERVAL = 10,
}

local M = {}

---@class CopilotModels
---@field formatted_name string
---@field vendor string
---@field opts { can_stream: boolean, can_use_tools: boolean, has_vision: boolean }

-- Cache / state
local _cached_models
local _cached_adapter
local _cache_expires
local _fetch_in_progress = false

---Reset the cache
---@return nil
function M.reset_cache()
  _cached_adapter = nil
end

---Refresh the cache expiry timestamp
---@param seconds number|nil Number of seconds until the cache expires. Default: 1800
---@return number
local function set_cache_expiry(seconds)
  seconds = seconds or 1800
  _cache_expires = os.time() + seconds
  return _cache_expires
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
---@param opts? { token: table, force: boolean } Whether to force token initialization if not available
---@return boolean
local function fetch_async(adapter, opts)
  _cached_models = get_cached_models()
  if _cached_models then
    return true
  end
  if _fetch_in_progress then
    return true
  end
  _fetch_in_progress = true

  opts = opts or {}

  if not _cached_adapter then
    _cached_adapter = adapter
  end

  local fresh_token = opts.token or token.fetch({ force = opts.force })

  if not fresh_token or not fresh_token.copilot_token then
    log:trace("Copilot Adapter: No copilot token available, skipping async models fetch")
    _fetch_in_progress = false
    return false
  end

  local base_url = (fresh_token.endpoints and fresh_token.endpoints.api) or "https://api.githubcopilot.com"
  local url = base_url .. "/models"

  local headers = vim.deepcopy(_cached_adapter.headers or {})
  headers["Authorization"] = "Bearer " .. fresh_token.copilot_token
  headers["X-Github-Api-Version"] = "2025-10-01"

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
          local id, entry = model_transformers.from_copilot(model)
          if id then
            models[id] = entry
          else
            log:debug("Copilot Adapter: Skipping model '%s'", model.id)
          end
        end

        _cached_models = models
        set_cache_expiry(config.adapters.http.opts.cache_models_for)
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
---@param opts { token: table, async: boolean }
---@return CopilotModels|nil
local function fetch(adapter, opts)
  local _ = fetch_async(adapter, { token = opts.token, force = true })

  -- Block until models are cached or timeout
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
---@param opts? { token: table, async: boolean }
---@return CopilotModels|nil
function M.choices(adapter, opts)
  opts = opts or {}
  opts.async = opts.async ~= false -- Default to true unless explicitly false

  if opts.async == false then
    return fetch(adapter, opts)
  end

  -- Non-blocking: start async fetching (if possible) and return whatever is cached
  -- Don't force token initialization for async requests
  fetch_async(adapter, { token = opts.token, force = false })
  return get_cached_models()
end

return M
