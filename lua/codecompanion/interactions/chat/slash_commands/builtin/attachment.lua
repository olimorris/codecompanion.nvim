local attachment_utils = require("codecompanion.utils.attachments")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")

local CONSTANTS = {
  NAME = "Attachment",
  PROMPT = "Select attachment(s)",
}

---Get all supported extensions for file picker
---@return string[] List of extensions
local function get_all_extensions()
  local exts = {}
  local ext_map = attachment_utils.get_supported_extensions()
  for ext, _ in pairs(ext_map) do
    table.insert(exts, ext)
  end
  return exts
end

---Prepares attachment search directories
---@return table Search directories
local function prepare_search_dirs()
  local search_dirs = {}

  -- Include attachment dirs if configured
  local attachment_dirs = config.interactions.chat.slash_commands.attachment
    and config.interactions.chat.slash_commands.attachment.opts
    and config.interactions.chat.slash_commands.attachment.opts.dirs
  if attachment_dirs and vim.tbl_count(attachment_dirs) > 0 then
    vim.list_extend(search_dirs, attachment_dirs)
  end

  -- Include image dirs if configured (for backwards compat)
  local image_dirs = config.interactions.chat.slash_commands.image
    and config.interactions.chat.slash_commands.image.opts
    and config.interactions.chat.slash_commands.image.opts.dirs
  if image_dirs and vim.tbl_count(image_dirs) > 0 then
    vim.list_extend(search_dirs, image_dirs)
  end

  return search_dirs
end

local providers = {
  ---The default provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  default = function(SlashCommand)
    local dirs = prepare_search_dirs()
    local ft = get_all_extensions()

    local default = require("codecompanion.providers.slash_commands.default")
    default = default
      .new({
        output = function(selection)
          local _res = attachment_utils.from_path(selection.path, { chat_bufnr = SlashCommand.Chat.bufnr })
          if type(_res) == "string" then
            return log:error(_res)
          end
          return SlashCommand:output(_res)
        end,
        SlashCommand = SlashCommand,
        title = CONSTANTS.PROMPT,
      })
      :documents(dirs, ft)
      :display()
  end,

  ---The Snacks.nvim provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  snacks = function(SlashCommand)
    local snacks = require("codecompanion.providers.slash_commands.snacks")
    snacks = snacks.new({
      output = function(selection)
        local path = selection.file or selection
        local _res = attachment_utils.from_path(path, { chat_bufnr = SlashCommand.Chat.bufnr })
        if type(_res) == "string" then
          return log:error(_res)
        end
        return SlashCommand:output(_res)
      end,
    })

    local dirs = prepare_search_dirs()
    local ft = get_all_extensions()

    snacks.provider.picker.pick("files", {
      confirm = snacks:display(),
      dirs = dirs,
      ft = ft,
      main = { file = false, float = true },
    })
  end,

  ---The Telescope provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  telescope = function(SlashCommand)
    local telescope = require("codecompanion.providers.slash_commands.telescope")
    telescope = telescope.new({
      title = CONSTANTS.PROMPT,
      output = function(selection)
        local path = selection[1] or selection
        local _res = attachment_utils.from_path(path, { chat_bufnr = SlashCommand.Chat.bufnr })
        if type(_res) == "string" then
          return log:error(_res)
        end
        return SlashCommand:output(_res)
      end,
    })

    local dirs = prepare_search_dirs()
    local exts = get_all_extensions()
    local find_command = { "fd", "--type", "f", "--follow", "--hidden" }
    for _, ext in ipairs(exts) do
      table.insert(find_command, "--extension")
      table.insert(find_command, ext)
    end

    telescope.provider.find_files({
      find_command = find_command,
      prompt_title = telescope.title,
      attach_mappings = telescope:display(),
      search_dirs = dirs,
    })
  end,

  ---The Mini.Pick provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  mini_pick = function(SlashCommand)
    local mini_pick = require("codecompanion.providers.slash_commands.mini_pick")
    mini_pick = mini_pick.new({
      title = CONSTANTS.PROMPT,
      output = function(selected)
        local path = selected.path or selected
        local _res = attachment_utils.from_path(path, { chat_bufnr = SlashCommand.Chat.bufnr })
        if type(_res) == "string" then
          return log:error(_res)
        end
        return SlashCommand:output(_res)
      end,
    })

    local dirs = prepare_search_dirs()
    local exts = get_all_extensions()
    local glob_pattern = "**/*.{" .. table.concat(exts, ",") .. "}"

    mini_pick.provider.builtin.files(
      { cwd = dirs[1], glob_pattern = glob_pattern },
      mini_pick:display(function(selected)
        return {
          path = selected,
        }
      end)
    )
  end,

  ---The fzf-lua provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  fzf_lua = function(SlashCommand)
    local fzf = require("codecompanion.providers.slash_commands.fzf_lua")
    fzf = fzf.new({
      title = CONSTANTS.PROMPT,
      output = function(selected)
        local file_path = type(selected) == "table" and (selected.path or selected[1]) or selected
        local _res = attachment_utils.from_path(file_path, { chat_bufnr = SlashCommand.Chat.bufnr })
        if type(_res) == "string" then
          return log:error(_res)
        end
        return SlashCommand:output(_res)
      end,
    })

    local dirs = prepare_search_dirs()
    local exts = get_all_extensions()
    local ext_pattern = "*.{" .. table.concat(exts, ",") .. "}"

    fzf.provider.files(
      fzf:display(function(selected, opts)
        local file = fzf.provider.path.entry_to_file(selected, opts)
        return {
          relative_path = file.stripped,
          path = file.path,
        }
      end),
      {
        cwd = dirs[1],
        file_icons = true,
        find_opts = ext_pattern,
      }
    )
  end,
}

local choice = {
  ---Load the file picker
  ---@param SlashCommand CodeCompanion.SlashCommand.Attachment
  ---@param SlashCommands CodeCompanion.SlashCommands
  ---@return nil
  File = function(SlashCommand, SlashCommands)
    return SlashCommands:set_provider(SlashCommand, providers)
  end,

  ---Share the URL of an attachment
  ---@param SlashCommand CodeCompanion.SlashCommand.Attachment
  ---@return nil
  URL = function(SlashCommand, _)
    return vim.ui.input({ prompt = "Enter the URL: " }, function(url)
      if #vim.trim(url or "") == 0 then
        return
      end

      attachment_utils.from_url(url, { chat_bufnr = SlashCommand.Chat.bufnr }, function(_res)
        if type(_res) == "string" then
          return log:error(_res)
        end
        SlashCommand:output(_res)
      end)
    end)
  end,

  ---Use Files API reference
  ---@param SlashCommand CodeCompanion.SlashCommand.Attachment
  ---@return nil
  ["Files API"] = function(SlashCommand, _)
    return vim.ui.input({ prompt = "Enter the file_id: " }, function(file_id)
      if #vim.trim(file_id or "") == 0 then
        return
      end

      SlashCommand:output({
        source = "file",
        file_id = file_id,
        id = file_id,
        path = "",
      })
    end)
  end,
}

---@class CodeCompanion.SlashCommand.Attachment: CodeCompanion.SlashCommand
local SlashCommand = {}

---@param args CodeCompanion.SlashCommandArgs
function SlashCommand.new(args)
  local self = setmetatable({
    Chat = args.Chat,
    config = args.config,
    context = args.context,
  }, { __index = SlashCommand })

  return self
end

---Execute the slash command
---@param SlashCommands CodeCompanion.SlashCommands
---@return nil
function SlashCommand:execute(SlashCommands)
  -- Build options based on adapter capabilities
  local options = { "File", "URL" }

  -- Only show Files API option if adapter supports it
  if self.Chat.adapter.opts and self.Chat.adapter.opts.file_api then
    table.insert(options, "Files API")
  end

  vim.ui.select(options, {
    prompt = "Select an attachment source",
  }, function(selected)
    if not selected then
      return
    end
    return choice[selected](self, SlashCommands)
  end)
end

---Add attachment to chat buffer
---@param selected CodeCompanion.Attachment
---@param opts? table
---@return nil
function SlashCommand:output(selected, opts)
  opts = opts or {}
  -- Set source to attachment command
  opts.source = "codecompanion.interactions.chat.slash_commands.attachment"

  if selected.source == "file" then
    -- Files API reference - no encoding needed
    return self.Chat:add_attachment_message(selected, opts)
  end

  local encoded_attachment = attachment_utils.encode_attachment(selected)
  if type(encoded_attachment) == "string" then
    return log:error("Could not encode attachment: %s", encoded_attachment)
  end

  -- Route to appropriate message handler based on attachment type
  if selected.attachment_type == "image" then
    return self.Chat:add_image_message(encoded_attachment, opts)
  else
    return self.Chat:add_attachment_message(encoded_attachment, opts)
  end
end

---Is the slash command enabled?
---@param chat CodeCompanion.Chat
---@return boolean, string
function SlashCommand.enabled(chat)
  -- Check if adapter supports document upload or vision
  local supports_docs = chat.adapter.opts and chat.adapter.opts.doc_upload or false
  local supports_images = chat.adapter.opts and chat.adapter.opts.vision or false

  if supports_docs or supports_images then
    return true, ""
  end

  return false, "The attachment Slash Command is not enabled for this adapter"
end

return SlashCommand
