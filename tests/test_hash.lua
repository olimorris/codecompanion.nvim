local h = require("tests.helpers")
local hash = require("codecompanion.utils.hash")

describe("Hashing", function()
  it("the same string returns the same hash", function()
    local result = hash.hash("hello world")
    h.eq(894552257, result)
  end)
  it("differing strings does not return the same hash", function()
    local result = hash.hash("hello world!")
    h.expect.no_equality(894552257, result)
  end)

  it("the same table returns the same hash", function()
    local tbl = {
      hello = "world",
      foo = "bar",
    }
    local result = hash.hash(tbl)
    h.eq(495487705, result)
  end)
end)
