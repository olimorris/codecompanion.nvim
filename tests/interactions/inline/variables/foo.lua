local Foo = {}

---@param args table
function Foo.new(args)
  return setmetatable({
    context = args.context,
  }, { __index = Foo })
end

---Fetch and output a foo
---@return string
function Foo:output()
  return "The output from foo variable"
end

return Foo
