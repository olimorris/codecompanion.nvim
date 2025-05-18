local Curl = require("plenary.curl")
local Job = require("plenary.job")
local config = require("codecompanion.config")
local util = require("codecompanion.utils")

local CONSTANTS = {
  NAME = "Image",
  PROMPT = "Select an image(s)",
}

local providers = {
  ---The default provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  default = function(SlashCommand)
    local default = require("codecompanion.providers.slash_commands.default")
    default = default
      .new({
        output = function(selection)
          SlashCommand:output(selection)
        end,
        SlashCommand = SlashCommand,
        title = CONSTANTS.PROMPT,
      })
      :buffers()
      :display()
  end,

  ---The Snacks.nvim provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  snacks = function(SlashCommand)
    local snacks = require("codecompanion.providers.slash_commands.snacks")
    snacks = snacks.new({
      title = CONSTANTS.PROMPT .. ": ",
      output = function(selection)
        return SlashCommand:output({
          bufnr = selection.buf,
          name = vim.fn.bufname(selection.buf),
          path = selection.file,
        })
      end,
    })

    snacks.provider.picker.pick({
      source = "buffers",
      prompt = snacks.title,
      confirm = snacks:display(),
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
          bufnr = selection.bufnr,
          name = selection.filename,
          path = selection.path,
        })
      end,
    })

    telescope.provider.buffers({
      prompt_title = telescope.title,
      ignore_current_buffer = true, -- Ignore the codecompanion buffer when selecting buffers
      attach_mappings = telescope:display(),
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
        return SlashCommand:output(selected)
      end,
    })

    mini_pick.provider.builtin.buffers(
      { include_current = false },
      mini_pick:display(function(selected)
        return {
          bufnr = selected.bufnr,
          name = selected.text,
          path = selected.text,
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
        return SlashCommand:output(selected)
      end,
    })

    fzf.provider.buffers(fzf:display(function(selected, opts)
      local file = fzf.provider.path.entry_to_file(selected, opts)
      return {
        bufnr = file.bufnr,
        name = file.path,
        path = file.bufname,
      }
    end))
  end,
}

-- The different choices the user has to insert an image via a slash command
local choice = {
  ---Share the URL of an image
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  URL = function(SlashCommand)
    return vim.ui.input({ prompt = "Enter the URL: " }, function(input)
      if #vim.trim(input or "") == 0 then
        return
      end

      if vim.fn.executable("base64") == 0 then
        return util.notify("The `base64` command could not be found", vim.log.levels.ERROR)
      end

      -- Download the image to a temporary directory
      local loc = vim.fn.tempname()
      local response
      local curl_ok, curl_payload = pcall(function()
        response = Curl.get(input, { output = loc })
      end)
      if not curl_ok then
        vim.loop.fs_unlink(loc) -- Clean up temp file if it was created
        return util.notify("Failed to execute curl: " .. tostring(curl_payload), vim.log.levels.ERROR)
      end

      -- Check if the response is valid
      if not response or (response.status and response.status >= 400) then
        local err_msg = "Could not download the image."
        if response and response.status then
          err_msg = err_msg .. " HTTP Status: " .. response.status
        end
        if response and response.body and #response.body > 0 then
          err_msg = err_msg .. "\nServer response: " .. response.body:sub(1, 200) -- Show a snippet
        end
        vim.loop.fs_unlink(loc) -- Clean up the downloaded file, as it might be an error page or empty
        return util.notify(err_msg, vim.log.levels.ERROR)
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

      -- Determine the user's OS to set the correct args
      local args
      local uname_info = vim.loop.os_uname()
      if uname_info and uname_info.sysname == "Darwin" then -- macOS
        args = { "-i", loc }
      elseif uname_info and uname_info.sysname == "Linux" then -- Linux
        args = { "-w", "0", loc }
      else
        args = { loc }
      end

      -- Base64 encode the image
      local job = Job:new({
        command = "base64",
        args = args,
        on_exit = function(data, code)
          vim.schedule(function()
            if code == 0 then
              local base64_content = nil
              if data._stdout_results and #data._stdout_results > 0 then
                base64_content = table.concat(data._stdout_results, "")
                base64_content = vim.trim(base64_content)
              end

              local selected = {
                source = "image_url",
                path = input,
                mimetype = mimetype,
                base64 = base64_content,
              }
              return SlashCommand:output(selected)
            else
              util.notify("Could not base64 encode the image", vim.log.levels.ERROR)
            end
            vim.loop.fs_unlink(loc)
          end)
        end,
      })
      job:start()
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
    return choice[selected](self)
  end)
end

---Put a reference to the image in the chat buffer
---@param selected table The selected image { source = string, path = string }
---@param opts? table
---@return nil
function SlashCommand:output(selected, opts)
  local id = "<image>" .. selected.path .. "</image>"
  local image = selected.path

  self.Chat:add_message({
    role = config.constants.USER_ROLE,
    content = image,
  }, { reference = id, base64 = selected.base64, mimetype = selected.mimetype, tag = "image", visible = false })

  self.Chat.references:add({
    bufnr = selected.bufnr,
    id = id,
    path = selected.path,
    source = "codecompanion.strategies.chat.slash_commands.image",
  })
end

return SlashCommand
