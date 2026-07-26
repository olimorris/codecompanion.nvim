local h = require("tests.helpers")
local im_utils = require("codecompanion.utils.images")
local log = require("codecompanion.utils.log")
local new_set = MiniTest.new_set
local stub_img_path = vim.fn.getcwd() .. "/tests/stubs/logo.png"
local stub_base64_start = "iVBORw0KGgoAAAANSUhEU"

---Serve the stub image from `Curl.get` instead of the network
---@return function restore
local function serve_stub_image()
  local curl = require("plenary.curl")
  local original_get = curl.get
  curl.get = function(_, opts)
    vim.uv.fs_copyfile(stub_img_path, opts.output)
    opts.callback({ status = 200, headers = { "content-type: image/png" } })
    return { sync = function() end }
  end
  return function()
    curl.get = original_get
  end
end

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
  local url = "https://example.com/logo.png"
  local restore = serve_stub_image()

  local encoded = im_utils.from_url(url, {})
  h.eq("table", type(encoded))
  h.expect_starts_with(stub_base64_start, encoded.base64)

  local from_callback
  im_utils.from_url(url, {}, function(_encoded)
    from_callback = _encoded
  end)
  vim.wait(1000, function()
    return from_callback ~= nil
  end, 10)

  restore()
  h.eq("table", type(from_callback))
  h.expect_starts_with(stub_base64_start, from_callback.base64)
end

return T
