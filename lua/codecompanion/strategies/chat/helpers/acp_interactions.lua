local config = require("codecompanion.config")
local diff_helper = require("codecompanion.strategies.chat.tools.catalog.helpers.diff")
local log = require("codecompanion.utils.log")
local ui = require("codecompanion.utils.ui")
local wait = require("codecompanion.strategies.chat.tools.catalog.helpers.wait")

local api = vim.api

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

---Pick an optionId from options by trying kinds in order
---@param options table
---@param prefer_kinds string[]
---@return string|nil
local function pick_option_id(options, prefer_kinds)
  local by_kind = {}
  for _, opt in ipairs(options or {}) do
    by_kind[opt.kind] = opt.optionId
  end
  for _, k in ipairs(prefer_kinds or {}) do
    if by_kind[k] then
      return by_kind[k]
    end
  end
  return nil
end

---Resolve a specific optionId for a given kind
---@param options table
---@param kind string
---@return string|nil
local function option_id_for_kind(options, kind)
  for _, opt in ipairs(options or {}) do
    if opt.kind == kind then
      return opt.optionId
    end
  end
  return nil
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

-- Build map of present kinds -> optionId from agent options
---@param options table
---@return table<string, string>
local function build_kind_map(options)
  local m = {}
  for _, opt in ipairs(options or {}) do
    if
      opt.kind == "allow_once"
      or opt.kind == "allow_always"
      or opt.kind == "reject_once"
      or opt.kind == "reject_always"
    then
      m[opt.kind] = opt.optionId
    end
  end
  return m
end

-- Remove any mappings from a buffer
---@param bufnr integer
---@param mapped_keys string[]
local function cleanup_mappings(bufnr, mapped_keys)
  for _, lhs in ipairs(mapped_keys or {}) do
    pcall(vim.keymap.del, "n", lhs, { buffer = bufnr })
  end
end

-- Install ACP-specific buffer-local keymaps dynamically based on options present
-- It scans config.strategies.chat.keymaps for entries starting with "_acp_".
-- Supports reserved names or an explicit entry.kind field.
---@param bufnr integer
---@param keymaps_cfg table
---@param kind_map table<string,string> -- kind -> optionId (present kinds)
---@param finish fun(accepted:boolean, timed_out:boolean, exact_kind:string|nil)
---@return string[] mapped_keys
local function setup_acp_keymaps(bufnr, keymaps_cfg, kind_map, finish)
  local mapped = {}

  local reserved = {
    _acp_allow_once = "allow_once",
    _acp_allow_always = "allow_always",
    _acp_reject_once = "reject_once",
    _acp_reject_always = "reject_always",
  }

  local function resolve_kind(key, entry)
    if entry and type(entry.kind) == "string" and kind_map[entry.kind] then
      return entry.kind
    end
    if reserved[key] and kind_map[reserved[key]] then
      return reserved[key]
    end
    -- As a fallback, try to parse suffix after _acp_
    local suffix = key:match("^_acp_(.*)$")
    if suffix and kind_map[suffix] then
      return suffix
    end
    return nil
  end

  for key, entry in pairs(keymaps_cfg or {}) do
    -- Only consider acp-specific entries
    if type(key) == "string" and key:sub(1, 5) == "_acp_" then
      local kind = resolve_kind(key, entry)
      local lhs = entry and entry.modes and entry.modes.n
      if kind and lhs then
        local accepted = (kind == "allow_once" or kind == "allow_always")
        table.insert(mapped, lhs)
        vim.keymap.set("n", lhs, function()
          finish(accepted, false, kind)
        end, { buffer = bufnr, silent = true, nowait = true })
      end
    end
  end

  return mapped
end

---Function to call when the user has provided a response
---@param request table
---@param diff_obj table
---@param bufnr integer
---@param using_scratch boolean
---@param mapped_keys string[]
---@return fun(accepted:boolean, timed_out:boolean, exact_kind:string|nil)
local function on_response(request, diff_obj, bufnr, using_scratch, mapped_keys)
  local done = false

  return function(accepted, timed_out, exact_kind)
    if done then
      return
    end
    done = true

    local option_id
    if exact_kind then
      option_id = option_id_for_kind(request.options, exact_kind)
    else
      local allow_pref = { "allow_once", "allow_always" }
      local reject_pref = { "reject_once", "reject_always" }
      option_id = accepted and pick_option_id(request.options, allow_pref)
        or pick_option_id(request.options, reject_pref)
    end

    if not option_id then
      if (not accepted) and timed_out and diff_obj.reject then
        pcall(function()
          diff_obj:reject()
        end)
      end
      cleanup_mappings(bufnr, mapped_keys)
      return request.respond(nil, true)
    end

    if accepted then
      if diff_obj.accept then
        pcall(function()
          diff_obj:accept()
        end)
      end
      if not using_scratch then
        pcall(function()
          api.nvim_buf_call(bufnr, function()
            vim.cmd("silent write")
          end)
        end)
      end
    else
      if diff_obj.reject then
        pcall(function()
          diff_obj:reject()
        end)
      end
    end

    cleanup_mappings(bufnr, mapped_keys)
    request.respond(option_id, false)
  end
end

---Display the diff preview and resolve permission by user decision
---@param chat CodeCompanion.Chat
---@param request { id: integer, session_id: string, tool_call: table, options: table, respond: fun(option_id:string|nil, canceled:boolean) }
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
  local diff_obj = diff_helper.create(bufnr, diff_id, {
    original_content = old_lines,
  })
  if not diff_obj then
    log:debug("[chat::helpers::acp_interactions] Failed to create diff; auto-canceling permission")
    return request.respond(nil, true)
  end

  local kind_map = build_kind_map(request.options or {})

  local finish = on_response(request, diff_obj, bufnr, using_scratch, {})
  local mapped_keys =
    setup_acp_keymaps(bufnr, (config.strategies.chat and config.strategies.chat.keymaps) or {}, kind_map, finish)
  finish = on_response(request, diff_obj, bufnr, using_scratch, mapped_keys)

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

return M
