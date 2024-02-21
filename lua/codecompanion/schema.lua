local config = require("codecompanion.config")
local curl = require("plenary.curl")

local M = {}

M.get_default = function(schema, defaults)
  local ret = {}
  for k, v in pairs(schema) do
    if not vim.startswith(k, "_") then
      if defaults and defaults[k] ~= nil then
        ret[k] = defaults[k]
      else
        ret[k] = v.default
      end
    end
  end
  return ret
end

---@class CodeCompanion.SchemaParam
---@field type "string"|"number"|"integer"|"boolean"|"enum"|"list"|"map"
---@field order nil|integer
---@field optional nil|boolean
---@field choices nil|table
---@field desc string
---@field validate? fun(value: any): boolean, nil|string

---@param schema CodeCompanion.SchemaParam
---@param value any
---@return boolean
---@return nil|string
local function validate_type(schema, value)
  local ptype = schema.type or "string"
  if value == nil then
    return schema.optional
  elseif ptype == "enum" then
    local valid = vim.tbl_contains(schema.choices, value)
    if not valid then
      return valid, string.format("must be one of %s", table.concat(schema.choices, ", "))
    else
      return valid
    end
  elseif ptype == "list" then
    -- TODO validate subtype
    return type(value) == "table" and vim.tbl_islist(value)
  elseif ptype == "map" then
    local valid = type(value) == "table" and (vim.tbl_isempty(value) or not vim.tbl_islist(value))
    -- TODO validate subtype and subtype_key
    if valid then
      -- Hack to make sure empty dicts get serialized properly
      setmetatable(value, vim._empty_dict_mt)
    end
    return valid
  elseif ptype == "number" then
    return type(value) == "number"
  elseif ptype == "integer" then
    return type(value) == "number" and math.floor(value) == value
  elseif ptype == "boolean" then
    return type(value) == "boolean"
  elseif ptype == "string" then
    return true
  else
    error(string.format("Unknown param type '%s'", ptype))
  end
end

---@param schema CodeCompanion.SchemaParam
---@param value any
---@return boolean
---@return nil|string
local function validate_field(schema, value)
  local valid, err = validate_type(schema, value)
  if not valid then
    return valid, err
  end
  if schema.validate and value ~= nil then
    return schema.validate(value)
  end
  return true
end

---@param schema CodeCompanion.SchemaParam
---@param values table
---@return nil|table<string, string>
M.validate = function(schema, values)
  local errors = {}
  for k, v in pairs(schema) do
    local valid, err = validate_field(v, values[k])
    if not valid then
      errors[k] = err or string.format("Not a valid %s", v.type)
    end
  end
  if not vim.tbl_isempty(errors) then
    return errors
  end
end

---@param schema CodeCompanion.SchemaParam
---@return string[]
M.get_ordered_keys = function(schema)
  local keys = vim.tbl_keys(schema)
  -- Sort the params by required, then if they have no value, then by name
  table.sort(keys, function(a, b)
    local aparam = schema[a]
    local bparam = schema[b]
    if aparam.order then
      if not bparam.order then
        return true
      elseif aparam.order ~= bparam.order then
        return aparam.order < bparam.order
      end
    elseif bparam.order then
      return false
    end
    if (aparam.optional == true) ~= (bparam.optional == true) then
      return bparam.optional
    end
    return a < b
  end)
  return keys
end

M.static = {}

local model_choices = {
  "gpt-4-1106-preview",
  "gpt-4",
  "gpt-3.5-turbo-1106",
  "gpt-3.5-turbo",
}

M.static.chat_settings = {
  model = {
    order = 1,
    type = "enum",
    desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
    default = config.options.ai_settings.chat.model,
    choices = model_choices,
  },
  temperature = {
    order = 2,
    type = "number",
    optional = true,
    default = config.options.ai_settings.chat.temperature,
    desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
    validate = function(n)
      return n >= 0 and n <= 2, "Must be between 0 and 2"
    end,
  },
  top_p = {
    order = 3,
    type = "number",
    optional = true,
    default = config.options.ai_settings.chat.top_p,
    desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
    validate = function(n)
      return n >= 0 and n <= 1, "Must be between 0 and 1"
    end,
  },
  stop = {
    order = 4,
    type = "list",
    optional = true,
    default = config.options.ai_settings.chat.stop,
    subtype = {
      type = "string",
    },
    desc = "Up to 4 sequences where the API will stop generating further tokens.",
    validate = function(l)
      return #l >= 1 and #l <= 4, "Must have between 1 and 4 elements"
    end,
  },
  max_tokens = {
    order = 5,
    type = "integer",
    optional = true,
    default = config.options.ai_settings.chat.max_tokens,
    desc = "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
    validate = function(n)
      return n > 0, "Must be greater than 0"
    end,
  },
  presence_penalty = {
    order = 6,
    type = "number",
    optional = true,
    default = config.options.ai_settings.chat.presence_penalty,
    desc = "Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model's likelihood to talk about new topics.",
    validate = function(n)
      return n >= -2 and n <= 2, "Must be between -2 and 2"
    end,
  },
  frequency_penalty = {
    order = 7,
    type = "number",
    optional = true,
    default = config.options.ai_settings.chat.frequency_penalty,
    desc = "Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model's likelihood to repeat the same line verbatim.",
    validate = function(n)
      return n >= -2 and n <= 2, "Must be between -2 and 2"
    end,
  },
  logit_bias = {
    order = 8,
    type = "map",
    optional = true,
    default = config.options.ai_settings.chat.logit_bias,
    desc = "Modify the likelihood of specified tokens appearing in the completion. Maps tokens (specified by their token ID) to an associated bias value from -100 to 100. Use https://platform.openai.com/tokenizer to find token IDs.",
    subtype_key = {
      type = "integer",
    },
    subtype = {
      type = "integer",
      validate = function(n)
        return n >= -100 and n <= 100, "Must be between -100 and 100"
      end,
    },
  },
  user = {
    order = 9,
    type = "string",
    optional = true,
    default = config.options.ai_settings.chat.user,
    desc = "A unique identifier representing your end-user, which can help OpenAI to monitor and detect abuse. Learn more.",
    validate = function(u)
      return u:len() < 100, "Cannot be longer than 100 characters"
    end,
  },
}

M.static.client_settings = {
  request = { default = curl.post },
  encode = { default = vim.json.encode },
  decode = { default = vim.json.decode },
  schedule = { default = vim.schedule },
}

return M
