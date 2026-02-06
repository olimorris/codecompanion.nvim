local M = {}

local api = vim.api
local Curl = require("plenary.curl")
local config = require("codecompanion.config")
local files_utils = require("codecompanion.utils.files")
local ui_utils = require("codecompanion.utils.ui")

---@class (private) CodeCompanion.Image
---@field id string
---@field path string
---@field bufnr? integer
---@field base64? string
---@field mimetype? string

---Base64 encode the given image and generate the corresponding mimetype
---@param image CodeCompanion.Image The image object containing the path and other metadata.
---@return CodeCompanion.Image|string The base64 encoded image string
function M.encode_image(image)
  if image.base64 == nil then
    -- skip if already encoded
    local b64_content, b64_err = files_utils.base64_encode_file(image.path)
    if b64_err then
      return b64_err
    end

    image.base64 = b64_content
  end

  if not image.mimetype then
    image.mimetype = files_utils.get_mimetype(image.path)
  end

  return image
end

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
  desc = "Clear temporary files.",
})

---@class (private) CodeCompanion.Image.Preprocessor.Context
---@field chat_bufnr integer?
---@field from "slash_command"|"tool"

---@alias CodeCompanion.Image.Preprocessor
--- | fun(source: string, ctx: CodeCompanion.Image.Preprocessor.Context?, cb: fun(result: string|CodeCompanion.Image)):nil
--- | fun(source: string, ctx: CodeCompanion.Image.Preprocessor.Context?, cb: nil): string|CodeCompanion.Image

---@type CodeCompanion.Image.Preprocessor
function M.from_path(path, _, cb)
  local encoded = M.encode_image({ path = path, id = path, mimetype = files_utils.get_mimetype(path) })
  if type(cb) == "function" then
    return vim.schedule(function()
      ---@diagnostic disable-next-line: param-type-mismatch
      cb(encoded)
    end)
  end
  return encoded
end

--- key: chat bufnr
--- value: number of pending requests.
--- Use this to keep track of whether a notification in a chat buffer should be cleared.
--- When loading a local image, it's usually so fast that we don't need a virtual text notification.
---@type table<integer, integer>
local pending_requests = vim.defaulttable(function()
  return 0
end)

---@param bufnr integer
---@param force boolean?
local function clear_notification(bufnr, force)
  if pending_requests[bufnr] > 0 then
    pending_requests[bufnr] = pending_requests[bufnr] - 1
  end
  if pending_requests[bufnr] == 0 or force then
    -- clear the notification if there's no more pending requests.
    pending_requests[bufnr] = 0
    vim.schedule(function()
      ui_utils.clear_notification(bufnr, { namespace = "codecompanion_fetch_image_" .. tostring(bufnr) })
    end)
  end
end

---@param bufnr integer
local function set_notification(bufnr)
  if pending_requests[bufnr] == 0 then
    -- only set notification once for each turn.
    -- this avoids excessive notifications when the `fetch_images` tool requests for multiple images in parallel.
    vim.schedule(function()
      ui_utils.show_buffer_notification(bufnr, {
        namespace = "codecompanion_fetch_image_" .. tostring(bufnr),
        text = "Fetching image from the given URL...",
        main_hl = "Comment",
      })
    end)
  end
  pending_requests[bufnr] = pending_requests[bufnr] + 1
end

api.nvim_create_autocmd("User", {
  -- NOTE: the notification may stay if one of the requests failed. Use this autocmd to avoid persistent notification.
  pattern = "CodeCompanionChatSubmitted",
  callback = function(args)
    clear_notification(args.data.bufnr, true)
  end,
  group = "codecompanion.image",
  desc = "A fail-safe that guarantees the notification is cleared.",
})

---@type CodeCompanion.Image.Preprocessor
function M.from_url(url, ctx, cb)
  ctx = vim.tbl_deep_extend("force", { from = "tool" }, ctx or {})

  local loc = vim.fn.tempname()
  temp_files[#temp_files + 1] = loc

  -- initialise with the default error message
  ---@type string|CodeCompanion.Image
  local result = string.format("Could not get the image from %s.", url)

  if ctx.chat_bufnr and ctx.from == "slash_command" then
    -- only show notifications when invoked from slash commands, because tools already have a nice notification.
    set_notification(ctx.chat_bufnr)
  end

  local job = Curl.get(url, {
    insecure = config.adapters.http.opts.allow_insecure,
    proxy = config.adapters.http.opts.proxy,
    output = loc,
    callback = function(response)
      if ctx.from == "slash_command" then
        clear_notification(ctx.chat_bufnr)
      end

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

        result = M.encode_image({ mimetype = mimetype, path = loc, id = url })
        if result.mimetype == nil then
          result = "Failed to extract the mimetype of the image from: " .. url
        end
        if type(cb) == "function" then
          vim.schedule(function()
            cb(result)
          end)
        end
      end
    end,
  })
  if cb == nil then
    job:sync()
    return result
  end
end

return M
