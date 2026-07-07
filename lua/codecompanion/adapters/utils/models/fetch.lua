local Curl = require("plenary.curl")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local transform = require("codecompanion.adapters.utils.models.transform")
local utils = require("codecompanion.adapters.utils")

local M = {}

---@class CodeCompanion.Adapter.ModelFetcher.Opts
---@field name string The adapter's name. Used in log messages and to find its `transform.from_<name>` function
---@field url string
---@field headers? fun(adapter: CodeCompanion.HTTPAdapter): table

---Synchronously fetch models from an endpoint
---@param opts CodeCompanion.Adapter.ModelFetcher.Opts
---@return fun(adapter: CodeCompanion.HTTPAdapter): table<string, CodeCompanion.Adapter.ModelChoice>
function M.sync(opts)
  local from_vendor = transform["from_" .. opts.name:lower()]
  assert(from_vendor, "No model transformer found for adapter: " .. opts.name)

  local cache_expires
  local cache_file = vim.fn.tempname()
  local cached_models

  return function(adapter)
    if cached_models and cache_expires and cache_expires > os.time() then
      return cached_models
    end

    local ok, response = pcall(function()
      return Curl.get(opts.url, {
        headers = opts.headers and opts.headers(adapter) or nil,
        insecure = config.adapters.http.opts.allow_insecure,
        proxy = config.adapters.http.opts.proxy,
        sync = true,
      })
    end)
    if not ok then
      log:error("Could not get the %s models from " .. opts.url .. "\nError: %s", opts.name, response)
      return {}
    end

    local decode_ok, json = pcall(vim.json.decode, response.body)
    if not decode_ok or not json.data then
      log:error("Error parsing the %s response from " .. opts.url .. "\nError: %s", opts.name, response.body)
      return {}
    end

    local models = {}
    for _, model in ipairs(json.data) do
      local id, entry = from_vendor(model)
      models[id] = entry
    end

    cached_models = models
    cache_expires = utils.refresh_cache(cache_file, config.adapters.http.opts.cache_models_for)

    return cached_models
  end
end

return M
