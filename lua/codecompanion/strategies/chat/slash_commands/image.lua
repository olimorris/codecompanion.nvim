local Curl = require("plenary.curl")
local config = require("codecompanion.config")
local helpers = require("codecompanion.strategies.chat.helpers")
local log = require("codecompanion.utils.log")

local CONSTANTS = {
  NAME = "Image",
  PROMPT = "Images",
  IMAGE_DIRS = config.strategies.chat.slash_commands.image.opts.dirs,
  IMAGE_TYPES = config.strategies.chat.slash_commands.image.opts.filetypes,
}

---Prepares image search directories and filetypes for a single invocation.
---@return table, table|nil Returns search_dirs and filetypes
local function prepare_image_search_options()
  local current_search_dirs = { vim.fn.getcwd() } -- Start with CWD for this call

  if CONSTANTS.IMAGE_DIRS and vim.tbl_count(CONSTANTS.IMAGE_DIRS) > 0 then
    vim.list_extend(current_search_dirs, CONSTANTS.IMAGE_DIRS)
  end

  local ft = nil
  if CONSTANTS.IMAGE_TYPES and vim.tbl_count(CONSTANTS.IMAGE_TYPES) > 0 then
    ft = CONSTANTS.IMAGE_TYPES
  end

  return current_search_dirs, ft
end

local providers = {
  ---The default provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  default = function(SlashCommand)
    local dirs, ft = prepare_image_search_options()

    local default = require("codecompanion.providers.slash_commands.default")
    default = default
      .new({
        output = function(selection)
          SlashCommand:output(selection)
        end,
        SlashCommand = SlashCommand,
        title = CONSTANTS.PROMPT,
      })
      :images(dirs, ft)
      :display()
  end,

  ---The Snacks.nvim provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  snacks = function(SlashCommand)
    local snacks = require("codecompanion.providers.slash_commands.snacks")
    snacks = snacks.new({
      output = function(selection)
        return SlashCommand:output({
          relative_path = selection.file,
          path = selection.file,
        })
      end,
    })

    local dirs, ft = prepare_image_search_options()

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
        return SlashCommand:output({
          path = selection[1],
        })
      end,
    })

    local dirs, img_fts = prepare_image_search_options()
    local find_command = { "fd", "--type", "f", "--follow", "--hidden" }
    for _, ext in ipairs(img_fts) do
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
}

-- The different choices the user has to insert an image via a slash command
local choice = {
  ---Load the file picker
  ---@param SlashCommand CodeCompanion.SlashCommand.Image
  ---@param SlashCommands CodeCompanion.SlashCommands
  ---@return nil
  File = function(SlashCommand, SlashCommands)
    return SlashCommands:set_provider(SlashCommand, providers)
  end,
  ---Share the URL of an image
  ---@param SlashCommand CodeCompanion.SlashCommand.Image
  ---@return nil
  URL = function(SlashCommand, _)
    return vim.ui.input({ prompt = "Enter the URL: " }, function(url)
      if #vim.trim(url or "") == 0 then
        return
      end

      if vim.fn.executable("base64") == 0 then
        return log:warn("The `base64` command could not be found")
      end

      -- Download the image to a temporary directory
      local loc = vim.fn.tempname()
      local response
      local curl_ok, curl_payload = pcall(function()
        response = Curl.get(url, {
          insecure = config.adapters.opts.allow_insecure,
          proxy = config.adapters.opts.proxy,
          output = loc,
        })
      end)
      if not curl_ok then
        vim.loop.fs_unlink(loc)
        return log:error("Failed to execute curl: %s", tostring(curl_payload))
      end

      -- Check if the response is valid
      if not response or (response.status and response.status >= 400) then
        local err_msg = "Could not download the image."
        if response and response.status then
          err_msg = err_msg .. " HTTP Status: " .. response.status
        end
        if response and response.body and #response.body > 0 then
          err_msg = err_msg .. "\nServer response: " .. response.body:sub(1, 200)
        end
        vim.loop.fs_unlink(loc)
        return log:error(err_msg)
      end

      -- Fetch the MIME type from headers
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

      return SlashCommand:output({
        id = url,
        path = loc,
        mimetype = mimetype,
      })
    end)
  end,
}

---@class CodeCompanion.SlashCommand.Image: CodeCompanion.SlashCommand
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
  vim.ui.select({ "URL", "File" }, {
    prompt = "Select an image source",
  }, function(selected)
    if not selected then
      return
    end
    return choice[selected](self, SlashCommands)
  end)
end

---Put a reference to the image in the chat buffer
---@param selected table The selected image { source = string, path = string }
---@param opts? table
---@return nil
function SlashCommand:output(selected, opts)
  local encoded_image = helpers.encode_image(selected)
  if type(encoded_image) == "string" then
    return log:error("Could not encode image: %s", encoded_image)
  end
  return helpers.add_image(self.Chat, selected)
end

---Is the slash command enabled?
---@param chat CodeCompanion.Chat
---@return boolean,string
function SlashCommand.enabled(chat)
  return chat.adapter.opts.vision, "The image Slash Command is not enabled for this adapter"
end

return SlashCommand
