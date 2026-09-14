local config = require("codecompanion.config")
local files = require("codecompanion.utils.files")

local fmt = string.format

local M = {}

M.DIR = "memories"
M.PREFIX = "/" .. M.DIR

---The absolute path to the memory directory
---@return string
function M.root()
  return vim.fs.joinpath(vim.fn.getcwd(), M.DIR)
end

---Every memory, addressed the way the LLM must pass it back to the memory tool
---@return string[]
function M.index()
  local root = M.root()
  if not files.is_dir(root) then
    return {}
  end

  local paths = vim
    .iter(files.scan_directory(root))
    :map(function(path)
      return M.PREFIX .. path:sub(#root + 1)
    end)
    :totable()
  table.sort(paths)

  return paths
end

---@return string[]
local function get_whitelisted_paths()
  local tool_config = config.interactions.chat.tools["memory"]
  local whitelist = tool_config and tool_config.opts and tool_config.opts.whitelist or {}

  local paths = {}
  for _, entry in ipairs(whitelist) do
    if entry.path and entry.as then
      local prefix = vim.startswith(entry.as, "/") and entry.as or ("/" .. entry.as)
      table.insert(paths, fmt("  - %s (mounted at %s)", entry.path, prefix))
    end
  end

  return paths
end

---Tell the LLM what it has stored, and how to name what it stores next
---@return string
function M.prompt()
  local index = M.index()

  local lines = {}
  if vim.tbl_isempty(index) then
    table.insert(lines, fmt("Your memory directory `%s` is empty.", M.PREFIX))
  else
    table.insert(lines, fmt("Below is everything in your memory directory `%s`:", M.PREFIX))
    table.insert(lines, "")
    vim.list_extend(
      lines,
      vim.tbl_map(function(path)
        return "- " .. path
      end, index)
    )
    table.insert(lines, "")
    table.insert(
      lines,
      "- That index is complete, so you never need to list the directory to see what you have stored."
    )
  end

  vim.list_extend(lines, {
    "- Read a memory only when its name matches what you have been asked about, and read one rather than several.",
    "- If no name matches, say that you have no memory on that topic instead of opening files to find out.",
    "- Save important decisions, summaries and insights from the conversation as new memories.",
    "- Name a memory so that the file name alone says what it holds: `parallel-sub-agents.md`, not `notes.md`. Rename any memory whose name fails that test.",
    "- Prefer updating an existing memory over creating a new one, unless the topic is new.",
    "- Say which memory you drew on when you continue or summarise an earlier conversation.",
  })

  local whitelisted = get_whitelisted_paths()
  if #whitelisted > 0 then
    table.insert(lines, fmt("- Alongside %s, you can also read and write to these paths:", M.PREFIX))
    vim.list_extend(lines, whitelisted)
  end

  return table.concat(lines, "\n")
end

return M
