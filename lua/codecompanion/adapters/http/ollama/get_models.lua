local Curl = require("plenary.curl")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.adapters")

local CONSTANTS = {
  TIMEOUT = 3000, -- 3 seconds
  POLL_INTERVAL = 10,
}

---Whether there are already some requests running.
local running = false

M = {}

---Structure:
---```lua
---_cached_models[url][model_name] = { opts = { can_reason = true, has_vision = false }, nice_name = 'nice_name' }
---```
---@type table<string, table<string, { nice_name: string?, opts: {can_reason: boolean, has_vision: boolean} }>>
local _cached_models = {}

---@param url string
---@param opts? {last: boolean}
local function get_cached_models(url, opts)
  assert(_cached_models[url] ~= nil, "Model info is not available in the cache.")
  local models = _cached_models[url]
  if opts and opts.last then
    return vim.tbl_keys(models)[1]
  else
    return models
  end
end

---Fetch model list and model info.
---Aborts if there's another fetch job running.
---Returns the number of models if the fetches are fired.
---@param adapter CodeCompanion.HTTPAdapter
---@param url string
---@return integer?
local function fetch_async(adapter, url)
  assert(adapter ~= nil)
  assert(url ~= nil)
  if running then
    return
  end
  running = true
  _cached_models[url] = _cached_models[url] or {}
  local headers = {
    ["content-type"] = "application/json",
  }

  local auth_header = "Bearer "
  if adapter.env_replaced.authorization then
    auth_header = adapter.env_replaced.authorization .. " "
  end
  if adapter.env_replaced.api_key then
    headers["Authorization"] = auth_header .. adapter.env_replaced.api_key
  end

  local ok, response = pcall(function()
    return Curl.get(url .. "/api/tags", {
      sync = true,
      headers = headers,
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
      timeout = CONSTANTS.TIMEOUT,
    })
  end)
  if not ok then
    log:error("Could not get the Ollama models from " .. url .. "/api/tags.\nError: %s", response)
    return
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Could not parse the response from " .. url .. "/api/tags")
    return
  end

  local jobs = {}

  for _, model_obj in ipairs(json.models) do
    -- start async requests
    jobs[model_obj.name] = Curl.post(url .. "/api/show", {
      headers = headers,
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
      body = vim.json.encode({ model = model_obj.name }),
      timeout = CONSTANTS.TIMEOUT,
      callback = function(output)
        _cached_models[url][model_obj.name] = { nice_name = model_obj.name, opts = {} }
        if output.status == 200 then
          local ok, model_info_json = pcall(vim.json.decode, output.body, { array = true, object = true })
          if ok then
            _cached_models[url][model_obj.name].opts.can_reason =
              vim.list_contains(model_info_json.capabilities or {}, "thinking")
            _cached_models[url][model_obj.name].opts.has_vision =
              vim.list_contains(model_info_json.capabilities or {}, "vision")
          end
        end
        jobs[model_obj.name] = nil
        if vim.tbl_isempty(jobs) then
          running = false
        end
      end,
    })
  end
  return #json.models
end

---Get a list of available Ollama models
---@param self CodeCompanion.HTTPAdapter
---@param opts? table
---@return table
function M.choices(self, opts)
  local adapter = require("codecompanion.adapters.http").resolve(self) --[[@as CodeCompanion.HTTPAdapter]]
  opts = vim.tbl_deep_extend("force", { async = true }, opts or {})
  if not adapter then
    log:error("Could not resolve Ollama adapter in the `choices` function")
    return {}
  end
  utils.get_env_vars(adapter)
  local url = adapter.env_replaced.url
  local is_uninitialised = _cached_models[url] == nil

  local num_models = fetch_async(adapter, url)

  if is_uninitialised or not opts.async then
    -- block here if `async == false` or uninitialised
    vim.wait(CONSTANTS.TIMEOUT, function()
      local models = _cached_models[url]
      if num_models ~= nil then
        return #vim.tbl_keys(models) == num_models
      else
        return models ~= nil and not vim.tbl_isempty(models)
      end
    end)
  end

  return get_cached_models(url, opts)
end

---Return `true` if the model of the adapter supports thinking.
---@param self CodeCompanion.HTTPAdapter
---@param model? string|function
---@return boolean
function M.check_thinking_capability(self, model)
  model = model or self.schema.model.default
  if type(model) == "function" then
    model = model(self)
  end
  local _choices = self.schema.model.choices
  if type(_choices) == "function" then
    _choices = _choices(self)
  end
  if _choices and _choices[model] and _choices[model].opts and _choices[model].opts.can_reason then
    return true
  end
  return false
end

return M
