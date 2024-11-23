local buf = require("codecompanion.utils.buffers")
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

---Find files in the current working directory. Designed to match the Telescope API
function Default:find_files()
  local check_git = vim.fn.system("git rev-parse --is-inside-work-tree")
  if check_git == 1 then
    return log:error(
      "The default provider requires the repository to be git enabled. Please select an alternative provider."
    )
  end

  local tracked_files = vim.fn.system(string.format("git -C %s ls-files", vim.fn.getcwd()))
  local untracked_files =
    vim.fn.system(string.format("git -C %s ls-files --others --exclude-standard", vim.fn.getcwd()))
  local files = tracked_files .. "\n" .. untracked_files

  self.to_display = vim
    .iter(vim.split(files, "\n"))
    :map(function(f)
      return { relative_path = f, path = vim.fn.getcwd() .. "/" .. f }
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

---The function to display the provider
---@return function
function Default:display()
  return vim.ui.select(self.to_display, {
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
