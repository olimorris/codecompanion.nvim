local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local wait = require("codecompanion.strategies.chat.helpers.wait")

local api = vim.api

local CONSTANTS = {
  ALLOWED_KINDS = {
    allow_once = true,
    allow_always = true,
    reject_once = true,
    reject_always = true,
  },
  MAPPINGS_PREFIX = "_acp_",
  TIMEOUT_RESPONSE = config.strategies.chat.opts.acp_timeout_response or "reject_once",
}

local M = {}

---Determine if the tool call contains a diff object
---@param tool_call table
---@return boolean
function M.tool_has_diff(tool_call)
  if
    tool_call.content
    and tool_call.content[1]
    and tool_call.content[1].type
    and tool_call.content[1].type == "diff"
  then
    return true
  end
  return false
end

---Get the diff object from the tool call
---@param tool_call table
---@return table
function M.get_diff(tool_call)
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

---Map possible kinds with their optionIDs from the agent
---@param options table
---@return table<string, string> -- kind -> optionId
local function build_kind_map(options)
  local map = {}

  for _, opt in ipairs(options or {}) do
    if CONSTANTS.ALLOWED_KINDS[opt.kind] then
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
      if kind and CONSTANTS.ALLOWED_KINDS[kind] and lhs then
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
---@param finish fun(accepted: boolean, timed_out: boolean, kind: string)
---@param mapped_lhs_out string[] (output param to collect mapped lhs for cleanup)
local function setup_keymaps(bufnr, normalized, kind_map, finish, mapped_lhs_out)
  for kind, lhs in pairs(normalized or {}) do
    if kind_map[kind] and lhs then
      local accepted = (kind == "allow_once" or kind == "allow_always")
      table.insert(mapped_lhs_out, lhs)
      vim.keymap.set("n", lhs, function()
        finish(accepted, false, kind)
      end, { buffer = bufnr, silent = true, nowait = true })
    end
  end
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

---Display the diff preview and resolve permission by user decision
---@param chat CodeCompanion.Chat
---@param request table
---@return nil
function M.show_diff(chat, request)
  local tool_call = request.tool_call
  if not M.tool_has_diff(tool_call) then
    return request.respond(nil, true)
  end

  local d = M.get_diff(tool_call)
  local old_lines = vim.split(d.old or "", "\n", { plain = true })
  local new_lines = vim.split(d.new or "", "\n", { plain = true })

  local window_config = config.display.chat.child_window

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

  return wait.for_decision(diff_id, { "CodeCompanionDiffAccepted", "CodeCompanionDiffRejected" }, function(result)
    if result.accepted then
      finish(true, false, nil)
    else
      finish(false, result.timeout == true, nil)
    end
  end, {
    chat_bufnr = chat.bufnr,
    notify = config.display.icons.warning .. " Waiting for decision ...",
  }, { timeout = 2e6 }) -- c. 30 mins wait
end

return M
