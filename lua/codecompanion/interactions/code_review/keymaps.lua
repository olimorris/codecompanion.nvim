local config = require("codecompanion.config")
local keymaps = require("codecompanion.utils.keymaps")

local M = {}

-- The review keymaps and the quickfix list they were bound for. The quickfix
-- buffer is shared by every list, so the maps only act while our list is
-- current and restore what they replaced as soon as another list takes over
local bound = { list_id = nil, override = nil }

---Does the code review own the current quickfix list?
---@return boolean
function M.owns_quickfix()
  return bound.list_id ~= nil and vim.fn.getqflist({ id = 0 }).id == bound.list_id
end

---@return nil
function M.restore()
  if bound.override then
    bound.override:restore()
  end
  bound.list_id = nil
  bound.override = nil
end

---Run a review action, stepping aside when another list has taken over the quickfix
---@param action string
---@return fun()
local function review_action(action)
  return function()
    if not M.owns_quickfix() then
      return M.restore()
    end
    require("codecompanion.interactions.code_review")[action]()
  end
end

M.accept = {
  callback = review_action("accept"),
}
M.comment = {
  callback = review_action("comment"),
}
M.ignore = {
  callback = review_action("ignore"),
}

---Bind the review keymaps to the quickfix buffer, remembering what they replace
---@param bufnr number
---@return nil
function M.set(bufnr)
  M.restore()

  local override = keymaps.Override.new(bufnr)
  for _, map in pairs(config.interactions.code_review.keymaps or {}) do
    local keys = type(map) == "table" and map.modes and map.modes.n
    local action = keys and map.callback
    if type(action) == "string" then
      local named = M[action:match("^keymaps%.(.+)$") or action]
      action = named and named.callback
    end

    if action then
      for _, key in ipairs(type(keys) == "table" and keys or { keys }) do
        override:set(key, action, { desc = map.description })
      end
    end
  end

  bound.list_id = vim.fn.getqflist({ id = 0 }).id
  bound.override = override
end

return M
