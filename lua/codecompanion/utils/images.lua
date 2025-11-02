local M = {}

local Curl = require("plenary.curl")
local base64 = require("codecompanion.utils.base64")
local config = require("codecompanion.config")
local helpers = require("codecompanion.strategies.chat.helpers")
local ui_utils = require("codecompanion.utils.ui")

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

---@class (private) CodeCompanion.Image.Preprocessor.Context
---@field chat_bufnr integer?

---@alias CodeCompanion.Image.Preprocessor
--- | fun(source: string, ctx: CodeCompanion.Image.Preprocessor.Context?, cb: fun(result: string|CodeCompanion.Image)):nil
--- | fun(source: string, ctx: CodeCompanion.Image.Preprocessor.Context?, cb: nil): string|CodeCompanion.Image

---@type CodeCompanion.Image.Preprocessor
function M.from_path(path, _, cb)
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
function M.from_url(url, ctx, cb)
  ctx = ctx or {}

  local loc = vim.fn.tempname()
  temp_files[#temp_files + 1] = loc

  -- initialise with the default error message
  ---@type string|CodeCompanion.Image
  local result = string.format("Could not get the image from %s.", url)

  local extmark_id = nil

  local ns = nil
  if ctx.chat_bufnr then
    ns = "codecompanion_fetch_image_" .. tostring(ctx.chat_bufnr)
    vim.schedule(function()
      extmark_id = ui_utils.show_buffer_notification(
        ctx.chat_bufnr,
        { namespace = ns, text = "Fetching image from the given URL...", main_hl = "Comment" }
      )
    end)
  end
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
      else
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
      end

      if extmark_id then
        vim.schedule(function()
          extmark_id = nil
          ui_utils.clear_notification(ctx.chat_bufnr, { namespace = ns })
        end)
      end
    end,
  })
  if cb == nil then
    job:sync()
    if extmark_id then
      extmark_id = nil
      vim.schedule(function()
        ui_utils.clear_notification(ctx.chat_bufnr, { namespace = ns })
      end)
    end
    return result
  end
end

return M
