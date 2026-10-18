local config = require("codecompanion.config")
local files_utils = require("codecompanion.utils.files")
local helpers = require("codecompanion.interactions.chat.helpers")
local image_utils = require("codecompanion.utils.images")
local log = require("codecompanion.utils.log")
local picker = require("codecompanion.providers.slash_commands.picker")
local tags = require("codecompanion.interactions.shared.tags")
local utils = require("codecompanion.utils")

local fmt = string.format

local CONSTANTS = {
  NAME = "File",
  PROMPT = "Select file(s)",
  IMAGE_MIMETYPES = { "image/gif", "image/jpeg", "image/png", "image/webp" },
}

local providers = picker.build_file_pickers({ prompt = CONSTANTS.PROMPT })

---@class CodeCompanion.SlashCommand.File: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
    opts = args.opts,
  }, { __index = SlashCommand })

  return self
end

---Execute the slash command (backwards compatible, delegates to chat_render)
---@param SlashCommands CodeCompanion.SlashCommands
---@return nil
function SlashCommand:execute(SlashCommands)
  return self:chat_render(SlashCommands)
end

---Render the slash command for the chat interaction
---@param SlashCommands CodeCompanion.SlashCommands
---@return nil
function SlashCommand:chat_render(SlashCommands)
  return SlashCommands:set_provider(self, providers)
end

---Render the slash command for the CLI interaction
---@param slash_config table The slash command config from config.lua
---@param callback fun(paths: string[]) Called with a table of relative file paths
---@return nil
function SlashCommand.cli_render(slash_config, callback)
  if not config.can_send_code() and (slash_config.opts and slash_config.opts.contains_code) then
    log:warn("Sending of code has been disabled")
    return
  end

  local SlashCommands = require("codecompanion.interactions.chat.slash_commands").new()
  SlashCommands:set_provider({
    config = slash_config,
    output = function(_, selected)
      local path = vim.fn.fnamemodify(selected.path, ":.")
      callback({ path })
    end,
  }, providers)
end

---@class CodeCompanion.SlashCommand.File.Selected
---@field path string
---@field id? string
---@field name? string
---@field mimetype? string
---@field description? string

---How a file is shown to the user and the LLM
---@param selected CodeCompanion.SlashCommand.File.Selected
---@return string
local function get_name(selected)
  return selected.name or vim.fn.fnamemodify(selected.path, ":.")
end

---Identify a file in the chat's context, which is never sent to the LLM
---@param selected CodeCompanion.SlashCommand.File.Selected
---@return string
local function get_id(selected)
  return selected.id or get_name(selected)
end

---@param slash_command CodeCompanion.SlashCommand.File
---@return boolean
local function is_code_blocked(slash_command)
  if not config.can_send_code() and (slash_command.config.opts and slash_command.config.opts.contains_code) then
    log:warn("Sending of code has been disabled")
    return true
  end
  return false
end

---Base64 encode an image and add it to the chat buffer for adapters that support vision
---@param selected CodeCompanion.SlashCommand.File.Selected
---@param opts { mimetype: string, silent?: boolean }
---@return boolean attached
function SlashCommand:output_image(selected, opts)
  local filename = vim.fn.fnamemodify(get_name(selected), ":t")

  if not vim.tbl_contains(CONSTANTS.IMAGE_MIMETYPES, opts.mimetype) then
    log:warn("`%s` is not a supported image type", filename)
    return false
  end

  local adapter = self.Chat.adapter
  if not (adapter.opts and adapter.opts.vision) then
    log:warn(
      "The `%s` adapter does not support images. `%s` was not added to the chat",
      adapter.formatted_name,
      filename
    )
    return false
  end

  local image = image_utils.encode_image({ path = selected.path, id = get_id(selected), mimetype = opts.mimetype })
  if type(image) == "string" then
    log:error("Could not encode image: %s", image)
    return false
  end

  self.Chat:add_image_message(image, {
    source = "codecompanion.interactions.shared.slash_commands.file",
  })

  if not opts.silent then
    utils.notify(fmt("Added the `%s` image to the chat", filename))
  end

  return true
end

---Base64 encode a document and add it to the chat buffer for adapters that support documents
---@param selected CodeCompanion.SlashCommand.File.Selected
---@param opts { mimetype: string, silent?: boolean, sync_all?: boolean }
---@return boolean attached
function SlashCommand:output_pdf(selected, opts)
  if is_code_blocked(self) then
    return false
  end

  local filename = vim.fn.fnamemodify(get_name(selected), ":t")

  local adapter = self.Chat.adapter
  if not (adapter.opts and adapter.opts.documents) then
    log:warn(
      "The `%s` adapter does not support documents. `%s` was not added to the chat",
      adapter.formatted_name,
      filename
    )
    return false
  end

  local base64, err = files_utils.base64_encode_file(selected.path)
  if err then
    log:error(err)
    return false
  end

  local id = "<file>" .. get_id(selected) .. "</file>"

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = base64,
  }, {
    visible = false,
    context = { id = id, mimetype = opts.mimetype, path = selected.path },
    _meta = { tag = tags.DOCUMENT, filetype = "pdf" },
  })

  if opts.sync_all then
    return true
  end

  self.Chat.context:add({
    id = id,
    path = selected.path,
    source = "codecompanion.interactions.shared.slash_commands.file",
  })

  if not opts.silent then
    utils.notify(fmt("Added the `%s` document to the chat", filename))
  end

  return true
end

---Add the contents of a file to the chat buffer as text
---@param selected CodeCompanion.SlashCommand.File.Selected
---@param opts { message?: string, silent?: boolean, sync_all?: boolean }
---@return boolean attached
function SlashCommand:output_text(selected, opts)
  if is_code_blocked(self) then
    return false
  end

  local file = helpers.format_file_for_llm(selected.path, { message = opts.message, name = selected.name })
  local id = "<file>" .. get_id(selected) .. "</file>"

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = file.content or "",
  }, {
    visible = false,
    context = { id = id, path = selected.path },
    _meta = { tag = tags.FILE },
  })

  if opts.sync_all then
    return true
  end

  self.Chat.context:add({
    id = id,
    path = selected.path,
    source = "codecompanion.interactions.shared.slash_commands.file",
  })

  if not opts.silent then
    utils.notify(fmt("Added the `%s` file to the chat", vim.fn.fnamemodify(get_name(selected), ":t")))
  end

  return true
end

---Files that are sent as attachments rather than text, matched in order against their mimetype
local ATTACHMENTS = {
  { mimetype = "^application/pdf$", output = SlashCommand.output_pdf },
  { mimetype = "^image/", output = SlashCommand.output_image },
}

---Output from the slash command in the chat buffer
---@param selected CodeCompanion.SlashCommand.File.Selected
---@param opts? { message?: string, description?: string, silent?: boolean, sync_all?: boolean }
---@return boolean attached
function SlashCommand:output(selected, opts)
  opts = opts or {}

  local mimetype = selected.mimetype or files_utils.get_mimetype(selected.path)
  for _, attachment in ipairs(ATTACHMENTS) do
    if mimetype and mimetype:match(attachment.mimetype) then
      return attachment.output(self, selected, vim.tbl_extend("force", opts, { mimetype = mimetype }))
    end
  end

  if selected.description then
    opts.message = selected.description
  end

  return self:output_text(selected, opts)
end

return SlashCommand
