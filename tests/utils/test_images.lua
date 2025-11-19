local h = require("tests.helpers")
local im_utils = require("codecompanion.utils.images")
local log = require("codecompanion.utils.log")
local new_set = MiniTest.new_set
local stub_img_path = vim.fn.getcwd() .. "/tests/stubs/logo.png"
local stub_base64_start = "iVBORw0KGgoAAAANSUhEU"

local T = new_set()

T["Image utils"] = new_set()
T["Image utils"]["encode_image"] = new_set()

T["Image utils"]["encode_image"]["can encode image"] = function()
  local encoded = im_utils.encode_image({ path = stub_img_path, id = stub_img_path })

  h.expect_starts_with(stub_base64_start, encoded.base64)
  h.eq("image/png", encoded.mimetype)
end

T["Image utils"]["encode_image"]["can throw error"] = function()
  h.eq("string", type(im_utils.encode_image({ path = "foo", id = "bar" })))
end

T["Image utils"]["encode from sources"] = new_set()
T["Image utils"]["encode from sources"]["from_path"] = function()
  local encoded = im_utils.from_path(stub_img_path, {})
  h.eq("table", type(encoded))
  h.expect_starts_with(stub_base64_start, encoded.base64)

  im_utils.from_path(stub_img_path, {}, function(_encoded)
    h.eq("table", type(_encoded))
    h.expect_starts_with(stub_base64_start, _encoded.base64)
  end)
end

T["Image utils"]["encode from sources"]["from_url"] = function()
  local url = "https://raw.githubusercontent.com/olimorris/codecompanion.nvim/main/tests/stubs/logo.png?raw=true"
  local encoded = im_utils.from_url(url, {})
  h.eq("table", type(encoded))
  h.expect_starts_with(stub_base64_start, encoded.base64)

  im_utils.from_url(url, {}, function(_encoded)
    h.eq("table", type(_encoded))
    h.expect_starts_with(stub_base64_start, _encoded.base64)
  end)
end

return T
