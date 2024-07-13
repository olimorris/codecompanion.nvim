local function to_legendary_keymap(key, keymap)
  return {
    key,
    -- prefix makes it easier to search in legendary.nvim window
    desc = string.format("CodeCompanion: %s", require("legendary.util").get_desc(keymap)),
    -- keymaps are all for the chat buffer
    filters = { filetype = "codecompanion" },
  }
end

---@param cmd CodeCompanionCommand
local function to_legendary_cmd(cmd)
  return {
    cmd.cmd,
    desc = cmd.opts.desc,
  }
end

return function()
  require("legendary.extensions").pre_ui_hook(function()
    local keys = require("codecompanion.config").strategies.chat.keymaps
    local legendary_keys = {}
    for lhs, rhs in pairs(keys) do
      if type(rhs) == "string" and vim.startswith(rhs, "keymaps.") then
        rhs = require("codecompanion.keymaps")[vim.split(rhs, ".", { plain = true })[2]]
      end
      table.insert(legendary_keys, to_legendary_keymap(lhs, rhs))
    end

    local legendary_cmds = {}
    for _, cmd in ipairs(require("codecompanion.commands")) do
      table.insert(legendary_cmds, to_legendary_cmd(cmd))
    end

    local legendary = require("legendary")
    legendary.keymaps(legendary_keys)
    legendary.commands(legendary_cmds)
    return true
  end)
end
