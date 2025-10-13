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

---@type table<string, table<string, { formatted_name: string?, opts: {can_reason: boolean, has_vision: boolean} }>>
local _cached_models = {}

---@param url string
---@param opts? MistralGetModelsOpts
local function get_cached_models(url, opts)
  assert(_cached_models[url] ~= nil, "Model info is not available in the cache.")
  local models = _cached_models[url]
  if opts and opts.last then
    return vim.tbl_keys(models)[1]
  else
    return models
  end
end

---When given list of names that are alias for the same model, return the preferred name
---@params names? table  list names, should at least contain 1 entry
---@return names? string
local function preferred_model_name(names)
  local high_score = -1
  local preferred_name
  local score
  for _, name in ipairs(names) do
    if string.find(name, "-latest$") then
      score = 2
    elseif string.find(name, "-%d%d%d%d$") then
      score = 0
    else
      score = 1
    end
    if score > high_score then
      high_score = score
      preferred_name = name
    end
  end
  return preferred_name
end

-- Multiple id can refer to the same Model,
-- This function removes duplicates, only using preferred model name
-- @param models table as returned by response mistral api
-- @return table
local function dedup_models(models)
  if models == nil then
    log:error("Could not get the Mistral models from ")
  end
  local preferred_names = {}
  for _, model in ipairs(models) do
    if model.id then
      local aliases = {}
      if model.aliases then
        aliases = model.aliases
      end
      table.insert(aliases, model.id)

      if preferred_names[model.id] then
        -- Model can have no alias, but still be a alias for other model.
        -- This will make sure it will still pick best name out those 2.
        -- This won't work for when m1 -> m2 <- m3. But don't think Mistral will make it that Complicated
        table.insert(aliases, preferred_names[model.id])
      end
      local preferred_name = preferred_model_name(aliases)
      for _, alias in ipairs(aliases) do
        preferred_names[alias] = preferred_name
      end
    end
  end
  local filtered_models = {}

  for _, model in ipairs(models) do
    -- Remove models that have aliases and don't have there preferred name.
    if model.id and model.id == preferred_names[model.id] then
      table.insert(filtered_models, model)
    end
  end
  return filtered_models
end

---Fetch model list and model info.
---Aborts if there's another fetch job running.
---Returns the number of models if the fetches are fired.
---@param adapter CodeCompanion.HTTPAdapter Ollama adapter with env var replaced.
---@param opts OllamaGetModelsOpts
local function fetch_async(adapter, opts)
  assert(adapter ~= nil)
  if running then
    return
  end

  local url = adapter.env_replaced.url
  local models_endpoint = adapter.env_replaced.models_endpoint

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

  pcall(function()
    local job = Curl.get(url .. models_endpoint, {
      headers = headers,
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
      timeout = CONSTANTS.TIMEOUT,
      callback = function(response)
        if response.status ~= 200 then
          return log:error("Could not get Mistral models from " .. url .. models_endpoint .. ".\nError: %s", response)
        end

        local ok, json = pcall(vim.json.decode, response.body)
        if not ok then
          return log:error("Could not parse the response from " .. url .. models_endpoint)
        end

        for _, model_obj in ipairs(dedup_models(json.data)) do

          -- Sometime models incorrect advertise capabilities.completion_chat.
          -- They informed me this is considered a bug, and are working on it.
          print(model_obj.deprecation)
          if model_obj.capabilities.completion_chat and  model_obj.deprecation == vim.NIL then
            _cached_models[url][model_obj.id] = { formatted_name = model_obj.name, opts = {} }
            _cached_models[url][model_obj.id].opts.has_vision = model_obj.capabilities.vision or false
            _cached_models[url][model_obj.id].opts.can_use_tools = model_obj.capabilities.function_calling or false

          end
        end
        running = false
        _cached_models[url] = _cached_models[url] or {}  -- TODO: this has the side effect models are never removed
      end,
    })
    if adapter.opts.cache_adapter == false then
      vim.wait(CONSTANTS.TIMEOUT, function()
        local models = _cached_models[url]
        return models ~= nil and not vim.tbl_isempty(models) and not running
      end)
    end
  end)
end

function M.choices(self, opts)
  local adapter = require("codecompanion.adapters.http").resolve(self) --[[@as CodeCompanion.HTTPAdapter]]
  opts = vim.tbl_deep_extend("force", { async = true }, opts or {})
  if not adapter then
    log:error("Could not resolve Mistral adapter in the `choices` function")
    return {}
  end
  utils.get_env_vars(adapter)
  local url = adapter.env_replaced.url
  local is_uninitialised = _cached_models[url] == nil

  local should_block = (self.opts.cache_adapter == false) or is_uninitialised or not opts.async

  fetch_async(adapter, { async = not should_block }) -- should_block means NO async

  if should_block and running then
    vim.wait(CONSTANTS.TIMEOUT, function()
      return not running
    end)
  end
  return get_cached_models(url, opts)
end

return M
