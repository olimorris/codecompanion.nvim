local M = {}

---Extend a default adapter
---@param base_tbl table
---@param new_tbl table
---@return nil
function M.extend(base_tbl, new_tbl)
  for name, adapter in pairs(new_tbl) do
    if base_tbl[name] then
      if type(adapter) == "table" then
        base_tbl[name] = adapter
        if adapter.schema then
          base_tbl[name].schema = vim.tbl_deep_extend("force", base_tbl[name].schema, adapter.schema)
        end
      end
    end
  end
end

---Make an adapter safe for serialization
---@param adapter CodeCompanion.Adapter
---@return table
function M.make_safe(adapter)
  return {
    name = adapter.name,
    features = adapter.features,
    url = adapter.url,
    headers = adapter.headers,
    params = adapter.parameters,
    opts = adapter.opts,
    handlers = adapter.handlers,
    schema = vim
      .iter(adapter.schema)
      :filter(function(n, _)
        if n == "model" then
          return false
        end
        return true
      end)
      :totable(),
  }
end

return M
