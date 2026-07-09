local Curl = require("plenary.curl")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local transform = require("codecompanion.adapters.utils.models.transform")
local utils = require("codecompanion.adapters.utils")

local CONSTANTS = {
  TIMEOUT = 3000,
  POLL_INTERVAL = 10,
}

---@alias CodeCompanion.Adapter.ModelFetcher.RequestOpts { async?: boolean }

---@class CodeCompanion.Adapter.ModelFetcher.Spec
---@field name string
---@field url string|fun(adapter: CodeCompanion.HTTPAdapter, request_opts?: CodeCompanion.Adapter.ModelFetcher.RequestOpts): string
---@field headers? fun(adapter: CodeCompanion.HTTPAdapter, request_opts?: CodeCompanion.Adapter.ModelFetcher.RequestOpts): table|nil

local M = {}

-- Per-adapter model cache, keyed by adapter name
local caches = {}

---Return the cache record for an adapter, creating it on first use
---@param spec CodeCompanion.Adapter.ModelFetcher.Spec
---@return { in_progress: boolean, transform: function, models?: table, expires?: number }
local function cache_for(spec)
  if not caches[spec.name] then
    local transformer = transform["from_" .. spec.name:lower()]
    assert(transformer, "No model transformer found for adapter: " .. spec.name)
    caches[spec.name] = { in_progress = false, transform = transformer }
  end
  return caches[spec.name]
end

---Return the cached models, or nil when the cache is empty or has expired
---@param cache table
---@return table<string, CodeCompanion.Adapter.ModelChoice>|nil
local function fresh(cache)
  if cache.models and cache.expires and cache.expires > os.time() then
    return cache.models
  end
end

---Parse the API response into model choices and cache them
---@param cache table
---@param json table
---@return nil
local function store(cache, json)
  local models = {}
  for _, model in ipairs(json.data) do
    local id, choice = cache.transform(model)
    if id then
      models[id] = choice
    end
  end

  cache.models = models
  cache.expires = utils.cache_expiry(config.adapters.http.opts.cache_models_for)
end

---Kick off a non-blocking request for the model list, unless one is already running
---@param spec CodeCompanion.Adapter.ModelFetcher.Spec
---@param adapter CodeCompanion.HTTPAdapter
---@param request_opts? CodeCompanion.Adapter.ModelFetcher.RequestOpts
---@return nil
local function request(spec, adapter, request_opts)
  local cache = cache_for(spec)
  if fresh(cache) or cache.in_progress then
    return
  end

  local headers = spec.headers and spec.headers(adapter, request_opts)
  if spec.headers and not headers then
    -- Not ready to fetch yet (e.g. no auth token available)
    return
  end

  cache.in_progress = true
  local url = type(spec.url) == "function" and spec.url(adapter, request_opts) or spec.url

  local ok, err = pcall(function()
    Curl.get(url, {
      headers = headers,
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
      callback = vim.schedule_wrap(function(response)
        cache.in_progress = false

        local decode_ok, json = pcall(vim.json.decode, response and response.body)
        if not decode_ok or type(json) ~= "table" or not json.data then
          log:error(
            "Error parsing the %s response from " .. url .. "\nError: %s",
            spec.name,
            response and response.body
          )
          return
        end

        store(cache, json)
      end),
    })
  end)

  if not ok then
    cache.in_progress = false
    log:error("Could not start async request for %s models: %s", spec.name, err)
  end
end

---Block until the model list is available, or the request times out
---@param spec CodeCompanion.Adapter.ModelFetcher.Spec
---@param adapter CodeCompanion.HTTPAdapter
---@param request_opts? CodeCompanion.Adapter.ModelFetcher.RequestOpts
---@return table<string, CodeCompanion.Adapter.ModelChoice>
local function wait(spec, adapter, request_opts)
  local cache = cache_for(spec)
  local models = fresh(cache)
  if models then
    return models
  end

  request(spec, adapter, request_opts)

  local ok = vim.wait(CONSTANTS.TIMEOUT, function()
    return fresh(cache) ~= nil
  end, CONSTANTS.POLL_INTERVAL)

  if not ok then
    log:error("Timeout waiting for %s models", spec.name)
    return {}
  end

  return cache.models
end

---Return an adapter's models
---@param spec CodeCompanion.Adapter.ModelFetcher.Spec
---@param adapter CodeCompanion.HTTPAdapter
---@param request_opts? CodeCompanion.Adapter.ModelFetcher.RequestOpts
---@return table<string, CodeCompanion.Adapter.ModelChoice>
function M.get(spec, adapter, request_opts)
  local cache = cache_for(spec)

  -- Blocking
  if request_opts and request_opts.async == false then
    return wait(spec, adapter, request_opts)
  end

  -- Async
  request(spec, adapter, request_opts)
  return fresh(cache) or {}
end

return M
