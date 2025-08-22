local config = require("codecompanion.config")
local diff_helper = require("codecompanion.strategies.chat.tools.catalog.helpers.diff")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local wait = require("codecompanion.strategies.chat.tools.catalog.helpers.wait")

local api = vim.api

local CONSTANTS = {
  MAPPINGS_PREFIX = "_acp_",
  TIMEOUT_RESPONSE = config.strategies.chat.opts.acp_timeout_response or "reject_once",
}

local ALLOWED_KINDS = {
  allow_once = true,
  allow_always = true,
  reject_once = true,
  reject_always = true,
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
    if ALLOWED_KINDS[opt.kind] then
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
      if kind and ALLOWED_KINDS[kind] and lhs then
        normalized[kind] = lhs
      end
    end
  end
  return normalized
end

---Open an existing buffer or the file path in a window; return bufnr (or nil)
---@param path string
---@return number|nil
local function open_target_buffer(path)
  -- Try and find existing buffer first...
  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and api.nvim_buf_is_valid(bufnr) then
    local win = ui.buf_get_win(bufnr)
    if win then
      pcall(api.nvim_set_current_win, win)
    end
    return bufnr
  end

  -- ...Before trying to open the file directly
  if vim.fn.filereadable(path) == 1 then
    -- Open in current window (simple, non-floating)
    pcall(vim.cmd.edit, vim.fn.fnameescape(path))
    return api.nvim_get_current_buf()
  end

  return nil
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
---@param bufnr number
---@param using_scratch boolean
---@param mapped_lhs string[]
---@return fun(accepted: boolean, timed_out: boolean, kind: string|nil)
local function on_user_response(request, diff, bufnr, using_scratch, mapped_lhs)
  local done = false

  local function option_id_for_kind(kind)
    for _, opt in ipairs(request.options or {}) do
      if opt.kind == kind then
        return opt.optionId
      end
    end
  end

  local function pick(prefer)
    for _, kind in ipairs(prefer) do
      local id = option_id_for_kind(kind)
      if id then
        return id
      end
    end
  end

  return function(accepted, timed_out, kind)
    if done then
      return
    end
    done = true

    local option_id
    if kind then
      option_id = option_id_for_kind(kind)
    else
      if timed_out then
        option_id = option_id_for_kind(CONSTANTS.TIMEOUT_RESPONSE) or option_id_for_kind("reject_once")
      else
        option_id = accepted and pick({ "allow_once", "allow_always" }) or pick({ "reject_once", "reject_always" })
      end
    end

    if not option_id then
      if (not accepted) and timed_out and diff.reject then
        pcall(function()
          diff:reject()
        end)
      end
      cleanup_mappings(bufnr, mapped_lhs)
      return request.respond(nil, true)
    end

    if accepted then
      if diff.accept then
        pcall(function()
          diff:accept()
        end)
      end
      if not using_scratch then
        pcall(function()
          api.nvim_buf_call(bufnr, function()
            vim.cmd("silent update!")
          end)
        end)
      end
    else
      if diff.reject then
        pcall(function()
          diff:reject()
        end)
      end
    end

    cleanup_mappings(bufnr, mapped_lhs)
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

  local bufnr = open_target_buffer(d.path)
  local using_scratch = false
  if not bufnr then
    using_scratch = true
    bufnr = api.nvim_create_buf(true, false)
  end

  pcall(function()
    vim.bo[bufnr].modifiable = true
    api.nvim_buf_set_lines(bufnr, 0, -1, true, new_lines)
  end)

  local ft = vim.filetype.match({ filename = d.path })
  if ft then
    pcall(vim.api.nvim_set_option_value, "filetype", ft, { buf = bufnr })
  end

  local diff_id = math.random(10000000)
  local diff = diff_helper.create(bufnr, diff_id, {
    original_content = old_lines,
    set_keymaps = false,
  })
  if not diff then
    log:debug("[chat::helpers::acp_interactions] Failed to create diff; auto-canceling permission")
    return request.respond(nil, true)
  end

  -- Build present kinds and normalize keymaps from config
  local kind_map = build_kind_map(request.options)
  local normalized = normalize_maps(config.strategies.chat.keymaps)

  -- Single finisher + single cleanup for both paths
  local mapped_lhs = {}
  local finish = on_user_response(request, diff, bufnr, using_scratch, mapped_lhs)

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
