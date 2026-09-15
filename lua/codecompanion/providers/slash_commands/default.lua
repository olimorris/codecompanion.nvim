local buf_utils = require("codecompanion.utils.buffers")
local files_utils = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local api = vim.api

---@class CodeCompanion.SlashCommand.Provider.Default: CodeCompanion.SlashCommand.Provider
local Default = {}

---@param args CodeCompanion.SlashCommand.ProviderArgs
function Default.new(args)
  local self = setmetatable({
    SlashCommand = args.SlashCommand,
    output = args.output,
    title = args.title,
  }, { __index = Default })

  return self
end

---Find files in the given directories. Designed to match the Telescope API
---@param opts? { dirs?: string[] }
function Default:find_files(opts)
  opts = opts or {}

  local files = {}
  for _, dir in ipairs(opts.dirs or { vim.fn.getcwd() }) do
    vim.list_extend(files, files_utils.scan_directory(dir, { max_depth = 10 }))
  end

  self.to_display = vim
    .iter(files)
    :map(function(file)
      return { relative_path = vim.fn.fnamemodify(file, ":."), path = file }
    end)
    :totable()

  self.to_format = function(item)
    return item.relative_path
  end

  return self
end

---Display current buffers in Neovim
function Default:buffers()
  local buffers = vim
    .iter(api.nvim_list_bufs())
    :filter(function(bufnr)
      return vim.fn.buflisted(bufnr) == 1 and api.nvim_get_option_value("filetype", { buf = bufnr }) ~= "codecompanion"
    end)
    :map(function(bufnr)
      return buf_utils.get_info(bufnr)
    end)
    :totable()

  if not next(buffers) then
    return log:warn("No buffers found")
  end

  -- Reorder the list so the buffer that the user initiated the chat from is at the top

  self.to_format = function(item)
    return item.relative_path
  end

  self.to_display = buffers
  return self
end

---Find URLs in a set of paths
---@param urls table The table of URLs to display
---@return nil
function Default:urls(urls)
  self.to_display = urls
  self.to_format = function(item)
    return item.display or item.url
  end
  return self
end

---Find images in a set of paths
---@param paths table
---@param filetypes table
function Default:images(paths, filetypes)
  local patterns
  if filetypes and next(filetypes) then
    patterns = vim
      .iter(filetypes)
      :map(function(filetype)
        return "*." .. filetype
      end)
      :totable()
  end

  local files = {}
  for _, path in ipairs(paths) do
    vim.list_extend(files, files_utils.scan_directory(path, { max_depth = 5, patterns = patterns }))
  end

  self.to_display = vim
    .iter(files)
    :map(function(file)
      return { relative_path = vim.fn.fnamemodify(file, ":."), path = file }
    end)
    :totable()

  self.to_format = function(item)
    return item.relative_path
  end

  return self
end

---The function to display the provider
---@return function
function Default:display()
  return vim.ui.select(self.to_display, {
    kind = "codecompanion.nvim",
    prompt = self.title,
    format_item = function(item)
      return self.to_format(item)
    end,
  }, function(selected)
    if not selected then
      return
    end

    return self.output(selected)
  end)
end

return Default
