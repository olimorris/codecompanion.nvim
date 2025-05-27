local Path = require("plenary.path")
local buf = require("codecompanion.utils.buffers")
local log = require("codecompanion.utils.log")
local scan = require("plenary.scandir")

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

---Find files in the current working directory. Designed to match the Telescope API
function Default:find_files()
  local path = Path:new(vim.fn.getcwd())
  if not path:is_dir() then
    return {}
  end

  local files = scan.scan_dir(path:absolute(), {
    hidden = true,
    depth = 10,
    add_dirs = false,
  })

  self.to_display = vim
    .iter(files)
    :map(function(f)
      return { relative_path = f, path = f }
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
      return vim.fn.buflisted(bufnr) == 1 and api.nvim_buf_get_option(bufnr, "filetype") ~= "codecompanion"
    end)
    :map(function(bufnr)
      return buf.get_info(bufnr)
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
  local files = {}
  for _, path in ipairs(paths) do
    local p = Path:new(path)

    local file = scan.scan_dir(p:absolute(), {
      hidden = false,
      depth = 5,
      add_dirs = false,
      search_pattern = filetypes,
    })

    vim.list_extend(files, file)
  end

  self.to_display = vim
    .iter(files)
    :map(function(f)
      return { relative_path = f, path = f }
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
