local function greet(name)
  name = name or "world"
  local message = "Hello, " .. name .. "!"
  print(message)
  return message
end

---@param a number|nil
---@param b number|nil
---@return number
local function add(a, b)
  a = a or 0
  b = b or 0
  local sum = a + b
  print("Sum:", sum)
  return sum
end

---@return number
local function count(tbl)
  if type(tbl) ~= "table" then
    error("count: expected table, got " .. type(tbl))
  end
  local n = 0
  for _ in pairs(tbl) do
    n = n + 1
  end
  print("Table size:", n)
  return n
end

---@param n number
---@return number
local function factorial(n)
  if n < 0 then
    error("factorial: negative input")
  elseif n == 0 then
    return 1
  else
    return n * factorial(n - 1)
  end
end

return {
  greet = greet,
  add = add,
  count = count,
  factorial = factorial,
}
