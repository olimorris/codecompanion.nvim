local M = {}

local Curl = require("plenary.curl")
local base64 = require("codecompanion.utils.base64")
local config = require("codecompanion.config")
local helpers = require("codecompanion.strategies.chat.helpers")
local log = require("codecompanion.utils.log")

---@class (private) CodeCompanion.Image
---@field id string
---@field path string
---@field bufnr? integer
---@field base64? string
---@field mimetype? string

---Keep track of temp files, and GC them at `VimLeavePre`
---@type string[]
local temp_files = {}

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    vim.iter(temp_files):each(function(p)
      (vim.uv or vim.loop).fs_unlink(p)
    end)
  end,
  group = vim.api.nvim_create_augroup("codecompanion.image", { clear = true }),
})

---@alias CodeCompanion.Image.Preprocessor
--- | fun(source: string, cb: fun(result: string|CodeCompanion.Image)):nil
--- | fun(source: string, cb: nil): string|CodeCompanion.Image

---@type CodeCompanion.Image.Preprocessor
function M.from_path(path, cb)
  local encoded = helpers.encode_image({ path = path, id = path, mimetype = base64.get_mimetype(path) })
  if type(cb) == "function" then
    return vim.schedule(function()
      ---@diagnostic disable-next-line: param-type-mismatch
      cb(encoded)
    end)
  end
  return encoded
end

---@type CodeCompanion.Image.Preprocessor
function M.from_url(url, cb)
  local loc = vim.fn.tempname()
  temp_files[#temp_files + 1] = loc

  -- initialise with the default error message
  ---@type string|CodeCompanion.Image
  local result = string.format("Could not get the image from %s.", url)

  local job = Curl.get(url, {
    insecure = config.adapters.http.opts.allow_insecure,
    proxy = config.adapters.http.opts.proxy,
    output = loc,
    callback = function(response)
      if response.status ~= 200 then
        result = string.format(
          "Could not get the image from %s.\nHTTP Status: %d\nError: %s",
          url,
          response.status,
          response.body
        )
        if type(cb) == "function" then
          cb(result)
        end
        return
      end

      local mimetype = nil
      if response.headers then
        for _, header_line in ipairs(response.headers) do
          local key, value = header_line:match("^([^:]+):%s*(.+)$")
          if key and value and key:lower() == "content-type" then
            mimetype = vim.trim(value:match("^([^;]+)")) -- Get part before any '; charset=...'
            break
          end
        end
      end

      result = helpers.encode_image({ mimetype = mimetype, path = loc, id = url })
      if type(cb) == "function" then
        vim.schedule(function()
          cb(result)
        end)
      end
    end,
  })
  if cb == nil then
    job:sync()
    return result
  end
end

return M
