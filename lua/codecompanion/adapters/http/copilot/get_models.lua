local Curl = require("plenary.curl")

local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local token = require("codecompanion.adapters.http.copilot.token")

local CONSTANTS = {
  TIMEOUT = 3000, -- 3 seconds
  POLL_INTERVAL = 10,
}

local M = {}

---@class CopilotModels
---@field formatted_name string
---@field vendor string
---@field opts {can_stream: boolean, can_use_tools: boolean, has_vision: boolean}

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
---@param provided_token? table
---@return boolean
local function fetch_async(adapter, provided_token)
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

  local fresh_token = provided_token or token.fetch()

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
          -- Copilot models can use the "completions" or "responses" endpoint
          local internal_endpoint = "completions"
          if model.supported_endpoints then
            for _, endpoint in ipairs(model.supported_endpoints) do
              if endpoint == "/responses" then
                internal_endpoint = "responses"
                break
              elseif endpoint ~= "/chat/completions" then
                log:debug("Copilot Adapter: Skipping unsupported endpoint '%s' for model '%s'", endpoint, model.id)
                goto continue
              end
            end
          end

          if model.model_picker_enabled then
            local choice_opts = {}
            local limits = {}
            local billing = {}

            if model.capabilities then
              if type(model.capabilities.type) == "string" and model.capabilities.type ~= "chat" then
                log:debug("Copilot Adapter: Skipping non-chat model '%s'", model.id)
                goto continue
              end
              if type(model.capabilities.type) == "table" and not vim.tbl_contains(model.capabilities.type, "chat") then
                log:debug("Copilot Adapter: Skipping non-chat model '%s'", model.id)
                goto continue
              end
              if model.capabilities.supports and model.capabilities.supports.streaming then
                choice_opts.can_stream = true
              end
              if model.capabilities.supports and model.capabilities.supports.tool_calls then
                choice_opts.can_use_tools = true
              end
              if model.capabilities.supports and model.capabilities.supports.vision then
                choice_opts.has_vision = true
              end
              if model.capabilities.limits then
                limits.max_output_tokens = model.capabilities.limits.max_output_tokens
                limits.max_prompt_tokens = model.capabilities.limits.max_prompt_tokens
              end
            end

            if model.billing then
              billing.is_premium = model.billing.is_premium
              billing.multiplier = model.billing.multiplier
            end

            local description = model.name .. (billing.multiplier and (" (" .. billing.multiplier .. "x)") or "")

            models[model.id] = {
              billing = billing,
              description = description,
              endpoint = internal_endpoint,
              formatted_name = model.name,
              limits = limits,
              opts = choice_opts,
              vendor = model.vendor,
            }
          end

          ::continue::
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
---@param provided_token? table
---@return CopilotModels|nil
local function fetch(adapter, provided_token)
  local _ = fetch_async(adapter, provided_token)

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
---@param provided_token? table
---@return CopilotModels|nil
function M.choices(adapter, opts, provided_token)
  opts = opts or { async = true }
  if not opts.async or opts.async == false then
    return fetch(adapter, provided_token)
  end

  -- Non-blocking: start async fetching (if possible) and return whatever is cached
  fetch_async(adapter, provided_token)
  return get_cached_models()
end

return M
