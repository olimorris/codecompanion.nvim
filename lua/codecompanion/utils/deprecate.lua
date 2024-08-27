---[[
---Forked and edited from the awesome:
---https://github.com/EdenEast/nightfox.nvim/blob/main/lua/nightfox/lib/deprecation.lua
--]
local M = {
  _list = { { "[CodeCompanion.nvim]\n", "Question" }, { "The following has been " }, { "deprecated:\n", "WarningMsg" } },
  _has_warned = {},
}

function M.write(key, ...)
  if M._has_warned[key] then
    return
  end

  for _, e in ipairs({ ... }) do
    table.insert(M._list, type(e) == "string" and { e } or e)
  end

  M._list[#M._list][1] = M._list[#M._list][1] .. "\n"

  vim.api.nvim_echo(M._list, true, {})
  M._has_warned[key] = true
end

return M
