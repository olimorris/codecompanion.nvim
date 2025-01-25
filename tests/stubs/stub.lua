local math = require("math")

ExampleClass = {}
ExampleClass.__index = ExampleClass

function ExampleClass:new(value)
  local self = setmetatable({}, ExampleClass)
  self.value = value
  return self
end

function ExampleClass:compute()
  return math.sqrt(self.value)
end

return ExampleClass
