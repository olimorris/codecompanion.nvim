local adapter
local assert = require("luassert")
local helpers = require("spec.codecompanion.adapters.helpers")

local json1 = [[{
  "github.com:12345": {
    "user": "rdvm",
    "oauth_token": "abc123",
    "githubAppId": "1"
  }
}]]

local json2 = [[{
  "github.com":{
    "user": "olimorris",
    "oauth_token":"abc123"
  }
}
]]

local function get_token(json)
  local data = vim.fn.json_decode(json)
  if data["github.com"] then
    return data["github.com"].oauth_token
  else
    for key, value in pairs(data) do
      if key:match("^github.com:") then
        return value.oauth_token
      end
    end
  end
  return nil
end

describe("Copilot adapter", function()
  before_each(function()
    adapter = require("codecompanion.adapters").resolve("copilot")
  end)

  it("can get the oauth_token", function()
    assert.equals("abc123", get_token(json1))
    assert.equals("abc123", get_token(json2))
  end)
end)
