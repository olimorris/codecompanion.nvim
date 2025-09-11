local Curl = require("plenary.curl")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.adapters")

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

---Get a list of available Ollama models
---@params self CodeCompanion.HTTPAdapter
---@params opts? table
---@return table
function M.choices(self, opts)
  -- Prevent the adapter from being resolved multiple times due to `get_models`
  -- having both `default` and `choices` functions

  local adapter = require("codecompanion.adapters").resolve(self)
  if not adapter then
    log:error("Could not resolve Ollama adapter in the `get_models` function")
    return {}
  end
  utils.get_env_vars(adapter)
  local url = adapter.env_replaced.url
  if _cached_models[url] == nil then
    log:trace("Cache miss. Fetching model info from Ollama server %s.", url)
    _cached_models[url] = {}
  else
    -- cache hit
    log:trace("Cache hit for Ollama server %s:\n%s", url, vim.inspect(_cached_models))
    return get_cached_models(url, opts)
  end

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
    })
  end)
  if not ok then
    log:error("Could not get the Ollama models from " .. url .. "/api/tags.\nError: %s", response)
    return {}
  end

  local ok, json = pcall(vim.json.decode, response.body)
  if not ok then
    log:error("Could not parse the response from " .. url .. "/api/tags")
    return {}
  end

  local jobs = {}

  for _, model_obj in ipairs(json.models) do
    -- start async requests
    local job = Curl.post(url .. "/api/show", {
      headers = headers,
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
      body = vim.json.encode({ model = model_obj.name }),
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
      end,
    })
    table.insert(jobs, job)
  end

  for _, job in ipairs(jobs) do
    -- wait for the requests to finish.
    job:wait()
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
