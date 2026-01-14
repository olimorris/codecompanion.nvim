local config = require("codecompanion.config")
local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local CONSTANTS = {
  LABELS = {
    allow_always = "1 Allow always",
    allow_once = "2 Allow",
    reject_once = "3 Reject",
    reject_always = "4 Reject always",
  },

  MAPPINGS_PREFIX = "_acp_",
}

local M = {}

---Find the first reject option from the request options
---@param options table
---@return string|nil optionId
local function find_reject_option(options)
  for _, opt in ipairs(options or {}) do
    if opt.kind:find("^reject", 1, true) then
      return opt.optionId
    end
  end
  return nil
end

---Build out the choices available to the user from the request
---@param request table
---@return string, string[], table<number, string>
local function build_choices(request)
  local prompt = string.format(
    "%s: %s ?",
    utils.capitalize(request.tool_call and request.tool_call.kind or "permission"),
    request.tool_call and request.tool_call.title or "Agent requested permission"
  )

  local choices, index_to_option = {}, {}
  for i, opt in ipairs(request.options or {}) do
    table.insert(choices, "&" .. (CONSTANTS.LABELS[opt.kind] or (tostring(i) .. " " .. opt.name)))
    index_to_option[i] = opt.optionId
  end

  return prompt, choices, index_to_option
end

---Kinds are the kind of options (e.g., allow_once, reject_always) available to
---the usrer. Build a map of kind -> optionId for easy lookup
---@param options table
---@return table<string, string> kind -> optionId
local function build_kind_map(options)
  local map = {}
  for _, opt in ipairs(options or {}) do
    if type(opt.kind) == "string" and type(opt.optionId) == "string" then
      map[opt.kind] = opt.optionId
    end
  end
  return map
end

---We allow users to set acp keymaps in the same way as any other keymap.
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

---When diffing, we display a banner at the top of the hunk with the available
---keymaps. So here, we build that banner with normalized keymaps.
---@param normalized table<string, string> kind -> lhs
---@param kind_map table<string, string> kind -> optionId
---@return string
local function build_banner(normalized, kind_map)
  local next_hunk = config.interactions.inline.keymaps.next_hunk.modes.n
  local previous_hunk = config.interactions.inline.keymaps.previous_hunk.modes.n

  local parts = {}
  local sorted_kinds = vim.tbl_keys(kind_map)
  table.sort(sorted_kinds)

  for _, kind in ipairs(sorted_kinds) do
    local lhs = normalized[kind]
    if lhs then
      local label = CONSTANTS.LABELS[kind]:sub(3) or kind:gsub("_", " ")
      table.insert(parts, string.format("%s %s", lhs, label))
    end
  end

  table.insert(parts, string.format("%s/%s Next/Prev", next_hunk, previous_hunk))
  table.insert(parts, "q Close")

  return table.concat(parts, " | ")
end

---When an agent makes a tool call it may require us to form a diff
---@param tool_call table
---@return boolean
local function requires_diff(tool_call)
  local content = tool_call.content and tool_call.content[1]
  if not content or content.type ~= "diff" then
    return false
  end
  -- Empty diff shouldn't show UI
  return not ((content.oldText == nil or content.oldText == "") and (content.newText == nil or content.newText == ""))
end

---Get the diff object from the tool call
---@param tool_call table
---@return table
local function get_diff(tool_call)
  local absolute_path = tool_call.locations and tool_call.locations[1] and tool_call.locations[1].path
  local path = absolute_path or vim.fs.joinpath(vim.fn.getcwd(), tool_call.content[1].path)

  local old = tool_call.content[1].oldText
  local new = tool_call.content[1].newText

  if type(old) ~= "string" then
    old = ""
  end
  if type(new) ~= "string" then
    new = ""
  end

  return {
    kind = tool_call.kind,
    old = old,
    new = new,
    path = path,
    status = tool_call.status,
    title = tool_call.title,
    tools = {
      call_id = tool_call.toolCallId,
    },
  }
end

---Set up keymaps on the diff buffer for ACP permission responses
---@param diff_ui CodeCompanion.DiffUI
---@param normalized table<string, string> kind -> lhs
---@param kind_map table<string, string> kind -> optionId
---@param request table The permission request with respond callback
local function setup_diff_keymaps(diff_ui, normalized, kind_map, request)
  for kind, option_id in pairs(kind_map) do
    local lhs = normalized[kind]
    if lhs and option_id then
      vim.keymap.set("n", lhs, function()
        if diff_ui.resolved then
          return
        end
        diff_ui.resolved = true
        log:debug("[acp::request_permission] User selected option: %s (%s)", kind, option_id)
        request.respond(option_id, false)
        diff_ui:close()
      end, {
        buffer = diff_ui.bufnr,
        desc = CONSTANTS.LABELS[kind] or kind,
        silent = true,
        nowait = true,
      })
    end
  end

  -- Override q to use our reject handler
  vim.keymap.set("n", "q", function()
    if diff_ui.resolved then
      return
    end
    diff_ui.resolved = true

    local rejected = find_reject_option(request.options)
    if rejected then
      request.respond(rejected, false)
    else
      request.respond(nil, true)
    end
    diff_ui:close()
  end, {
    buffer = diff_ui.bufnr,
    desc = "Close and reject",
    silent = true,
    nowait = true,
  })
end

---Display the diff preview and resolve permission by user decision
---@param chat CodeCompanion.Chat
---@param request table
---@return nil
local function show_diff(chat, request)
  local d = get_diff(request.tool_call)
  local old_lines = vim.split(d.old or "", "\n", { plain = true })
  local new_lines = vim.split(d.new or "", "\n", { plain = true })
  local ft = vim.filetype.match({ filename = d.path })

  local kind_map = build_kind_map(request.options)
  local normalized = normalize_maps(config.interactions.chat.keymaps)
  local banner = build_banner(normalized, kind_map)

  local diff_id = math.random(10000000)
  local helpers = require("codecompanion.helpers")

  local diff_ui = helpers.show_diff({
    from_lines = old_lines,
    to_lines = new_lines,
    banner = banner,
    chat_bufnr = chat.bufnr,
    diff_id = diff_id,
    ft = ft or "text",
    skip_default_keymaps = true,
  })

  setup_diff_keymaps(diff_ui, normalized, kind_map, request)

  -- We set WinClosed autocmds to detect for when a user has made a selection
  -- WinClosed fires with the window ID as the match, so we need to use pattern
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(diff_ui.winnr),
    once = true,
    callback = function()
      if not diff_ui.resolved then
        diff_ui.resolved = true
        log:debug("[acp::request_permission] Diff window closed without selection, rejecting")

        local rejected = find_reject_option(request.options)
        if rejected then
          return request.respond(rejected, false)
        end
        return request.respond(nil, true)
      end
    end,
  })
end

---Show the permission request to the user and handle their response
---@param chat CodeCompanion.Chat
---@param request table
---@return nil
function M.confirm(chat, request)
  if request.tool_call and requires_diff(request.tool_call) then
    log:debug("[acp::request_permission] Showing diff for permission request")
    return show_diff(chat, request)
  end

  local prompt, choices, index_to_option = build_choices(request)
  log:debug("[acp::request_permission] Available choices %s", choices)

  local picked = vim.fn.confirm(prompt, table.concat(choices, "\n"), 2, "Question")
  if picked > 0 and index_to_option[picked] then
    log:debug("[acp::request_permission] User selected option %s", index_to_option[picked])
    request.respond(index_to_option[picked], false)
  else
    request.respond(nil, true)
  end
end

return M
