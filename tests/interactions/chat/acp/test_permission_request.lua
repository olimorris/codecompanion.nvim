local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        -- Minimal config surface used by permissions.lua
        local cfg = require("codecompanion.config")
        cfg.display = cfg.display or {}
        cfg.display.icons = cfg.display.icons or { warning = "!" }
        cfg.display.chat = cfg.display.chat or {}
        cfg.display.chat.floating_window = cfg.display.chat.floating_window or {
          width = 60, height = 12, row = "center", col = "center", relative = "editor", opts = {},
        }
        cfg.display.diff.window = cfg.display.diff.window or {}
        cfg.interactions = cfg.interactions or {}
        cfg.interactions.chat = cfg.interactions.chat or {}
        cfg.interactions.chat.opts = cfg.interactions.chat.opts or {}
        cfg.interactions.chat.keymaps = cfg.interactions.chat.keymaps or {}
        cfg.interactions.inline = cfg.interactions.inline or {}
        cfg.interactions.shared.keymaps = cfg.interactions.shared.keymaps or {
          view_diff = { modes = { n = "gv" } },
          always_accept = { modes = { n = "g1" } },
          accept_change = { modes = { n = "g2" } },
          reject_change = { modes = { n = "g3" } },
          cancel = { modes = { n = "g4" } },
          next_hunk = { modes = { n = "}" } },
          previous_hunk = { modes = { n = "{" } },
        }
      ]])
    end,
    post_case = function()
      child.lua([[
        -- Clean up any floating windows
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(win) then
            local cfg = vim.api.nvim_win_get_config(win)
            if cfg.relative and cfg.relative ~= "" then
              pcall(vim.api.nvim_win_close, win, true)
            end
          end
        end
        -- Unload modules
        package.loaded["codecompanion.interactions.chat.acp.request_permission"] = nil
        package.loaded["codecompanion.helpers"] = nil
        package.loaded["codecompanion.diff"] = nil
        package.loaded["codecompanion.diff.ui"] = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["no diff -> approval prompt -> return selected option"] = function()
  local result = child.lua([[
    -- Stub approval_prompt to auto-select by label
    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    ap.request = function(_, opts)
      for _, choice in ipairs(opts.choices) do
        if choice.label == "Accept" then
          choice.callback()
          return
        end
      end
    end

    local responded = {}
    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-nodiff",
        kind = "execute",
        title = "Run command",
        status = "pending",
        content = {}, -- no diff entries
      },
      options = {
        { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
        { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
      },
      respond = function(option_id, canceled)
        responded = { option_id = option_id, canceled = canceled }
      end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)
    return responded
  ]])

  h.eq("allow_once_id", result.option_id)
  h.eq(false, result.canceled)
end

T["no diff -> approval prompt -> reject option"] = function()
  local result = child.lua([[
    -- Stub approval_prompt to auto-select by label
    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    ap.request = function(_, opts)
      for _, choice in ipairs(opts.choices) do
        if choice.label == "Reject" then
          choice.callback()
          return
        end
      end
    end

    local responded = {}
    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-nodiff",
        kind = "execute",
        title = "Run command",
        status = "pending",
        content = {}, -- no diff entries
      },
      options = {
        { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
        { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
      },
      respond = function(option_id, canceled)
        responded = { option_id = option_id, canceled = canceled }
      end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)
    return responded
  ]])

  h.eq("reject_once_id", result.option_id)
  h.eq(false, result.canceled)
end

T["diff flow -> approval prompt shows view option"] = function()
  local result = child.lua([[
    -- Capture what approval_prompt receives
    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    _G.__approval_opts = nil
    ap.request = function(_, opts)
      _G.__approval_opts = {
        title = opts.title,
        prompt = opts.prompt,
        choice_keys = {},
        choice_labels = {},
      }
      for _, choice in ipairs(opts.choices) do
        table.insert(_G.__approval_opts.choice_keys, choice.keymap)
        table.insert(_G.__approval_opts.choice_labels, choice.label)
      end
    end

    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-diff",
        kind = "edit",
        title = "Apply changes",
        status = "pending",
        content = { { type = "diff", path = "file.txt", oldText = "old line", newText = "new line" } },
      },
      options = {
        { optionId = "allow_always_id", name = "Always", kind = "allow_always" },
        { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
        { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
      },
      respond = function() end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)
    return _G.__approval_opts
  ]])

  -- Small diff triggers inline mode with file-based title
  h.eq("Proposed edits for `file.txt`:", result.title)
  -- Inline diff text is included in the prompt
  h.eq(true, result.prompt:find("diff") ~= nil)
  h.eq("gv", result.choice_keys[1])
  h.eq("View", result.choice_labels[1])
  h.eq("Always accept", result.choice_labels[2])
  h.eq("Accept", result.choice_labels[3])
  h.eq("Reject", result.choice_labels[4])
end

T["diff flow -> view opens diff with keymaps"] = function()
  local result = child.lua([[
    -- Stub approval_prompt to auto-select "View"
    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    ap.request = function(_, opts)
      for _, choice in ipairs(opts.choices) do
        if choice.label == "View" then
          choice.callback()
          return
        end
      end
    end

    _G.__responded = nil
    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-diff",
        kind = "edit",
        title = "Apply changes",
        status = "pending",
        content = { { type = "diff", path = "file.txt", oldText = "old line", newText = "new line" } },
      },
      options = {
        { optionId = "allow_always_id", name = "Always", kind = "allow_always" },
        { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
        { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
      },
      respond = function(option_id, canceled)
        _G.__responded = { option_id = option_id, canceled = canceled }
      end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)

    -- Diff keymaps now come from shared keymaps config
    local keymaps = require("codecompanion.config").interactions.shared.keymaps

    -- Find the diff floating window
    local diff_bufnr, diff_winnr
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative and cfg.relative ~= "" then
        diff_winnr = win
        diff_bufnr = vim.api.nvim_win_get_buf(win)
        break
      end
    end

    -- Check keymaps exist on the buffer
    local function map_exists(bufnr, lhs)
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if m.lhs == lhs then return true end
      end
      return false
    end

    return {
      has_diff_window = diff_winnr ~= nil,
      has_accept = diff_bufnr and map_exists(diff_bufnr, keymaps.accept_change.modes.n) or false,
      has_always = diff_bufnr and map_exists(diff_bufnr, keymaps.always_accept.modes.n) or false,
      has_reject = diff_bufnr and map_exists(diff_bufnr, keymaps.reject_change.modes.n) or false,
      has_close = diff_bufnr and map_exists(diff_bufnr, "q") or false,
    }
  ]])

  h.eq(true, result.has_diff_window)
  h.eq(true, result.has_accept)
  h.eq(true, result.has_always)
  h.eq(true, result.has_reject)
  h.eq(true, result.has_close)
end

T["diff flow -> accept without viewing responds directly"] = function()
  local result = child.lua([[
    -- Stub approval_prompt to auto-select the "Allow" option
    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    ap.request = function(_, opts)
      for _, choice in ipairs(opts.choices) do
        if choice.label == "Accept" then
          choice.callback()
          return
        end
      end
    end

    local responded = {}
    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-diff",
        kind = "edit",
        title = "Apply changes",
        status = "pending",
        content = { { type = "diff", path = "file.txt", oldText = "old", newText = "new" } },
      },
      options = {
        { optionId = "allow_always_id", name = "Always", kind = "allow_always" },
        { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
        { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
      },
      respond = function(option_id, canceled)
        responded = { option_id = option_id, canceled = canceled }
      end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)

    -- No diff window should have been opened
    local has_float = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative and cfg.relative ~= "" then
        has_float = true
        break
      end
    end

    return {
      has_float = has_float,
      option_id = responded.option_id,
      canceled = responded.canceled,
    }
  ]])

  h.eq(false, result.has_float)
  h.eq("allow_once_id", result.option_id)
  h.eq(false, result.canceled)
end

T["diff flow -> empty oldText and newText does not show diff"] = function()
  local result = child.lua([[
    -- Stub approval_prompt to auto-select first option
    local ap = require("codecompanion.interactions.chat.helpers.approval_prompt")
    ap.request = function(_, opts)
      opts.choices[1].callback()
    end

    local responded = {}
    local chat = { bufnr = 0 }
    local request = {
      tool_call = {
        toolCallId = "tc-empty",
        kind = "edit",
        title = "Empty diff",
        status = "pending",
        content = { { type = "diff", path = "file.txt", oldText = "", newText = "" } },
      },
      options = {
        { optionId = "allow_once_id", name = "Allow", kind = "allow_once" },
        { optionId = "reject_once_id", name = "Reject", kind = "reject_once" },
      },
      respond = function(option_id, canceled)
        responded = { option_id = option_id, canceled = canceled }
      end,
    }

    local permissions = require("codecompanion.interactions.chat.acp.request_permission")
    permissions.confirm(chat, request)

    -- Check no floating window was created
    local has_float = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative and cfg.relative ~= "" then
        has_float = true
        break
      end
    end

    return {
      has_float = has_float,
      option_id = responded.option_id,
      canceled = responded.canceled,
      -- Empty diff falls through to non-diff path (no "View" option)
      first_choice_label = _G.__first_label,
    }
  ]])

  -- Empty diff should fall through to approval prompt without View option
  h.eq(false, result.has_float)
  h.eq("allow_once_id", result.option_id)
  h.eq(false, result.canceled)
end

return T
