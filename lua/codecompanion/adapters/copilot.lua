local curl = require("plenary.curl")

local log = require("codecompanion.utils.log")
local openai = require("codecompanion.adapters.openai")

---@type string|nil
local _oauth_token

---@type string|nil
local _github_token

---Get the Copilot OAuth token from local storage
---@return string|nil
local function get_oauth_token()
  if _oauth_token then
    return _oauth_token
  end

  local config_dir
  if vim.fn.has("win32") == 1 then
    config_dir = vim.fn.expand("~/AppData/Local")
  elseif os.getenv("CODECOMPANION_TOKEN_PATH") then
    config_dir = os.getenv("CODECOMPANION_TOKEN_PATH")
  else
    local xdg_config = vim.fn.expand("$XDG_CONFIG_HOME")
    config_dir = (xdg_config and vim.fn.isdirectory(xdg_config) > 0) and xdg_config or vim.fn.expand("~/.config")
  end

  log:debug("Copilot config dir: %s", config_dir)

  local token_files = {
    "/github-copilot/hosts.json",
    "/github-copilot/apps.json",
  }

  for _, file in ipairs(token_files) do
    local path = vim.fn.expand(config_dir .. file)

    if vim.fn.filereadable(path) ~= 1 then
      log:debug("File not found: %s", path)
    end

    local f = io.open(path, "r")
    if not f then
      return log:error("Could not open file: %s", path)
    end

    local content = f:read("*all")
    f:close()

    local ok, data = pcall(vim.fn.json_decode, content)
    if not ok then
      return log:error("Could not decode JSON from file: %s", path)
    end

    if data["github.com"] then
      return data["github.com"].oauth_token
    else
      for key, value in pairs(data) do
        if key:match("^github.com:") then
          return value.oauth_token
        end
      end
    end
  end

  return nil
end

---Authorize the GitHub OAuth token
---@return string|nil
local function authorize_token()
  if _github_token then
    return _github_token
  end

  local request = curl.get("https://api.github.com/copilot_internal/v2/token", {
    headers = {
      Authorization = "Bearer " .. _oauth_token,
      ["Accept"] = "application/json",
    },
    on_error = function(err)
      log:error("GitHub Copilot token request error: %s", err)
    end,
  })

  _github_token = vim.fn.json_decode(request.body).token
  return _github_token
end

---@class CodeCompanion.AdapterArgs
return {
  name = "copilot",
  roles = {
    llm = "assistant",
    user = "user",
  },
  features = {
    text = true,
    tokens = false,
    vision = false,
  },
  url = "https://api.githubcopilot.com/chat/completions",
  env = {
    ---@return string|nil
    api_key = function()
      return _github_token
    end,
  },
  raw = {
    "--no-buffer",
    "--silent",
  },
  headers = {
    Authorization = "Bearer ${api_key}",
    ["Content-Type"] = "application/json",
    ["Copilot-Integration-Id"] = "vscode-chat",
    ["editor-version"] = "Neovim/" .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
  },
  parameters = {
    stream = true,
  },
  handlers = {
    ---Check for a token before starting the request
    ---@param self CodeCompanion.AdapterArgs
    ---@return boolean
    setup = function(self)
      _oauth_token = get_oauth_token()
      if not _oauth_token then
        log:error("No GitHub Copilot token found. Please refer to https://github.com/github/copilot.vim")
        return false
      end

      _github_token = authorize_token()
      if not _github_token then
        log:error("Could not authorize your GitHub Copilot token.")
        return false
      end

      return true
    end,

    --- Use the OpenAI adapter for the bulk of the work
    form_parameters = function(self, params, messages)
      return openai.handlers.form_parameters(self, params, messages)
    end,
    form_messages = function(self, messages)
      return openai.handlers.form_messages(self, messages)
    end,
    chat_output = function(data)
      return openai.handlers.chat_output(data)
    end,
    inline_output = function(data, context)
      return openai.handlers.inline_output(data, context)
    end,
    on_stdout = function(self, data)
      log:debug("Copilot stdout: %s", data._stdout_results)
      return openai.handlers.on_stdout(self, data)
    end,
  },
  schema = {
    model = {
      order = 1,
      mapping = "parameters",
      type = "enum",
      desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
      default = "gpt-4o-2024-05-13",
      choices = {
        "gpt-4o-2024-05-13",
      },
    },
    temperature = {
      order = 2,
      mapping = "parameters",
      type = "number",
      default = 0,
      desc = "What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or top_p but not both.",
    },
    max_tokens = {
      order = 3,
      mapping = "parameters",
      type = "integer",
      default = 4096,
      desc = "The maximum number of tokens to generate in the chat completion. The total length of input tokens and generated tokens is limited by the model's context length.",
    },
    top_p = {
      order = 4,
      mapping = "parameters",
      type = "number",
      default = 1,
      desc = "An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered. We generally recommend altering this or temperature but not both.",
    },
    n = {
      order = 5,
      mapping = "parameters",
      type = "number",
      default = 1,
      desc = "How many chat completions to generate for each prompt.",
    },
  },
}
