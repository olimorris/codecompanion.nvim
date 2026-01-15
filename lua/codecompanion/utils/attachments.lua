local Curl = require("plenary.curl")
local config = require("codecompanion.config")
local files_utils = require("codecompanion.utils.files")
local ui_utils = require("codecompanion.utils.ui")

local M = {}

---Build attachment types dynamically from config
---@return table<string, { extensions: string[], max_size_mb: number }>
local function build_attachment_types()
  local types = {}

  -- Get image extensions from /image slash command config
  local image_cmd = config.interactions.chat.slash_commands["image"]
  if image_cmd and image_cmd.opts and image_cmd.opts.filetypes then
    types.image = {
      extensions = image_cmd.opts.filetypes,
      max_size_mb = 10, -- Image size limit
    }
  end

  -- Get attachment (document) extensions from /attachment slash command config
  local attachment_cmd = config.interactions.chat.slash_commands["attachment"]
  if attachment_cmd and attachment_cmd.opts and attachment_cmd.opts.filetypes then
    types.attachment = {
      extensions = attachment_cmd.opts.filetypes,
      max_size_mb = 32, -- Document size limit
    }
  end

  return types
end

---Attachment-specific MIME types (fallback for types not in files_utils)
---@type table<string, string>
local ATTACHMENT_MIME_TYPES = {
  -- Images
  bmp = "image/bmp",
  tiff = "image/tiff",
  svg = "image/svg+xml",
  -- Documents
  xlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  pptx = "application/vnd.openxmlformats-officedocument.presentationml.presentation",
}

---Get image file extensions from config
---@return string[]
function M.get_image_filetypes()
  local types = build_attachment_types()
  return types.image and vim.deepcopy(types.image.extensions) or {}
end

---Get attachment (document) file extensions from config
---@return string[]
function M.get_attachment_filetypes()
  local types = build_attachment_types()
  return types.attachment and vim.deepcopy(types.attachment.extensions) or {}
end

---Get all supported file extensions as a flat list
---@return string[]
function M.get_all_filetypes()
  local types = build_attachment_types()
  local all = {}
  for _, type_info in pairs(types) do
    vim.list_extend(all, type_info.extensions)
  end
  return all
end

---Get MIME type for a file, using files_utils first, then attachment-specific fallback
---@param path string
---@return string|nil
local function get_mimetype(path)
  -- Try files_utils first (handles most common types)
  local mimetype = files_utils.get_mimetype(path)
  if mimetype then
    return mimetype
  end

  -- Fallback to attachment-specific MIME types
  local ext = path:match("%.([^%.]+)$")
  if ext then
    ext = ext:lower()
    return ATTACHMENT_MIME_TYPES[ext]
  end

  return nil
end

---@class (private) CodeCompanion.Attachment
---@field id string
---@field path string
---@field bufnr? integer
---@field base64? string
---@field mimetype? string
---@field source? string "base64"|"url"|"file"
---@field url? string
---@field file_id? string
---@field attachment_type? string "image"|"attachment"

---Keep track of temp files, and GC them at `VimLeavePre`
---@type string[]
local temp_files = {}

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    vim.iter(temp_files):each(function(p)
      (vim.uv or vim.loop).fs_unlink(p)
    end)
  end,
  group = vim.api.nvim_create_augroup("codecompanion.attachments", { clear = true }),
  desc = "Clear temporary attachment files.",
})

---Get all supported file extensions
---@return table<string, string> Map of extension to type
function M.get_supported_extensions()
  local types = build_attachment_types()
  local exts = {}
  for type_name, type_info in pairs(types) do
    for _, ext in ipairs(type_info.extensions) do
      exts[ext] = type_name
    end
  end
  return exts
end

---Detect attachment type from file extension
---@param path string
---@return string|nil type "image"|"attachment" or nil if unsupported
local function detect_attachment_type(path)
  local ext = path:match("%.([^%.]+)$")
  if not ext then
    return nil
  end
  ext = ext:lower()

  local types = build_attachment_types()
  for type_name, type_info in pairs(types) do
    if vim.tbl_contains(type_info.extensions, ext) then
      return type_name
    end
  end

  return nil
end

---Validate attachment file
---@param path string
---@return boolean success, string? error_message
local function validate_attachment(path)
  local stat = vim.loop.fs_stat(path)
  if not stat then
    return false, "File does not exist"
  end

  local attachment_type = detect_attachment_type(path)
  if not attachment_type then
    local types = build_attachment_types()
    local supported_exts = {}
    for _, type_info in pairs(types) do
      vim.list_extend(supported_exts, type_info.extensions)
    end
    local ext = path:match("%.([^%.]+)$")
    return false,
      string.format("Unsupported file type: .%s (supported: %s)", ext or "unknown", table.concat(supported_exts, ", "))
  end

  local types = build_attachment_types()
  local type_info = types[attachment_type]
  local max_size = type_info.max_size_mb * 1024 * 1024
  if stat.size > max_size then
    return false,
      string.format(
        "File too large: %.2fMB (max %dMB for %s)",
        stat.size / 1024 / 1024,
        type_info.max_size_mb,
        attachment_type
      )
  end

  return true, nil
end

---Base64 encode the given attachment and generate the corresponding mimetype
---@param attachment CodeCompanion.Attachment
---@return CodeCompanion.Attachment|string The encoded attachment or error message
function M.encode_attachment(attachment)
  if attachment.source == "url" then
    return attachment -- URLs don't need encoding
  end

  if attachment.source == "file" then
    return attachment -- Files API references don't need encoding
  end

  if attachment.base64 then
    return attachment -- Already encoded
  end

  local path = attachment.path
  local ok, err = validate_attachment(path)
  if not ok then
    return assert(err, "validate_attachment must return error message when ok is false")
  end

  -- Read and encode file
  local b64_content, b64_err = files_utils.base64_encode_file(path)
  if b64_err then
    return b64_err
  end

  attachment.base64 = assert(b64_content, "base64_encode_file must return content when no error")

  -- Get MIME type (uses files_utils first, then attachment-specific fallback)
  if not attachment.mimetype then
    attachment.mimetype = get_mimetype(path)
  end

  attachment.source = "base64"
  return attachment
end

---@class (private) CodeCompanion.Attachment.Preprocessor.Context
---@field chat_bufnr integer?

---@alias CodeCompanion.Attachment.Preprocessor
--- | fun(source: string, ctx: CodeCompanion.Attachment.Preprocessor.Context?, cb: fun(result: string|CodeCompanion.Attachment)):nil
--- | fun(source: string, ctx: CodeCompanion.Attachment.Preprocessor.Context?, cb: nil): string|CodeCompanion.Attachment

---Load attachment from file path
---@type CodeCompanion.Attachment.Preprocessor
function M.from_path(path, _, cb)
  -- Validate the attachment
  local ok, err = validate_attachment(path)
  if not ok then
    local error_msg = assert(err, "validate_attachment must return error message when ok is false")
    if type(cb) == "function" then
      return vim.schedule(function()
        cb(error_msg)
      end)
    end
    return error_msg
  end

  -- Expand to full path
  local full_path = vim.fn.expand(path)

  -- Determine attachment type
  local attachment_type = detect_attachment_type(full_path)

  -- Get MIME type (uses files_utils first, then attachment-specific fallback)
  local mimetype = get_mimetype(full_path)

  -- Create attachment object
  ---@type CodeCompanion.Attachment
  local attachment = {
    path = full_path,
    id = full_path,
    mimetype = mimetype,
    source = "base64",
    attachment_type = attachment_type,
  }

  if type(cb) == "function" then
    return vim.schedule(function()
      cb(attachment)
    end)
  end
  return attachment
end

---Load attachment from URL
---@type CodeCompanion.Attachment.Preprocessor
function M.from_url(url, ctx, cb)
  ctx = ctx or {}

  -- Try to detect attachment type from URL
  local attachment_type = detect_attachment_type(url)

  -- If it's an image, download it
  if attachment_type == "image" then
    local loc = vim.fn.tempname()
    temp_files[#temp_files + 1] = loc

    -- initialise with the default error message
    ---@type string|CodeCompanion.Attachment
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
        if extmark_id then
          extmark_id = nil
          vim.schedule(function()
            ui_utils.clear_notification(ctx.chat_bufnr, { namespace = ns })
          end)
        end
        if response.status < 200 or response.status >= 300 then
          result = string.format("Could not get the image from %s. Status code: %d", url, response.status)
        else
          result = M.from_path(loc)
        end
        if type(cb) == "function" then
          vim.schedule(function()
            cb(result)
          end)
        end
      end,
    })
    if type(cb) ~= "function" then
      job:sync()
      return result
    end
  else
    -- For documents, validate URL points to a supported type
    local types = build_attachment_types()
    local has_supported_ext = false
    for type_name, type_info in pairs(types) do
      for _, ext in ipairs(type_info.extensions) do
        if url:match("%." .. ext .. "$") or url:match("%." .. ext .. "%?") then
          has_supported_ext = true
          attachment_type = type_name
          break
        end
      end
      if has_supported_ext then
        break
      end
    end

    if not has_supported_ext then
      local supported_exts = {}
      for _, type_info in pairs(types) do
        vim.list_extend(supported_exts, type_info.extensions)
      end
      local err_msg =
        string.format("URL must point to a supported attachment type (%s)", table.concat(supported_exts, ", "))
      if type(cb) == "function" then
        return vim.schedule(function()
          cb(err_msg)
        end)
      end
      return err_msg
    end

    -- For URLs to documents, we can pass directly to the API without downloading
    ---@type CodeCompanion.Attachment
    local attachment = {
      source = "url",
      url = url,
      id = url,
      path = "",
      attachment_type = attachment_type,
    }

    if type(cb) == "function" then
      return vim.schedule(function()
        cb(attachment)
      end)
    end
    return attachment
  end
end

---Get attachment info for display
---@param attachment CodeCompanion.Attachment
---@return string
function M.get_attachment_info(attachment)
  local type_label = attachment.attachment_type or "Attachment"
  if attachment.source == "url" then
    return string.format("%s: %s", type_label, attachment.url)
  elseif attachment.source == "file" then
    return string.format("%s: file_id=%s", type_label, attachment.file_id)
  else
    local filename = vim.fn.fnamemodify(attachment.path, ":t")
    return string.format("%s: %s", type_label, filename)
  end
end

return M
