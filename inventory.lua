local M = {}

local items = {}

function M.add(name, quantity, price)
  table.insert(items, { name = name, quantity = quantity, price = price })
end

function M.remove(name)
  for i, item in ipairs(items) do
    if item.name == name then
      table.remove(items, i)
      return true
    end
  end
  return false
end

function M.total_quantity()
  local x = 0
  for _, item in ipairs(items) do
    x = x + item.quantity
  end
  return x
end

function M.total_value()
  local x = 0
  for _, item in ipairs(items) do
    x = x + item.quantity * item.price
  end
  return x
end

function M.find(name)
  for _, item in ipairs(items) do
    if item.name == name then
      return item
    end
  end
  return nil
end

function M.low_stock(threshold)
  local result = {}
  for _, item in ipairs(items) do
    if item.quantity < threshold then
      table.insert(result, item)
    end
  end
  return result
end

function M.apply_discount(percent)
  for _, item in ipairs(items) do
    item.price = item.price - item.price * percent / 100
  end
end

return M
