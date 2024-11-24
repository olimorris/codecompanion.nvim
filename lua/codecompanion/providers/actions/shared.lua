local M = {}

--- Select the item and execute it
--- @param provider table provider that's calling this function
--- @param item table
function M.select(provider, item)
  -- If the user has selected an item which contains a picker then we open a picker
  if item.picker and type(item.picker.items) == "table" then
    local picker_opts = {
      prompt = item.picker.prompt,
      columns = item.picker.columns,
    }
    return provider:picker(provider.validate(item.picker.items, provider.context), picker_opts)
    -- If the picker items are a function then we need to validate them against the context
  elseif item.picker and type(item.picker.items) == "function" then
    local picker_opts = {
      prompt = item.picker.prompt,
      columns = item.picker.columns,
    }
    return provider:picker(provider.validate(item.picker.items(provider.context), provider.context), picker_opts)
  -- Otherwise we can just execute it if it's a function
  elseif item and type(item.callback) == "function" then
    return item.callback(provider.context)
  else
    -- Or resolve it down to a strategy
    return provider.resolve(item, provider.context)
  end
end

return M
