local M = {}

---Base64 encode a given file using the `base64` command.
---@param path string The path to the file to encode
---@return string?, string? The output and error message
function M.encode_file(path)
  local _f, err_name, err_msg = vim.uv.fs_open(path, "rs", 438)
  if _f then
    local stat = assert(vim.uv.fs_stat(path))
    local content, err = vim.uv.fs_read(_f, stat.size, nil)
    vim.uv.fs_close(_f)
    if content then
      local ok, res = pcall(vim.base64.encode, content)
      if ok then
        return res, nil
      else
        return nil, "Could not base64-encode the file: " .. path
      end
    else
      return nil, string.format("Could not load the file: %s\nError: %s", path, err)
    end
  end

  local _err = string.format("Could not open the file: %s", path)
  if err_name or err_msg then
    _err = _err .. string.format("\n%s: %s", err_name or "Unknown error", err_msg or "")
  end
  return nil, _err
end

return M
