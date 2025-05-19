local Job = require("plenary.job")

local M = {}

---Base64 encode a given file using the `base64` command.
---@param filepath string The path to the file to encode
---@return string?, string? The output and error message
function M.encode(filepath)
  if vim.fn.executable("base64") == 0 then
    return nil, "Could not find the `base64` command."
  end

  local args
  local os = vim.loop.os_uname()
  if os and os.sysname == "Darwin" then
    args = { "-i", filepath }
  elseif os and os.sysname == "Linux" then
    args = { "-w", "0", filepath }
  else
    args = { filepath }
  end

  local job = Job:new({
    command = "base64",
    args = args,
    enable_recording = true,
  })

  local sync_ok, sync_payload = pcall(function()
    job:sync(3000) -- Timeout after 3 seconds
  end)

  if not sync_ok then
    return nil, "base64 encoding failed or timed out: " .. tostring(sync_payload)
  end

  if job.code == 0 then
    local stdout_results = job:result()
    local b64_content = nil
    if stdout_results and #stdout_results > 0 then
      b64_content = table.concat(stdout_results, "")
      b64_content = vim.trim(b64_content)
    end
    if b64_content and #b64_content > 0 then
      return b64_content, nil
    else
      return nil, "base64 encoding produced empty output."
    end
  else
    local stderr_msg = ""
    if job:stderr_result() and #(job:stderr_result()) > 0 then
      stderr_msg = ": " .. table.concat(job:stderr_result(), " ")
    end
    return nil, "Could not base64 encode image (code " .. tostring(job.code) .. ")" .. stderr_msg
  end
end

---Get the mimetype from the given file
---@param filepath string The path to the file
---@return string
function M.get_mimetype(filepath)
  local map = {
    gif = "image/gif",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    png = "image/png",
    webp = "image/webp",
  }

  local extension = vim.fn.fnamemodify(filepath, ":e")
  extension = extension:lower()

  return map[extension]
end

return M
