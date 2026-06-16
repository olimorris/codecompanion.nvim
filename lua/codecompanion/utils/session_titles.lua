local files = require("codecompanion.utils.files")
local log = require("codecompanion.utils.log")

local store_path = vim.fs.joinpath(vim.fn.stdpath("data"), "codecompanion", "session_titles.json")

local M = {}

---Load the title store from disk
---@return table<string, string>
local function load()
  if not files.exists(store_path) then
    return {}
  end

  local ok, data = pcall(files.read, store_path)
  if not ok then
    return {}
  end

  local decoded_ok, decoded = pcall(vim.json.decode, data, { luanil = { object = true } })
  if not decoded_ok or type(decoded) ~= "table" then
    return {}
  end

  return decoded
end

---Save the title store to disk
---@param store table<string, string>
---@return nil
local function save(store)
  local ok, err = pcall(files.write_to_path, store_path, vim.json.encode(store))
  if not ok then
    log:error("session_titles: failed to save: %s", err)
  end
end

---Get all persisted titles
---@return table<string, string>
function M.load_all()
  return load()
end

---Get the persisted title for a session
---@param session_id string
---@return string|nil
function M.get(session_id)
  return load()[session_id]
end

---Set the persisted title for a session
---@param session_id string
---@param title string
---@return nil
function M.set(session_id, title)
  local store = load()
  store[session_id] = title
  save(store)
end

---Remove the persisted title for a session
---@param session_id string
---@return nil
function M.remove(session_id)
  local store = load()
  if store[session_id] then
    store[session_id] = nil
    save(store)
  end
end

return M
