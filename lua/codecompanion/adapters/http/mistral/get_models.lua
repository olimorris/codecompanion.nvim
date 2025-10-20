local Curl = require("plenary.curl")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils.adapters")

local CONSTANTS = {
  TIMEOUT = 3000, -- 3 seconds
}

---Whether there are already some requests running.
local running = false

local M = {}

---@class MistralModelInfo
---@field formatted_name string?
---@field opts {can_use_tools: boolean, has_vision: boolean}

---@class MistralApiCapabilities
---@field completion_chat boolean
---@field vision boolean
---@field function_calling boolean

---@class MistralApiModel
---@field id string
---@field name string
---@field aliases string[]
---@field deprecation any?
---@field capabilities MistralApiCapabilities

---@type table<string, MistralModelInfo>
local _cached_models = {}

---@return table<string, MistralModelInfo>
local function get_cached_models()
  return _cached_models
end

---When given a list of names that are aliases for the same model, returns the preferred name.
---The preference order is: names ending with '-latest' (highest priority),
---then names ending with four digits (e.g., '-2023'), and finally other names.
---@param names string[] List of names, should at least contain 1 entry
---@return string?
local function preferred_model_name(names)
  local high_score = -1
  local preferred_name
  local score
  for _, name in ipairs(names) do
    if string.find(name, "-latest$") then
      score = 2
    elseif string.find(name, "-%d%d%d%d$") then
      score = 1
    else
      score = 0
    end
    if score > high_score then
      high_score = score
      preferred_name = name
    end
  end
  return preferred_name
end

---Multiple id can refer to the same Model,
---This function removes duplicates, only using preferred model name
---@param models MistralApiModel[] Table as returned by Mistral API response
---@return MistralApiModel[]
local function dedup_models(models)
  local preferred_names = {}
  for _, model in ipairs(models) do
    if model.id then
      local aliases = model.aliases
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
---@return boolean cache was successful updated
---@param adapter CodeCompanion.HTTPAdapter Mistral adapter with env var replaced.
local function fetch_async(adapter)
  assert(adapter ~= nil)

  utils.get_env_vars(adapter)
  if running then
    return false
  end

  running = true

  _cached_models = _cached_models or {}

  local models_endpoint = "/v1/models"
  local headers = {
    ["content-type"] = "application/json",
    ["Authorization"] = "Bearer " .. adapter.env_replaced.api_key,
  }
  local url = adapter.env_replaced.url
  local ok, err = pcall(function()
    Curl.get(url .. models_endpoint, {
      headers = headers,
      insecure = config.adapters.http.opts.allow_insecure,
      proxy = config.adapters.http.opts.proxy,
      timeout = CONSTANTS.TIMEOUT,
      -- Schedule_wrap is used otherwise you get: nvim_create_namespace must not be called in a fast event context.
      -- This can happen wen you update vim ui in curl callback.
      callback = vim.schedule_wrap(function(response)
        if response.status ~= 200 then
          log:error("Could not get Mistral models from " .. url .. models_endpoint .. ". Error: %s", response.body)
          running = false
          return false
        end

        local ok, json = pcall(vim.json.decode, response.body)
        if not ok then
          log:error("Could not parse the response from " .. url .. models_endpoint)
          running = false
          return false
        end

        for _, model_obj in ipairs(dedup_models(json.data)) do
          -- Sometime models incorrect advertise capabilities.completion_chat.
          -- They informed me this is considered a bug, and are working on it.
          if model_obj.capabilities.completion_chat and model_obj.deprecation == vim.NIL then
            _cached_models[model_obj.id] = {
              formatted_name = model_obj.name,
              opts = {
                has_vision = model_obj.capabilities.vision or false,
                can_use_tools = model_obj.capabilities.function_calling or false,
              },
            }
          end
        end
        running = false
      end),
    })
  end)

  if not ok then
    log:error("Could not fetch fetch Mistral Copilot models: %s", err)
    running = false
    return false
  end
  return true
end

---@param self CodeCompanion.HTTPAdapter
---@return table<string, MistralModelInfo>
function M.choices(self)
  local models = get_cached_models()
  if models ~= nil and next(models) then
    return models
  end

  fetch_async(self)
  vim.wait(CONSTANTS.TIMEOUT, function()
    return not running
  end)
  return get_cached_models()
end
return M
