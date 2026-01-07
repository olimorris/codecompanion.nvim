local files_utils = require("codecompanion.utils.files")

local M = {}

local CONSTANTS = {
  MAX_SIZE_MB = 32,
  SUPPORTED_TYPES = {
    pdf = "application/pdf",
    rtf = "text/rtf",
    xslx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    csv = "text/csv",
    docx = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  },
}

---@class (private) CodeCompanion.Document
---@field id string
---@field path string
---@field bufnr? integer
---@field base64? string
---@field media_type? string
---@field source? string "base64"|"url"|"file"
---@field url? string
---@field file_id? string

---Validate document file
---@param path string
---@return boolean success, string? error_message
local function validate_document(path)
  local stat = vim.loop.fs_stat(path)
  if not stat then
    return false, "File does not exist"
  end

  -- Check file size (32MB limit per Anthropic API)
  local max_size = CONSTANTS.MAX_SIZE_MB * 1024 * 1024
  if stat.size > max_size then
    return false, string.format("File too large: %.2fMB (max %dMB)", stat.size / 1024 / 1024, CONSTANTS.MAX_SIZE_MB)
  end

  -- Check file extension
  local ext = path:match("%.([^%.]+)$")
  if ext then
    ext = ext:lower()
  end
  if not ext or not CONSTANTS.SUPPORTED_TYPES[ext] then
    return false,
      string.format(
        "Unsupported file type: .%s (supported: %s)",
        ext or "unknown",
        table.concat(vim.tbl_keys(CONSTANTS.SUPPORTED_TYPES), ", ")
      )
  end

  return true, nil
end

---Base64 encode the given document and generate the corresponding media_type
---@param document CodeCompanion.Document
---@return CodeCompanion.Document|string The encoded document or error message
function M.encode_document(document)
  if document.source == "url" then
    return document -- URLs don't need encoding
  end

  if document.source == "file" then
    return document -- Files API references don't need encoding
  end

  if document.base64 then
    return document -- Already encoded
  end

  local path = document.path
  local ok, err = validate_document(path)
  if not ok then
    return assert(err, "validate_document must return error message when ok is false")
  end

  -- Read and encode file
  local b64_content, b64_err = files_utils.base64_encode_file(path)
  if b64_err then
    return b64_err
  end

  document.base64 = assert(b64_content, "base64_encode_file must return content when no error")

  if not document.media_type then
    local ext = path:match("%.([^%.]+)$")
    if ext then
      ext = ext:lower()
      document.media_type = CONSTANTS.SUPPORTED_TYPES[ext] or "application/octet-stream"
    end
  end

  document.source = "base64"
  return document
end

---@class (private) CodeCompanion.Document.Preprocessor.Context
---@field chat_bufnr integer?

---@alias CodeCompanion.Document.Preprocessor
--- | fun(source: string, ctx: CodeCompanion.Document.Preprocessor.Context?, cb: fun(result: string|CodeCompanion.Document)):nil
--- | fun(source: string, ctx: CodeCompanion.Document.Preprocessor.Context?, cb: nil): string|CodeCompanion.Document

---Load document from file path
---@type CodeCompanion.Document.Preprocessor
function M.from_path(path, _, cb)
  -- Validate the document
  local ok, err = validate_document(path)
  if not ok then
    local error_msg = assert(err, "validate_document must return error message when ok is false")
    if type(cb) == "function" then
      return vim.schedule(function()
        cb(error_msg)
      end)
    end
    return error_msg
  end

  -- Expand to full path
  local full_path = vim.fn.expand(path)

  -- Extract extension and set media_type
  local ext = full_path:match("%.([^%.]+)$")
  local media_type = "application/octet-stream" -- default fallback
  if ext then
    ext = ext:lower()
    media_type = CONSTANTS.SUPPORTED_TYPES[ext] or media_type
  end

  -- Create document object
  ---@type CodeCompanion.Document
  local document = {
    path = full_path,
    id = full_path,
    media_type = media_type,
    source = "base64",
  }

  if type(cb) == "function" then
    return vim.schedule(function()
      cb(document)
    end)
  end
  return document
end

---Load document from URL
---@type CodeCompanion.Document.Preprocessor
function M.from_url(url, ctx, cb)
  ctx = ctx or {}

  -- Validate URL points to a supported document type
  local has_supported_ext = false
  for ext, _ in pairs(CONSTANTS.SUPPORTED_TYPES) do
    if url:match("%." .. ext .. "$") or url:match("%." .. ext .. "%?") then
      has_supported_ext = true
      break
    end
  end

  if not has_supported_ext then
    local supported = table.concat(vim.tbl_keys(CONSTANTS.SUPPORTED_TYPES), ", ")
    local err_msg = string.format("URL must point to a supported document type (%s)", supported)
    if type(cb) == "function" then
      return vim.schedule(function()
        cb(err_msg)
      end)
    end
    return err_msg
  end

  -- For URLs, we can pass directly to the API without downloading
  ---@type CodeCompanion.Document
  local document = {
    source = "url",
    url = url,
    id = url,
    path = "", -- Required by CodeCompanion.Document class
  }

  if type(cb) == "function" then
    return vim.schedule(function()
      cb(document)
    end)
  end
  return document
end

---Get document info for display
---@param document CodeCompanion.Document
---@return string
function M.get_document_info(document)
  if document.source == "url" then
    return string.format("Document: %s", document.url)
  elseif document.source == "file" then
    return string.format("Document: file_id=%s", document.file_id)
  else
    local filename = vim.fn.fnamemodify(document.path, ":t")
    return string.format("Document: %s", filename)
  end
end

return M
