---@class CodeCompanion.Registry.Entry
---@field name string
---@field description string
---@field interaction string
---@field bufnr number
---@field open fun()
---@field hide fun()

local M = {}

---@type table<number, CodeCompanion.Registry.Entry>
local entries = {}

---Register an interaction
---@param bufnr number
---@param entry CodeCompanion.Registry.Entry
---@return nil
function M.add(bufnr, entry)
  entry.bufnr = bufnr
  entries[bufnr] = entry
end

---Deregister an interaction
---@param bufnr number
---@return nil
function M.remove(bufnr)
  entries[bufnr] = nil
end

---Partially update an entry
---@param bufnr number
---@param fields table
---@return nil
function M.update(bufnr, fields)
  if entries[bufnr] then
    for k, v in pairs(fields) do
      entries[bufnr][k] = v
    end
  end
end

---Return all entries
---@return CodeCompanion.Registry.Entry[]
function M.list()
  return vim
    .iter(pairs(entries))
    :map(function(_, v)
      return v
    end)
    :totable()
end

---Return a single entry
---@param bufnr number
---@return CodeCompanion.Registry.Entry|nil
function M.get(bufnr)
  return entries[bufnr]
end

---Navigate to the next or previous interaction
---@param current_bufnr number
---@param direction number 1 for next, -1 for previous
---@return nil
function M.move(current_bufnr, direction)
  local sorted = M.list()
  table.sort(sorted, function(a, b)
    return a.bufnr < b.bufnr
  end)

  local len = #sorted
  if len <= 1 then
    return
  end

  local idx
  for i, entry in ipairs(sorted) do
    if entry.bufnr == current_bufnr then
      idx = i
      break
    end
  end
  if not idx then
    return
  end

  local next_idx = direction > 0 and (idx % len) + 1 or ((idx - 2 + len) % len) + 1
  local current = sorted[idx]
  local next_entry = sorted[next_idx]

  current.hide()
  next_entry.open()
end

return M
