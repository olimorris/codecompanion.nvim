local config = require("codecompanion.config")

local M = {}

---@class CodeCompanion.SystemPrompt.Context
---@field language string
---@field adapter CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter
---@field date string
---@field nvim_version string
---@field os string the operating system that the user is using
---@field default_system_prompt? string
---@field cwd string current working directory
---@field project_root? string The closest parent directory that contains either a `.git`, `.svn`, or `.hg` directory

---Build the context that a system prompt function receives
---@param opts { adapter: CodeCompanion.HTTPAdapter|CodeCompanion.ACPAdapter, bufnr?: number }
---@return CodeCompanion.SystemPrompt.Context
function M.make_context(opts)
  ---@type table<string, fun():any>
  local dynamic_ctx = {
    -- These can be slow-to-run or too complex for a one-liner. So wrap them in
    -- functions and use a metatable to handle the eval when needed.
    adapter = function()
      return require("codecompanion.adapters").make_safe(opts.adapter)
    end,
    os = function()
      local machine = vim.uv.os_uname().sysname
      if machine == "Darwin" then
        machine = "Mac"
      end
      if machine:find("Windows") then
        machine = "Windows"
      end
      return machine
    end,
  }

  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local winid = vim.fn.bufwinid(bufnr)
  local static_ctx = { ---@type CodeCompanion.SystemPrompt.Context|{}
    cwd = winid ~= -1 and vim.fn.getcwd(winid) or vim.fn.getcwd(),
    date = tostring(os.date(config.interactions.opts.date_format)),
    language = config.opts.language or "English",
    nvim_version = vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
    project_root = vim.fs.root(bufnr, { ".git", ".svn", "hg" }),
  }

  ---@type CodeCompanion.SystemPrompt.Context
  return setmetatable(static_ctx, {
    __index = function(_, key)
      local val = dynamic_ctx[key]
      if type(val) == "function" then
        return val()
      end
      return val
    end,
  })
end

return M
