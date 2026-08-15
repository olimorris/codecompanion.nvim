--[[
Manual harness for the get_diagnostics tool.
NOTE: Debug/eyeball script - not part of the automated Mini.Test suite. It needs a real
language server attached, which is why it can't live in tests/.

Usage: with CodeCompanion loaded and your LSP running:
  :luafile tests/scripts/get_diagnostics_tool.lua   runs against FILE, or the current buffer
  :CCGetDiagnostics lua/codecompanion/init.lua      runs against any path, after sourcing

Prints what the tool hands back to the chat buffer: the inspected { status, data } table,
then the data on its own so the formatting is readable. Both land in :messages.
--]]

-- ============================================================================
-- CONFIG - edit, then :luafile %
-- ============================================================================

local FILE = "~/Code/Neovim/codecompanion.nvim/feature-a/lua/codecompanion/interactions/chat/context.lua" -- empty runs against the current buffer
local SEVERITY = "WARNING" -- nil | "ERROR" | "WARNING" | "INFORMATION" | "HINT"

-- ============================================================================

local tool = require("codecompanion.interactions.chat.tools.builtin.get_diagnostics")

local fmt = string.format

---Run the tool against a path and print what it returns
---@param filepath string
---@return nil
local function inspect_diagnostics(filepath)
  local started = vim.uv.hrtime()

  tool.cmds[1](tool, { filepath = filepath, severity = SEVERITY }, {
    output_cb = function(msg)
      local bufnr = vim.fn.bufnr(filepath)
      local clients = bufnr ~= -1 and #vim.lsp.get_clients({ bufnr = bufnr }) or 0

      print(
        fmt(
          "get_diagnostics `%s` returned in %.0fms, %d LSP client(s) attached",
          filepath,
          (vim.uv.hrtime() - started) / 1e6,
          clients
        )
      )
      print(vim.inspect(msg))
      print(msg.data)
    end,
  })
end

inspect_diagnostics(FILE ~= "" and FILE or vim.api.nvim_buf_get_name(0))
