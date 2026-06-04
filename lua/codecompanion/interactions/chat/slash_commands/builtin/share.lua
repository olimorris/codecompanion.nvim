local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local fmt = string.format

local CONSTANTS = {
  GIST_API_URL = "https://api.github.com/gists",
  NAME = "Share",
}

---Post content to the GitHub Gist API
---@param opts { token: string, description: string, filename: string, content: string }
---@param callback fun(err: string|nil, url: string|nil)
local function create_gist(opts, callback)
  local payload = vim.json.encode({
    description = opts.description,
    files = {
      [opts.filename] = {
        content = opts.content,
      },
    },
    public = false,
  })

  vim.system({
    "curl",
    "--silent",
    "--request",
    "POST",
    "--header",
    "Accept: application/vnd.github+json",
    "--header",
    fmt("Authorization: Bearer %s", opts.token),
    "--header",
    "X-GitHub-Api-Version: 2022-11-28",
    "--data",
    payload,
    CONSTANTS.GIST_API_URL,
  }, { text = true }, function(result)
    if result.code ~= 0 then
      return callback(fmt("curl exited with code %d: %s", result.code, result.stderr))
    end

    local ok, response = pcall(vim.json.decode, result.stdout)
    if not ok or not response then
      return callback("Failed to parse GitHub API response")
    end

    if response.message then
      return callback(fmt("GitHub API error: %s", response.message))
    end

    if not response.html_url then
      return callback("No URL returned in GitHub API response")
    end

    callback(nil, response.html_url)
  end)
end

---@class CodeCompanion.SlashCommand.Share: CodeCompanion.SlashCommand
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
---@return nil
function SlashCommand:execute()
  local token = self.config.opts and self.config.opts.token

  if not token or #token == 0 then
    return log:error(
      "No GitHub token found. Set `opts.token` in your config to a personal access token with the `gist` scope"
    )
  end

  local lines = vim.api.nvim_buf_get_lines(self.Chat.bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  if #vim.trim(content) == 0 then
    return utils.notify("No visible content to share", vim.log.levels.WARN)
  end

  local default_description = self.Chat.title or "CodeCompanion Chat"

  vim.ui.input({ default = default_description, prompt = " Gist Description " }, function(description)
    if description == nil then
      return
    end

    description = (#vim.trim(description) > 0) and description or default_description

    vim.ui.input({ default = "codecompanion-chat.md", prompt = " Gist Filename " }, function(filename)
      if filename == nil then
        return
      end

      filename = (#vim.trim(filename) > 0) and filename or "codecompanion-chat.md"

      self:output({ token = token, description = description, filename = filename, content = content })
    end)
  end)
end

---Create a private GitHub gist from the visible chat buffer content and copy the URL to the clipboard
---@param opts { token: string, description: string, filename: string, content: string }
---@return nil
function SlashCommand:output(opts)
  utils.notify("Sharing chat as a private GitHub gist...")

  create_gist(opts, function(err, url)
    vim.schedule(function()
      if err then
        return log:error("Share: %s", err)
      end

      vim.fn.setreg("+", url)
      utils.notify(fmt("Gist created and URL copied to clipboard: %s", url))
    end)
  end)
end

return SlashCommand
