local buf_utils = require("codecompanion.utils.buffers")
local file_utils = require("codecompanion.utils.files")

local M = {}

---Write a full-text replacement to path
---@param path string The file path to write to
---@param content string The full content to write to the file
---@return boolean|nil,string|nil The outcome followed by error message on nil
function M.write_text_file(path, content)
  -- Try to find an existing buffer for the path
  local bufnr = buf_utils.get_bufnr_from_filepath(path)
  if bufnr then
    local ok, err = pcall(function()
      buf_utils.write(bufnr, content)
    end)
    if not ok then
      return nil, ("Buffer write failed for %s: %s"):format(path, tostring(err))
    end
    return true
  end

  -- Otherwise, it's a file
  local ok, err = pcall(function()
    file_utils.write_to_path(path, content)
  end)
  if not ok then
    return nil, ("File write failed for %s: %s"):format(path, tostring(err))
  end
  return true
end

return M
