local files = require("codecompanion.utils.files")

local M = {}

M.name = "Claude Code"
M.script = "claude.sh"

-- `claude.sh` reads the same variable, so the pair owns the name between them
local MARKER = "$CODECOMPANION_HOOK"

---Claude Code's hook events, mapped to the actions `claude.sh` reports
local HOOKS = {
  Notification = "approval_requested",
  PermissionRequest = "approval_requested",
  PostToolUse = "approval_finished",
  Stop = "done",
  UserPromptSubmit = "submitted",
}

---@param value any
---@param indent? string Carried through the recursion, not for callers
---@return string
local function encode(value, indent)
  indent = indent or ""

  if type(value) ~= "table" then
    return vim.json.encode(value)
  end

  local child = indent .. "  "

  if vim.islist(value) then
    if vim.tbl_isempty(value) then
      return "[]"
    end
    local items = vim.tbl_map(function(item)
      return child .. encode(item, child)
    end, value)
    return "[\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "]"
  end

  if vim.tbl_isempty(value) then
    return "{}"
  end

  -- Decoding loses the original key order, so sort to keep repeat writes stable
  local keys = vim.tbl_keys(value)
  table.sort(keys)

  local pairs_out = vim.tbl_map(function(key)
    return string.format("%s%s: %s", child, vim.json.encode(key), encode(value[key], child))
  end, keys)

  return "{\n" .. table.concat(pairs_out, ",\n") .. "\n" .. indent .. "}"
end

---@param path string
---@return table|nil settings Nil when the file could not be read or parsed
local function read_settings(path)
  local read_ok, lines = pcall(vim.fn.readfile, path)
  if not read_ok then
    return nil
  end

  local contents = table.concat(lines, "\n")
  if vim.trim(contents) == "" then
    return {}
  end

  local decode_ok, decoded = pcall(vim.json.decode, contents, { luanil = { object = true, array = true } })
  if not decode_ok or type(decoded) ~= "table" then
    return nil
  end

  return decoded
end

---Remove previous writes that CodeCompanion made to Claude Code's settings
---@param entries table[]
---@return table[]
local function delete_entries(entries)
  return vim.tbl_filter(function(entry)
    for _, hook in ipairs(entry.hooks or {}) do
      if type(hook.command) == "string" and hook.command:find(MARKER, 1, true) then
        return false
      end
    end
    return true
  end, entries)
end

---@param action string
---@return table
local function build_entry(action)
  return {
    hooks = {
      {
        type = "command",
        command = string.format('[ -z "%s" ] || "%s" %s', MARKER, MARKER, action),
      },
    },
  }
end

---@return string
function M.get_settings_path()
  return vim.fs.joinpath(vim.fn.expand("~"), ".claude", "settings.json")
end

---Merge CodeCompanion's hooks into Claude Code's settings
---@return boolean ok
---@return string|nil err
function M.install()
  local path = M.get_settings_path()

  local settings = read_settings(path)
  if not settings then
    return false, string.format("Could not read or parse %s, so it has been left alone", path)
  end

  settings.hooks = settings.hooks or {}
  for event, action in pairs(HOOKS) do
    local entries = delete_entries(settings.hooks[event] or {})
    table.insert(entries, build_entry(action))
    settings.hooks[event] = entries
  end

  local ok, err = pcall(files.write_to_path, path, encode(settings) .. "\n")
  if not ok then
    return false, string.format("Could not write %s: %s", path, err)
  end

  return true
end

return M
