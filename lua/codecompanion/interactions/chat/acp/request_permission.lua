local log = require("codecompanion.utils.log")
local utils = require("codecompanion.utils")

local labels = require("codecompanion.interactions.chat.tools.labels")

local fmt = string.format

---Ref: https://agentclientprotocol.com/protocol/schema#permissionoptionkind
local ACP_OPTIONS = {
  allow_once = { label = labels.accept, keymap = "accept" },
  allow_always = { label = labels.always_accept, keymap = "always_accept" },
  reject_once = { label = labels.reject, keymap = "reject" },
  reject_always = { label = labels.reject_always },
}

local M = {}

---Find the first reject option from the request options
---@param opts table
---@return string|nil optionId
local function find_reject_option(opts)
  for _, opt in ipairs(opts or {}) do
    if opt.kind:find("^reject", 1, true) then
      return opt.optionId
    end
  end
  return nil
end

---Build a map of kind -> optionId for easy lookup
---@param opts table
---@return table<string, string> kind -> optionId
local function build_kind_map(opts)
  local map = {}
  for _, opt in ipairs(opts or {}) do
    if type(opt.kind) == "string" and type(opt.optionId) == "string" then
      map[opt.kind] = opt.optionId
    end
  end
  return map
end

---Get the shared keymap key for an ACP option kind
---@param kind string
---@param keys table
---@return string|nil
local function key_for_kind(kind, keys)
  local opt = ACP_OPTIONS[kind]
  if opt and opt.keymap and keys[opt.keymap] then
    return keys[opt.keymap]
  end
  return nil
end

---Build the banner displayed in the diff window winbar
---@param kind_map table<string, string>
---@param keys table
---@return string
local function build_banner(kind_map, keys)
  local parts = {}
  local sorted_kinds = vim.tbl_keys(kind_map)
  table.sort(sorted_kinds)

  for _, kind in ipairs(sorted_kinds) do
    local lhs = key_for_kind(kind, keys)
    if lhs then
      local label = (ACP_OPTIONS[kind] and ACP_OPTIONS[kind].label) or kind:gsub("_", " ")
      table.insert(parts, fmt("%s %s", lhs, label))
    end
  end

  table.insert(parts, fmt("%s/%s Next/Prev", keys.next_hunk, keys.previous_hunk))
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

---Open the floating diff view for an ACP permission request
---@param permission table
local function open_diff_view(permission)
  local d = get_diff(permission.request.tool_call)

  local kind_map = build_kind_map(permission.request.options)
  local keys = labels.keymaps()

  local diff_ui = require("codecompanion.helpers").show_diff({
    from_lines = vim.split(d.old or "", "\n", { plain = true }),
    to_lines = vim.split(d.new or "", "\n", { plain = true }),
    banner = build_banner(kind_map, keys),
    chat_bufnr = permission.chat.bufnr,
    diff_id = math.random(1000000),
    ft = vim.filetype.match({ filename = d.path }) or "text",
    keymaps = {
      on_reject = function()
        permission.on_done(labels.reject)
        local rejected = find_reject_option(permission.request.options)
        permission.request.respond(rejected, false)
      end,
    },
    skip_default_keymaps = true,
    title = vim.fn.fnamemodify(d.path, ":."),
  })

  setup_diff_keymaps({
    diff_ui = diff_ui,
    kind_map = kind_map,
    keys = keys,
    request = permission.request,
    on_done = permission.on_done,
  })
end

---Build the approval choices for an ACP permission request
---@param permission table
---@param has_diff boolean
---@return CodeCompanion.Chat.ApprovalChoice[]
local function build_choices(permission, has_diff)
  local keys = labels.keymaps()
  local choices = {}

  if has_diff then
    table.insert(choices, {
      keymap = keys.view,
      label = labels.view,
      preview = true,
      callback = function()
        log:debug("[acp::request_permission] Opening diff for review")
        open_diff_view(permission)
      end,
    })
  end

  for _, opt in ipairs(permission.request.options or {}) do
    local key = key_for_kind(opt.kind, keys)
    if key then
      table.insert(choices, {
        keymap = key,
        label = (ACP_OPTIONS[opt.kind] and ACP_OPTIONS[opt.kind].label) or opt.name,
        callback = function()
          log:debug("[acp::request_permission] User selected option %s", opt.optionId)
          permission.request.respond(opt.optionId, false)
        end,
      })
    end
  end

  table.insert(choices, {
    keymap = keys.cancel,
    label = labels.cancel,
    callback = function()
      log:debug("[acp::request_permission] User cancelled")
      permission.request.respond(nil, true)
    end,
  })

  return choices
end

---Allow the user to approve from within the chat buffer
---@param permission table
---@param choices CodeCompanion.Chat.ApprovalChoice[]
---@param prompt_opts { title?: string, prompt: string }
local function approve_in_chat(permission, choices, prompt_opts)
  local approval_prompt = require("codecompanion.interactions.chat.helpers.approval_prompt")
  permission.on_done = approval_prompt.request(permission.chat, {
    choices = choices,
    id = permission.request.id,
    name = permission.request.tool_call and permission.request.tool_call.kind or nil,
    prompt = prompt_opts.prompt,
    title = prompt_opts.title,
  })
end

---Show the permission request to the user and handle their response
---@param chat CodeCompanion.Chat
---@param request table
---@return nil
function M.confirm(chat, request)
  local tool_call = request.tool_call
  local has_diff = tool_call and requires_diff(tool_call)

  local permission = { chat = chat, request = request }
  local choices = build_choices(permission, has_diff)

  if not has_diff then
    local prompt = fmt(
      "%s: %s",
      utils.capitalize(tool_call and tool_call.kind or "Permission"),
      tool_call and tool_call.title or "Agent requested permission"
    )
    return approve_in_chat(permission, choices, { prompt = prompt })
  end

  local d = get_diff(tool_call)
  local title = fmt("Proposed edits for `%s`:", vim.fn.fnamemodify(d.path, ":."))
  local from_lines = vim.split(d.old or "", "\n", { plain = true })
  local to_lines = vim.split(d.new or "", "\n", { plain = true })

  local approval_prompt = require("codecompanion.interactions.chat.helpers.approval_prompt")
  approval_prompt.present_diff({
    chat_bufnr = chat.bufnr,
    from_lines = from_lines,
    to_lines = to_lines,
    title = title,
    approve = function(prompt_opts)
      approve_in_chat(permission, choices, prompt_opts)
    end,
    open_diff_view = function()
      open_diff_view(permission)
    end,
  })
end

return M
