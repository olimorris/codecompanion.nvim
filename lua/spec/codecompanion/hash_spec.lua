local assert = require("luassert")
local hash = require("codecompanion.utils.hash")

describe("Hashing", function()
  it("the same string returns the same hash", function()
    local result = hash.hash("hello world")
    assert.are.same(894552257, result)
  end)
  it("differing strings does not return the same hash", function()
    local result = hash.hash("hello world!")
    assert.is_not.same(894552257, result)
  end)

  it("the same table returns the same hash", function()
    local tbl = {
      hello = "world",
      foo = "bar",
    }
    local result = hash.hash(tbl)
    assert.are.same(495487705, result)
  end)
end)
