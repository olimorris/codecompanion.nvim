local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")

local Path = require("plenary.path")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")
local util_hash = require("codecompanion.utils.hash")

local fmt = string.format

local CONSTANTS = {
  NAME = "Fetch",
  CACHE_PATH = vim.fn.stdpath("cache") .. "/codecompanion/urls",
}

---Format the output for the chat buffer
---@param url string
---@param text string
---@return string
local function format_output(url, text)
  return fmt(
    [[Here is the content from `%s` that I'm sharing with you:

<content>
%s
</content>]],
    url,
    text
  )
end

---Output the contents of the URL to the chat buffer
---@param chat CodeCompanion.Chat
---@param data table
---@param opts table
---@return nil
local function output(chat, data, opts)
  local id = "<url>" .. data.url .. "</url>"

  chat:add_message({
    role = config.constants.USER_ROLE,
    content = format_output(data.url, data.content),
  }, { reference = id, visible = false })

  chat.references:add({
    source = "slash_command",
    name = "fetch",
    id = id,
  })

  if opts.silent then
    return
  end

  return util.notify(fmt("Added `%s` to the chat", data.url))
end

---Determine if the URL has already been cached
---@param hash string
---@return boolean
local function is_cached(hash)
  local p = Path:new(CONSTANTS.CACHE_PATH .. "/" .. hash)
  return p:exists()
end

---Read the cache for the URL
---@param chat CodeCompanion.Chat
---@param url string
---@param hash string
---@param opts table
---@return nil
local function read_cache(chat, url, hash, opts)
  local p = Path:new(CONSTANTS.CACHE_PATH .. "/" .. hash)
  local cache = p:read()

  log:debug("Fetch Slash Command: Restoring from cache for %s", url)

  return output(chat, {
    content = cache,
    url = url,
  }, opts)
end

---Write the cache for the URL
---@param hash string
---@param data string
---@return nil
local function write_cache(hash, data)
  local p = Path:new(CONSTANTS.CACHE_PATH .. "/" .. hash)
  p.filename = p:expand()
  vim.fn.mkdir(CONSTANTS.CACHE_PATH, "p")
  p:touch({ parents = true })
  p:write(data or "", "w")
end

---Fetch the contents of a URL
---@param chat CodeCompanion.Chat
---@param adapter table
---@param url string
---@param opts table
---@return nil
local function fetch(chat, adapter, url, opts)
  adapter.env = {
    query = function()
      return url
    end,
  }

  log:debug("Fetch Slash Command: Fetching from %s", url)

  return client
    .new({
      adapter = adapter,
    })
    :request({
      url = url,
    }, {
      callback = function(err, data)
        if err then
          return log:error("Failed to fetch the URL, with error %s", err)
        end

        if data then
          local ok, body = pcall(vim.json.decode, data.body)
          if not ok then
            return log:error("Could not parse the JSON response")
          end
          if data.status == 200 then
            write_cache(util_hash.hash(url), body.data.text)
            return output(chat, {
              content = body.data.text,
              url = url,
            }, opts)
          else
            return log:error("Error %s - %s", data.status, body.data.text)
          end
        end
      end,
    })
end

---Prompt the user whether to load the URL from the cache
---@param chat CodeCompanion.Chat
---@param url string
---@param hash string
---@param adapter table
---@param opts table
---@param cb function
---@return nil
local function load_from_cache(chat, url, hash, adapter, opts, cb)
  return vim.ui.select({ "Yes", "No" }, {
    prompt = "Load the URL from the cache?",
  }, function(choice)
    if not choice then
      return cb
    end
    if choice == "Yes" then
      return read_cache(chat, url, hash, opts)
    end
    return fetch(chat, adapter, url, opts)
  end)
end

---@class CodeCompanion.SlashCommand.Fetch: CodeCompanion.SlashCommand
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
---@param opts? table
---@return nil|string
function SlashCommand:execute(SlashCommands, opts)
  vim.ui.input({ prompt = "Enter a URL" }, function(url)
    if url == "" or not url then
      return nil
    end

    return self:output(url, opts)
  end)
end

---Output the contents of the URL
---@param url string
---@param opts? table
---@return nil
function SlashCommand:output(url, opts)
  local ok, adapter = pcall(require, "codecompanion.adapters.non_llm." .. self.config.opts.adapter)
  if not ok then
    ok, adapter = pcall(loadfile, self.config.opts.provider)
  end
  if not ok or not adapter then
    return log:error("Failed to load the adapter for the fetch Slash Command")
  end

  opts = opts or {}

  if type(adapter) == "function" then
    adapter = adapter()
  end

  adapter = adapters.resolve(adapter)
  if not adapter then
    return log:error("Failed to load the adapter for the fetch Slash Command")
  end

  local function call_fetch()
    return fetch(self.Chat, adapter, url, opts)
  end

  local hash = util_hash.hash(url)

  if opts and opts.ignore_cache then
    log:debug("Fetch Slash Command: Ignoring the cache")
    return call_fetch()
  end
  if opts and opts.auto_restore_cache then
    log:debug("Fetch Slash Command: Auto restoring from cache")
    return read_cache(self.Chat, url, hash, opts)
  end

  if is_cached(hash) then
    load_from_cache(self.Chat, url, hash, adapter, opts, function()
      return call_fetch()
    end)
  else
    return call_fetch()
  end
end

return SlashCommand
