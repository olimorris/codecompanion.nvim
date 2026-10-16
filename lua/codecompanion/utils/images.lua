local M = {}

local files_utils = require("codecompanion.utils.files")

---@class (private) CodeCompanion.Image
---@field id string
---@field path string
---@field bufnr? number
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

return M
