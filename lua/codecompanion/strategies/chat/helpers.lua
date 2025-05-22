local base64 = require("codecompanion.utils.base64")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local M = {}

---Format the given role without any separator
---@param role string
---@return string
function M.format_role(role)
  if config.display.chat.show_header_separator then
    role = vim.trim(role:gsub(config.display.chat.separator, ""))
  end
  return role
end

---Strip any references from the messages
---@param messages table
---@return table
function M.strip_references(messages)
  local i = 1
  while messages[i] and messages[i]:sub(1, 1) == ">" do
    table.remove(messages, i)
    -- we do not increment i, since removing shifts everything down
  end
  return messages
end

---Get the keymaps from the slash commands
---@param slash_commands table
---@return table
function M.slash_command_keymaps(slash_commands)
  local keymaps = {}
  for k, v in pairs(slash_commands) do
    if v.keymaps then
      keymaps[k] = {}
      keymaps[k].description = v.description
      keymaps[k].callback = "keymaps." .. k
      keymaps[k].modes = v.keymaps.modes
    end
  end

  return keymaps
end

---Base64 encode the given image
---@param image table The image object containing the path and other metadata.
---@return {base64: string, mimetype: string}|string The base64 encoded image string
function M.encode_image(image)
  local b64_content, b64_err = base64.encode(image.path)
  if b64_err then
    return b64_err
  end

  image.base64 = b64_content

  if not image.mimetype then
    image.mimetype = base64.get_mimetype(image.path)
  end

  return image
end

---Add an image to the chat buffer
---@param Chat CodeCompanion.Chat The chat instance
---@param image table The image object containing the path and other metadata
---@param opts table Options for adding the image
---@return nil
function M.add_image(Chat, image, opts)
  opts = opts or {}

  local id = "<image>" .. (image.id or image.path) .. "</image>"

  Chat:add_message({
    role = opts.role or config.constants.USER_ROLE,
    content = image.base64,
  }, { reference = id, mimetype = image.mimetype, tag = "image", visible = false })

  Chat.references:add({
    bufnr = opts.bufnr or image.bufnr,
    id = id,
    path = image.path,
    source = opts.source or "codecompanion.strategies.chat.slash_commands.image",
  })
end

return M
