local function to_legendary_keymap(key, keymap)
  return {
    key,
    keymap.callback,
    desc = require("legendary.util").get_desc(keymap),
    -- keymaps are all for the chat buffer
    filters = { filetype = "codecompanion" },
  }
end

return function()
  require("legendary.extensions").pre_ui_hook(function()
    local keys = require("codecompanion.config").options.keymaps
    local legendary_keys = {}
    for lhs, rhs in pairs(keys) do
      if type(rhs) == "string" and vim.startswith(rhs, "keymaps.") then
        rhs = require("codecompanion.keymaps")[vim.split(rhs, ".", { plain = true })[2]]
      end
      table.insert(legendary_keys, to_legendary_keymap(lhs, rhs))
    end
  end)
end
