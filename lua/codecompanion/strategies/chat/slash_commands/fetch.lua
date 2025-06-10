local Path = require("plenary.path")
local adapters = require("codecompanion.adapters")
local client = require("codecompanion.http")
local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local util = require("codecompanion.utils")
local util_hash = require("codecompanion.utils.hash")

local fmt = string.format

local CONSTANTS = {
  NAME = "Fetch",
  CACHE_PATH = config.strategies.chat.slash_commands.fetch.opts.cache_path,
}

---Get the cached URLs from the directory
---@return table
local function get_cached_files()
  local scan = require("plenary.scandir")
  local cache_dir = Path:new(CONSTANTS.CACHE_PATH):expand()

  if not Path:new(cache_dir):exists() then
    return {}
  end

  local cache = scan.scan_dir(cache_dir, {
    depth = 1,
    search_pattern = "%.json$",
  })

  local urls = vim
    .iter(cache)
    :map(function(f)
      local file = Path:new(f):read()
      local content = vim.json.decode(file)
      return {
        filepath = f,
        content = content.data,
        filename = vim.fn.fnamemodify(f, ":t"),
        url = content.url,
        timestamp = content.timestamp,
        display = string.format("[%s] %s", util.make_relative(content.timestamp), content.url),
      }
    end)
    :totable()

  -- Sort by timestamp (newest first)
  table.sort(urls, function(a, b)
    return a.timestamp > b.timestamp
  end)

  return urls
end

---Format the output for the chat buffer
---@param url string
---@param text string
---@param opts table
---@return string
local function format_output(url, text, opts)
  local output = [[%s

<content>
%s
</content>]]

  if opts and opts.description then
    return fmt(output, opts.description, text)
  end

  return fmt(output, "Here is the output from " .. url .. " that I'm sharing with you:", text)
end

---Output the contents of the URL to the chat buffer @param chat CodeCompanion.Chat
---@param data table
---@param opts? table
---@return nil
local function output(chat, data, opts)
  opts = opts or {}
  local id = "<url>" .. data.url .. "</url>"

  chat:add_message({
    role = config.constants.USER_ROLE,
    content = format_output(data.url, data.content, opts),
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

local providers = {
  ---The default provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  default = function(SlashCommand)
    local cached_files = get_cached_files()

    if #cached_files == 0 then
      return util.notify("No cached URLs found", vim.log.levels.WARN)
    end

    local default = require("codecompanion.providers.slash_commands.default")
    return default
      .new({
        output = function(selection)
          return output(SlashCommand.Chat, selection)
        end,
        SlashCommand = SlashCommand,
      })
      :urls(cached_files)
      :display()
  end,
  ---The snacks.nvim provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  snacks = function(SlashCommand)
    local cached_files = get_cached_files()

    if #cached_files == 0 then
      return util.notify("No cached URLs found", vim.log.levels.WARN)
    end

    local snacks = require("codecompanion.providers.slash_commands.snacks")
    snacks = snacks.new({
      output = function(selection)
        return output(SlashCommand.Chat, selection)
      end,
    })

    -- Transform cached files into picker items
    local items = vim.tbl_map(function(file)
      return {
        text = file.display,
        file = file.filepath,
        url = file.url,
        content = file.content,
        timestamp = file.timestamp,
      }
    end, cached_files)

    snacks.provider.picker.pick({
      title = "Cached URLs",
      items = items,
      prompt = snacks.title,
      format = function(item, _)
        local display_text = item.text
        return { { display_text } }
      end,
      confirm = snacks:display(),
      main = { file = false, float = true },
    })
  end,
  ---The Telescope provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  telescope = function(SlashCommand)
    local cached_files = get_cached_files()

    if #cached_files == 0 then
      return util.notify("No cached URLs found", vim.log.levels.WARN)
    end

    local telescope = require("codecompanion.providers.slash_commands.telescope")
    telescope = telescope.new({
      output = function(selection)
        return output(SlashCommand.Chat, selection)
      end,
    })

    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")

    local function create_finder()
      return finders.new_table({
        results = cached_files,
        entry_maker = function(entry)
          return {
            value = entry,
            content = entry.content,
            url = entry.url,
            ordinal = entry.display,
            display = entry.display,
            filename = entry.filepath,
          }
        end,
      })
    end

    pickers
      .new({
        finder = create_finder(),
        attach_mappings = telescope:display(),
      })
      :find()
  end,
  ---The Mini.Pick provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  mini_pick = function(SlashCommand)
    local cached_files = get_cached_files()

    if #cached_files == 0 then
      return util.notify("No cached URLs found", vim.log.levels.WARN)
    end

    local mini_pick = require("codecompanion.providers.slash_commands.mini_pick")
    mini_pick = mini_pick.new({
      output = function(selected)
        return output(SlashCommand.Chat, selected)
      end,
    })

    local items = vim.tbl_map(function(file)
      return {
        text = file.display,
        url = file.url,
        content = file.content,
      }
    end, cached_files)

    mini_pick.provider.start({
      source = vim.tbl_deep_extend(
        "force",
        mini_pick:display(function(picked_item)
          return picked_item
        end).source,
        {
          items = items,
        }
      ),
    })
  end,
  ---The FZF-Lua provider
  ---@param SlashCommand CodeCompanion.SlashCommand
  ---@return nil
  fzf_lua = function(SlashCommand)
    local cached_files = get_cached_files()

    if #cached_files == 0 then
      return util.notify("No cached URLs found", vim.log.levels.WARN)
    end

    local fzf = require("codecompanion.providers.slash_commands.fzf_lua")
    fzf = fzf.new({
      output = function(selected)
        return output(SlashCommand.Chat, selected)
      end,
    })

    local items = vim.tbl_map(function(file)
      return file.display
    end, cached_files)

    local transformer_fn = function(selected, _)
      for _, file_object in ipairs(cached_files) do
        if file_object.display == selected then
          return file_object
        end
      end
    end

    fzf.provider.fzf_exec(items, fzf:display(transformer_fn))
  end,
}

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
  local p = Path:new(CONSTANTS.CACHE_PATH .. "/" .. hash .. ".json")
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
  log:debug("Fetch Slash Command: Fetching from %s", url)

  -- Make sure that we don't modify the original adapter
  adapter = vim.deepcopy(adapter)
  adapter.methods.slash_commands.fetch(adapter)

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
            output(chat, {
              content = body.data.text,
              url = url,
            }, opts)

            -- Cache the response
            -- TODO: Get an LLM to create summary
            vim.ui.select({ "Yes", "No" }, {
              prompt = "Do you want to cache this URL?",
              kind = "codecompanion.nvim",
            }, function(selected)
              if selected == "Yes" then
                local hash = util_hash.hash(url)
                write_cache(
                  hash,
                  vim.json.encode({
                    url = url,
                    hash = hash,
                    timestamp = os.time(),
                    data = body.data.text,
                  })
                )
              end
            end)
          else
            return log:error("Error %s - %s", data.status, body.message or "No message provided")
          end
        end
      end,
    })
end

-- The different choices to load URLs in to the chat buffer
local choice = {
  URL = function(SlashCommand, _)
    return vim.ui.input({ prompt = "Enter the URL: " }, function(url)
      if #vim.trim(url or "") == 0 then
        return
      end

      return SlashCommand:output(url)
    end)
  end,
  Cache = function(SlashCommand, _)
    local cached_files = get_cached_files()

    if #cached_files == 0 then
      return util.notify("No cached URLs found", vim.log.levels.WARN)
    end

    return providers[SlashCommand.config.opts.provider](SlashCommand, cached_files)
  end,
}

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
  local cached_files = get_cached_files()
  local options = { "URL" }
  if #cached_files > 0 then
    table.insert(options, "Cache")
  end

  if #options == 1 then
    return choice[options[1]](self, SlashCommands)
  end

  vim.ui.select(options, {
    prompt = "Select link source",
    kind = "codecompanion.nvim",
  }, function(selected)
    if not selected then
      return
    end
    return choice[selected](self, SlashCommands)
  end)
end

---Output the contents of the URL
---@param url string
---@param opts? table
---@return nil
function SlashCommand:output(url, opts)
  opts = opts or {}

  local adapter = adapters.get_from_string(self.config.opts.adapter)
  if not adapter then
    return log:error("Could not resolve adapter for the fetch slash command")
  end

  local function call_fetch()
    return fetch(self.Chat, adapter, url, opts)
  end

  local hash = util_hash.hash(url)

  if opts and opts.ignore_cache then
    log:debug("Fetch Slash Command: Ignoring cache")
    return call_fetch()
  end
  if opts and opts.auto_restore_cache and is_cached(hash) then
    log:debug("Fetch Slash Command: Auto restoring from cache")
    return read_cache(self.Chat, url, hash, opts)
  end

  return call_fetch()
end

return SlashCommand
