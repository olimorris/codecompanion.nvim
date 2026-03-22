local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local labels = require("codecompanion.interactions.chat.tools.labels")

---Ref: https://agentclientprotocol.com/protocol/schema#permissionoptionkind
local ACP_OPTIONS = {
  allow_once = { label = labels.accept, keymap = "accept" },
  allow_always = { label = labels.always_accept, keymap = "always_accept" },
  reject_once = { label = labels.reject, keymap = "reject" },
  reject_always = { label = labels.reject_always },
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

---Build a map of kind -> optionId for easy lookup
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

---Get the shared keymap key for an ACP option kind
---@param kind string
---@param keys table Resolved keymaps from labels.keymaps()
---@return string|nil
local function key_for_kind(kind, keys)
  local opt = ACP_OPTIONS[kind]
  if opt and opt.keymap and keys[opt.keymap] then
    return keys[opt.keymap]
  end
  return nil
end

---Build the banner displayed in the diff window winbar
---@param kind_map table<string, string> kind -> optionId
---@param keys table Resolved keymaps from labels.keymaps()
---@return string
local function build_banner(kind_map, keys)
  local parts = {}
  local sorted_kinds = vim.tbl_keys(kind_map)
  table.sort(sorted_kinds)

  for _, kind in ipairs(sorted_kinds) do
    local lhs = key_for_kind(kind, keys)
    if lhs then
      local label = (ACP_OPTIONS[kind] and ACP_OPTIONS[kind].label) or kind:gsub("_", " ")
      table.insert(parts, string.format("%s %s", lhs, label))
    end
  end

  table.insert(parts, string.format("%s/%s Next/Prev", keys.next_hunk, keys.previous_hunk))
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
---@param opts { diff_ui: CodeCompanion.DiffUI, kind_map: table<string, string>, keys: table, request: table, on_done: fun(choice_label: string) }
local function setup_diff_keymaps(opts)
  for kind, option_id in pairs(opts.kind_map) do
    local lhs = key_for_kind(kind, opts.keys)
    if lhs and option_id then
      local label = (ACP_OPTIONS[kind] and ACP_OPTIONS[kind].label) or kind
      vim.keymap.set("n", lhs, function()
        if opts.diff_ui.resolved then
          return
        end
        opts.diff_ui.resolved = true
        log:debug("[acp::request_permission] User selected option: %s (%s)", kind, option_id)
        opts.on_done(label)
        opts.request.respond(option_id, false)
        opts.diff_ui:close()
      end, {
        buffer = opts.diff_ui.bufnr,
        desc = label,
        silent = true,
        nowait = true,
      })
    end
  end

  vim.keymap.set("n", "q", function()
    opts.diff_ui:close()
  end, {
    buffer = opts.diff_ui.bufnr,
    desc = "Close diff",
    silent = true,
    nowait = true,
  })
end

---Display the diff preview and resolve permission by user decision
---@param opts { chat: CodeCompanion.Chat, request: table, on_done: fun(choice_label: string) }
---@return nil
local function show_diff(opts)
  local d = get_diff(opts.request.tool_call)

  local diff_id = math.random(1000000)
  local kind_map = build_kind_map(opts.request.options)
  local keys = labels.keymaps()

  local diff_ui = require("codecompanion.helpers").show_diff({
    from_lines = vim.split(d.old or "", "\n", { plain = true }),
    to_lines = vim.split(d.new or "", "\n", { plain = true }),
    banner = build_banner(kind_map, keys),
    chat_bufnr = opts.chat.bufnr,
    diff_id = diff_id,
    ft = vim.filetype.match({ filename = d.path }) or "text",
    keymaps = {
      on_reject = function()
        opts.on_done(labels.reject)
        local rejected = find_reject_option(opts.request.options)
        opts.request.respond(rejected, false)
      end,
    },
    skip_default_keymaps = true,
    title = vim.fn.fnamemodify(d.path, ":."),
  })

  setup_diff_keymaps({
    diff_ui = diff_ui,
    kind_map = kind_map,
    keys = keys,
    request = opts.request,
    on_done = opts.on_done,
  })
end

---Show the permission request to the user and handle their response
---@param chat CodeCompanion.Chat
---@param request table
---@return nil
function M.confirm(chat, request)
  local approval_prompt = require("codecompanion.interactions.chat.helpers.approval_prompt")

  local tool_call = request.tool_call
  local prompt = string.format(
    "%s: %s",
    utils.capitalize(tool_call and tool_call.kind or "Permission"),
    tool_call and tool_call.title or "Agent requested permission"
  )

  local has_diff = request.tool_call and requires_diff(request.tool_call)
  local keys = labels.keymaps()

  local choices = {}

  local on_done

  if has_diff then
    table.insert(choices, {
      keymap = keys.view,
      label = labels.view,
      preview = true,
      callback = function()
        log:debug("[acp::request_permission] Opening diff for review")
        show_diff({ chat = chat, request = request, on_done = on_done })
      end,
    })
  end

  for _, opt in ipairs(request.options or {}) do
    local key = key_for_kind(opt.kind, keys)
    if key then
      table.insert(choices, {
        keymap = key,
        label = (ACP_OPTIONS[opt.kind] and ACP_OPTIONS[opt.kind].label) or opt.name,
        callback = function()
          log:debug("[acp::request_permission] User selected option %s", opt.optionId)
          request.respond(opt.optionId, false)
        end,
      })
    end
  end

  table.insert(choices, {
    keymap = keys.cancel,
    label = labels.cancel,
    callback = function()
      log:debug("[acp::request_permission] User cancelled")
      request.respond(nil, true)
    end,
  })

  on_done = approval_prompt.request(chat, {
    id = request.id,
    name = tool_call and tool_call.kind or nil,
    title = has_diff and "View Proposed Edits" or nil,
    prompt = prompt,
    choices = choices,
  })
end

return M
