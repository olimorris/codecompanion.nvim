local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local util = require("codecompanion.utils")
local wait = require("codecompanion.strategies.chat.helpers.wait")

local api = vim.api

local CONSTANTS = {
  LABELS = {
    allow_always = "1 Allow always",
    allow_once = "2 Allow once",
    reject_once = "3 Reject",
    reject_always = "4 Reject always",
  },

  ALLOWED_KINDS = {
    allow_always = true,
    allow_once = true,
    reject_once = true,
    reject_always = true,
  },

  MAPPINGS_PREFIX = "_acp_",
  TIMEOUT_RESPONSE = config.strategies.chat.opts.acp_timeout_response or "reject_once",

  NS = api.nvim_create_namespace("codecompanion.acp.diff"),
}

local M = {}

---Build out the choices available to the user from the request
---@param request table
---@return string, string[], table<number, string>
local function build_choices(request)
  local prompt = string.format(
    "%s: %s ?",
    util.capitalize(request.tool_call and request.tool_call.kind or "permission"),
    request.tool_call and request.tool_call.title or "Agent requested permission"
  )

  local choices, index_to_option = {}, {}
  for i, opt in ipairs(request.options or {}) do
    table.insert(choices, "&" .. (CONSTANTS.LABELS[opt.kind] or (tostring(i) .. " " .. opt.name)))
    index_to_option[i] = opt.optionId
  end
  return prompt, choices, index_to_option
end

---Map possible kinds with their optionIDs from the agent
---@param options table
---@return table<string, string> -- kind -> optionId
local function build_kind_map(options)
  local map = {}
  for _, opt in ipairs(options or {}) do
    if type(opt.kind) == "string" and type(opt.optionId) == "string" then
      map[opt.kind] = opt.optionId
    end
  end
  return map
end

---We allow users to set acp keymaps in the same way as any other keymap
---Whilst this is convenient, we need to normalize the input to a
---simpler structure so we can set them properly in the diff
---@param keymaps table
---@return table<string, string> kind -> lhs
local function normalize_maps(keymaps)
  local normalized = {}
  for name, entry in pairs(keymaps or {}) do
    if type(name) == "string" and name:sub(1, #CONSTANTS.MAPPINGS_PREFIX) == CONSTANTS.MAPPINGS_PREFIX then
      local kind = (type(entry) == "table" and entry.kind) or name:match("^" .. CONSTANTS.MAPPINGS_PREFIX .. "(.*)$")
      local lhs = entry and entry.modes and entry.modes.n
      if kind and lhs then
        normalized[kind] = lhs
      end
    end
  end
  return normalized
end

-- Remove any mappings from a buffer
---@param bufnr number
---@param mapped_keys string[]
local function cleanup_mappings(bufnr, mapped_keys)
  for _, lhs in ipairs(mapped_keys) do
    pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
  end
end

---Set up keymaps in the buffer for the user to respond
---@param bufnr number
---@param normalized table<string, string> kind -> lhs
---@param kind_map table<string, string> kind -> optionId
---@param finish fun(accepted: boolean, timed_out: boolean, kind: string|nil)
---@param mapped_lhs_out string[] (output param to collect mapped lhs for cleanup)
local function setup_keymaps(bufnr, normalized, kind_map, finish, mapped_lhs_out)
  for kind, option_id in pairs(kind_map or {}) do
    local lhs = normalized[kind]
    if option_id and lhs then
      local accepted = (kind:find("allow", 1, true) ~= nil)
      table.insert(mapped_lhs_out, lhs)
      vim.keymap.set("n", lhs, function()
        finish(accepted, false, kind)
      end, { buffer = bufnr, silent = true, nowait = true })
    end
  end

  -- Quick cancel
  table.insert(mapped_lhs_out, "q")
  vim.keymap.set("n", "q", function()
    finish(false, false, nil)
  end, { buffer = bufnr, silent = true, nowait = true })
end

---Simple human label from kind (no hardcoded enum)
---@param kind string
---@return string
local function format_kind(kind)
  local s = kind:gsub("_", " ")
  return s:sub(1, 1):upper() .. s:sub(2)
end

---Build a single banner string from available keymaps
---@param normalized table<string, string> kind -> lhs
---@param kind_map table<string, string> kind -> optionId
---@return string
local function build_banner(normalized, kind_map)
  local maps = {}
  for kind, _ in pairs(kind_map or {}) do
    local lhs = normalized[kind]
    if lhs then
      table.insert(maps, ("[" .. format_kind(kind) .. ": " .. lhs .. "]"))
    end
  end
  table.sort(maps)
  table.insert(maps, "[Close: q]")
  return " Keymaps: " .. table.concat(maps, " | ") .. " "
end

---Place banner below the last line; only show keys that actually exist
---@param winnr number
---@param normalized table<string, string>
---@param kind_map table<string, string>
local function place_banner(winnr, normalized, kind_map)
  local banner = build_banner(normalized, kind_map)

  local ok = false
  if winnr and api.nvim_win_is_valid(winnr) then
    ok = pcall(function()
      ui.set_winbar(winnr, banner, "CodeCompanionChatInfoBanner")
    end)
  end

  if not ok then
    util.notify(banner)
  end
end

---Setup autocmds that cancel the permission if the diff is closed manually
---
---@param bufnr number
---@param winnr number
---@param finish fun(accepted: boolean, timed_out: boolean, kind: string|nil)
local function setup_autocmds(bufnr, winnr, finish)
  local group_name = ("codecompanion.acp.diff.%d.%d"):format(bufnr, winnr)
  local group = api.nvim_create_augroup(group_name, { clear = true })

  -- If the buffer is wiped, consider it a cancel
  api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    group = group,
    once = true,
    callback = function()
      pcall(finish, false, false, nil)
      pcall(api.nvim_clear_autocmds, { group = group })
    end,
  })

  -- If the window is closed, consider it a cancel
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    once = true,
    callback = function(args)
      if tonumber(args.match) == winnr then
        pcall(finish, false, false, nil)
        pcall(api.nvim_clear_autocmds, { group = group })
      end
    end,
  })
end

---Function to call when the user has provided a response
---@param request table
---@param diff table
---@param opts { bufnr: number, mapped_lhs: string[], winnr: number }
---@return fun(accepted: boolean, timed_out: boolean, kind: string|nil)
local function on_user_response(request, diff, opts)
  local done = false

  -- Find the optionId for a given kind
  local function get_option_id(kind)
    for _, opt in ipairs(request.options or {}) do
      if opt.kind == kind then
        return opt.optionId
      end
    end
  end

  -- Pick the first available optionId from a list of preferred kinds
  local function pick(from)
    for _, kind in ipairs(from) do
      local id = get_option_id(kind)
      if id then
        return id
      end
    end
  end

  -- Close floating window and delete buffer
  local function close_float()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == opts.bufnr then
        pcall(api.nvim_win_close, win, true)
      end
    end
    if api.nvim_buf_is_valid(opts.bufnr) then
      pcall(api.nvim_buf_delete, opts.bufnr, { force = true })
    end
  end

  return function(accepted, timed_out, kind)
    if done then
      return
    end
    done = true

    local option_id
    if kind then
      option_id = get_option_id(kind)
    else
      if timed_out then
        option_id = get_option_id(CONSTANTS.TIMEOUT_RESPONSE) or get_option_id("reject_once")
      else
        option_id = accepted and pick({ "allow_once", "allow_always" }) or pick({ "reject_once", "reject_always" })
      end
    end

    if not option_id then
      if (not accepted) and timed_out and diff.reject then
        pcall(function()
          diff:reject({ save = false })
        end)
      end
      cleanup_mappings(opts.bufnr, opts.mapped_lhs)
      close_float()
      return request.respond(nil, true)
    end

    if accepted then
      if diff.accept then
        pcall(function()
          diff:accept({ save = false })
        end)
      end
    else
      if diff.reject then
        pcall(function()
          diff:reject({ save = false })
        end)
      end
    end

    cleanup_mappings(opts.bufnr, opts.mapped_lhs)
    close_float()
    request.respond(option_id, false)
  end
end

---Determine if the tool call contains a diff object
---@param tool_call table
---@return boolean
local function tool_has_diff(tool_call)
  if
    tool_call.content
    and tool_call.content[1]
    and tool_call.content[1].type
    and tool_call.content[1].type == "diff"
  then
    -- Don't show a diff if there's nothing to diff...
    local content = tool_call.content[1]
    if (content.oldText == nil or content.oldText == "") and (content.newText == nil or content.newText == "") then
      return false
    end
    return true
  end
  return false
end

---Get the diff object from the tool call
---@param tool_call table
---@return table
local function get_diff(tool_call)
  return {
    kind = tool_call.kind,
    new = tool_call.content[1].newText,
    old = tool_call.content[1].oldText,
    path = vim.fs.joinpath(vim.fn.getcwd(), tool_call.content[1].path),
    status = tool_call.status,
    title = tool_call.title,
    tool_call_id = tool_call.toolCallId,
  }
end

---Display the diff preview and resolve permission by user decision
---@param chat CodeCompanion.Chat
---@param request table
---@return nil
local function show_diff(chat, request)
  local tool_call = request.tool_call
  if not tool_has_diff(tool_call) then
    return request.respond(nil, true)
  end

  local d = get_diff(tool_call)
  local old_lines = vim.split(d.old or "", "\n", { plain = true })
  local new_lines = vim.split(d.new or "", "\n", { plain = true })

  local window_config =
    vim.tbl_deep_extend("force", config.display.chat.child_window, config.display.chat.diff_window or {})

  local bufnr, winnr = ui.create_float(new_lines, {
    window = { width = window_config.width, height = window_config.height },
    row = window_config.row or "center",
    col = window_config.col or "center",
    relative = window_config.relative or "editor",
    filetype = vim.filetype.match({ filename = d.path }),
    title = "Edit Requested: " .. vim.fn.fnamemodify(d.path or "", ":."),
    lock = true,
    ignore_keymaps = true,
    opts = window_config.opts,
  })

  local diff_id = math.random(10000000)
  -- Force users to use the inline diff
  -- TODO: Possibly allow mini.diff in this scenario?
  local InlineDiff = require("codecompanion.providers.diff.inline")
  local diff = InlineDiff.new({
    bufnr = bufnr,
    contents = old_lines,
    id = diff_id,
    winnr = winnr,
  })
  if not diff then
    log:debug("[chat::acp::interactions] Failed to create diff; auto-canceling permission")
    return request.respond(nil, true)
  end

  -- Build present kinds and normalize keymaps from config
  local kind_map = build_kind_map(request.options)
  local normalized = normalize_maps(config.strategies.chat.keymaps)

  local mapped_lhs = {}
  local finish = on_user_response(request, diff, {
    bufnr = bufnr,
    mapped_lhs = mapped_lhs,
    winnr = winnr,
  })

  setup_keymaps(bufnr, normalized, kind_map, finish, mapped_lhs)
  place_banner(winnr, normalized, kind_map)
  setup_autocmds(bufnr, winnr, finish)

  return wait.for_decision(diff_id, { "CodeCompanionDiffAccepted", "CodeCompanionDiffRejected" }, function(result)
    if result.accepted then
      finish(true, false, nil)
    else
      finish(false, result.timeout == true, nil)
    end
  end, {
    chat_bufnr = chat.bufnr,
    notify = config.display.icons.warning .. " Waiting for decision ...",
  })
end

---Show the permission request to the user and handle their response
---@param chat CodeCompanion.Chat
---@param request table
---@return nil
function M.show(chat, request)
  if request.tool_call and tool_has_diff(request.tool_call) then
    return show_diff(chat, request)
  end

  local prompt, choices, index_to_option = build_choices(request)

  local picked = vim.fn.confirm(prompt, table.concat(choices, "\n"), 2, "Question")
  if picked > 0 and index_to_option[picked] then
    request.respond(index_to_option[picked], false)
  else
    request.respond(nil, true)
  end
end

return M
