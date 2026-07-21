local fetch_models = require("codecompanion.adapters.utils.models.fetch")
local token = require("codecompanion.adapters.http.copilot.token")

local CONSTANTS = {
  AUTO_MODEL = "auto",
}

local M = {}

---@class CopilotModels
---@field formatted_name string
---@field vendor? string
---@field opts { can_stream: boolean, can_use_tools: boolean, has_vision: boolean }

---Resolve the Copilot token to authenticate the models request with
---@param request_opts? { token?: table, async?: boolean }
---@return table|nil
local function resolve_token(request_opts)
  if request_opts and request_opts.token then
    return request_opts.token
  end
  local force = request_opts and request_opts.async == false
  return token.fetch({ force = force })
end

local models_source = {
  name = "Copilot",
  ---@param _ CodeCompanion.HTTPAdapter
  ---@param request_opts? { token?: table, async?: boolean }
  ---@return string
  url = function(_, request_opts)
    local fresh_token = resolve_token(request_opts)
    local base_url = (fresh_token and fresh_token.endpoints and fresh_token.endpoints.api)
      or "https://api.githubcopilot.com"
    return base_url .. "/models"
  end,
  ---@param adapter CodeCompanion.HTTPAdapter
  ---@param request_opts? { token?: table, async?: boolean }
  ---@return table|nil
  headers = function(adapter, request_opts)
    local fresh_token = resolve_token(request_opts)
    if not fresh_token or not fresh_token.copilot_token then
      return nil
    end

    local headers = vim.deepcopy(adapter.headers or {})
    headers["Authorization"] = "Bearer " .. fresh_token.copilot_token
    headers["X-Github-Api-Version"] = "2025-10-01"
    return headers
  end,
}

---GitHub picks the model on our behalf; capabilities are assumed to match the best available model
---@type CopilotModels
local auto_model = {
  formatted_name = "Auto",
  opts = {
    can_stream = true,
    can_use_tools = true,
    has_vision = true,
  },
}

---Canonical interface used by adapter.schema.model.choices implementations.
---@param adapter table
---@param opts? { token: table, async: boolean }
---@return table<string, CopilotModels>|nil
function M.choices(adapter, opts)
  local result = fetch_models.get(models_source, adapter, opts)

  if opts and opts.async == false then
    result = result or {}
    result[CONSTANTS.AUTO_MODEL] = result[CONSTANTS.AUTO_MODEL] or auto_model
    return result
  end

  -- Non-blocking lookups return nil until the background fetch has populated the cache
  if not (result and not vim.tbl_isempty(result)) then
    return nil
  end

  result[CONSTANTS.AUTO_MODEL] = result[CONSTANTS.AUTO_MODEL] or auto_model
  return result
end

return M
