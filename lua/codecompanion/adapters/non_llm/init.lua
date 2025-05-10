local Adapter = require("codecompanion.adapters")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

---@class CodeCompanion.NonLLMAdapter: CodeCompanion.Adapter
local NonLLMAdapter = {}

for k, v in pairs(Adapter) do
  NonLLMAdapter[k] = v
end

---@param adapter? CodeCompanion.NonLLMAdapter|string|function
---@return CodeCompanion.Adapter
function NonLLMAdapter.resolve(adapter)
  adapter = adapter or config.adapters.non_llm[config.strategies.chat.adapter]

  if type(adapter) == "table" then
    adapter = NonLLMAdapter.new(adapter)
  elseif type(adapter) == "string" then
    adapter = NonLLMAdapter.extend(adapter)
  elseif type(adapter) == "function" then
    adapter = adapter()
  end

  return adapter.set_model(adapter)
end

---@return CodeCompanion.NonLLMAdapter
function NonLLMAdapter.new(args)
  return setmetatable(args, { __index = NonLLMAdapter })
end

---Extend an existing non LLM adapter
---@param adapter table|string|function
---@param opts? table
---@return CodeCompanion.NonLLMAdapter
function NonLLMAdapter.extend(adapter, opts)
  local ok
  local adapter_config

  if type(adapter) == "string" then
    ok, adapter_config = pcall(require, "codecompanion.adapters.non_llm." .. adapter)
    if not ok then
      adapter_config = config.adapters.non_llm[adapter]
      if type(adapter_config) == "function" then
        adapter_config = adapter_config()
      end
    end
  elseif type(adapter) == "function" then
    adapter_config = adapter()
  else
    adapter_config = adapter
  end

  adapter_config = vim.tbl_deep_extend("force", {}, vim.deepcopy(adapter_config), opts or {})

  return NonLLMAdapter.new(adapter_config)
end

return NonLLMAdapter
