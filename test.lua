local M = {}

-- Simple greeting function
function M.greeted(name)
  if type(name) ~= "string" then
    return "Invalid name provided"
  end
  return string.format("Hello, %s!", name)
end

-- Calculator function that performs basic operations
function M.calculate(operation, a, b)
  if type(a) ~= "number" or type(b) ~= "number" then
    return nil, "Invalid numbers provided"
  end

  local operations = {
    add = function(x, y)
      return x + y
    end,
    subtract = function(x, y)
      return x - y
    end,
    multiply = function(x, y)
      return x * y
    end,
    divide = function(x, y)
      if y == 0 then
        return nil, "Division by zero"
      end
      return x / y
    end,
  }

  if operations[operation] then
    return operations[operation](a, b)
  end
  return nil, "Invalid operation"
end

-- Table manipulation function
function M.filter_table(tbl, predicate)
  local result = {}
  for _, value in ipairs(tbl) do
    if predicate(value) then
      table.insert(result, value)
    end
  end
  return result
end

-- Function with multiple returns and error handling
function M.process_data(data)
  if type(data) ~= "table" then
    return nil, nil, "Input must be a table"
  end

  local sum = 0
  local count = 0

  for _, value in ipairs(data) do
    if type(value) == "number" then
      sum = sum + value
      count = count + 1
    end
  end

  if count == 0 then
    return nil, nil, "No valid numbers found"
  end

  return sum, sum / count, nil -- returns total, average, error
end

return M
