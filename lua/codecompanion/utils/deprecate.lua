---[[
---Forked and edited from the awesome:
---https://github.com/EdenEast/nightfox.nvim/blob/main/lua/nightfox/lib/deprecation.lua
--]
local M = {
  _list = { { "[CodeCompanion.nvim]\n", "Question" }, { "The following has been " }, { "deprecated:\n", "WarningMsg" } },
  _has_registered = false,
}

function M.write(...)
  for _, e in ipairs({ ... }) do
    table.insert(M._list, type(e) == "string" and { e } or e)
  end

  M._list[#M._list][1] = M._list[#M._list][1] .. "\n"

  if not M._has_registered then
    vim.api.nvim_echo(M._list, true, {})
    M._has_registered = true
  end
end

return M
