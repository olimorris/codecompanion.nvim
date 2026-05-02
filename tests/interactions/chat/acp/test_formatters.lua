local h = require("tests.helpers")
local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[formatters = require("codecompanion.interactions.chat.acp.formatters")]])
    end,
    post_once = child.stop,
  },
})

---Send a tool call and adapter through `formatters.tool_message` in the child
---@param tool_call table
---@param opts? { verbose?: boolean }
---@return any
local function format(tool_call, opts)
  opts = opts or {}
  local adapter = { opts = { verbose_output = opts.verbose == true } }
  local expr = ("formatters.tool_message(%s, %s)"):format(vim.inspect(tool_call), vim.inspect(adapter))
  return child.lua_get(expr)
end

---Evaluate `formatters.extract_text(block)` in the child
---@param block table|nil
---@return any
local function extract_text(block)
  return child.lua_get(("formatters.extract_text(%s)"):format(vim.inspect(block)))
end

T["ACP Formatters"] = new_set()

T["ACP Formatters"]["extract_text - sanitises text blocks"] = function()
  h.eq(
    "Hello World code More text",
    extract_text({ type = "text", text = "Hello\nWorld\n```lua\ncode\n```\nMore text" })
  )
end

T["ACP Formatters"]["extract_text - resource_link returns uri"] = function()
  h.eq(
    "[resource: file:///path/to/file.txt]",
    extract_text({ type = "resource_link", uri = "file:///path/to/file.txt" })
  )
end

T["ACP Formatters"]["extract_text - image"] = function()
  h.eq("[image]", extract_text({ type = "image" }))
end

T["ACP Formatters"]["extract_text - audio"] = function()
  h.eq("[audio]", extract_text({ type = "audio" }))
end

T["ACP Formatters"]["extract_text - nil input"] = function()
  h.eq(vim.NIL, extract_text(nil))
end

T["ACP Formatters"]["edit - non-verbose returns label"] = function()
  h.eq(
    "Edit: /Users/test/file.lua",
    format({
      toolCallId = "edit-1",
      kind = "edit",
      status = "completed",
      title = "Write file.lua",
      locations = { { path = "/Users/test/file.lua" } },
      content = {
        { type = "diff", path = "/Users/test/file.lua", oldText = "old", newText = "old\nnew" },
      },
    })
  )
end

T["ACP Formatters"]["edit - verbose returns diff summary with +N lines"] = function()
  h.eq(
    "Edited /Users/test/file.lua (+1 lines)",
    format({
      toolCallId = "edit-1",
      kind = "edit",
      status = "completed",
      title = "Write file.lua",
      locations = { { path = "/Users/test/file.lua" } },
      content = {
        { type = "diff", path = "/Users/test/file.lua", oldText = "old", newText = "old\nnew" },
      },
    }, { verbose = true })
  )
end

T["ACP Formatters"]["edit - verbose returns diff summary with -N lines"] = function()
  h.eq(
    "Edited /Users/test/file.lua (-2 lines)",
    format({
      toolCallId = "edit-1",
      kind = "edit",
      status = "completed",
      title = "Write file.lua",
      locations = { { path = "/Users/test/file.lua" } },
      content = {
        { type = "diff", path = "/Users/test/file.lua", oldText = "a\nb\nc", newText = "a" },
      },
    }, { verbose = true })
  )
end

T["ACP Formatters"]["edit - pending status keeps label even when verbose"] = function()
  h.eq(
    "Edit: /Users/test/file.lua",
    format({
      toolCallId = "edit-1",
      kind = "edit",
      status = "pending",
      title = "Write file.lua",
      locations = { { path = "/Users/test/file.lua" } },
    }, { verbose = true })
  )
end

T["ACP Formatters"]["edit - cwd-relative diff path is shortened"] = function()
  local cwd = child.lua_get("vim.fn.getcwd()")
  h.eq(
    "Edited quotes.lua (+2 lines)",
    format({
      toolCallId = "edit-1",
      kind = "edit",
      status = "completed",
      title = "Write quotes.lua",
      locations = { { path = cwd .. "/quotes.lua" } },
      content = {
        {
          type = "diff",
          path = cwd .. "/quotes.lua",
          oldText = nil,
          newText = "-- Simple test comment for ACP capture\nreturn {}\n",
        },
      },
    }, { verbose = true })
  )
end

T["ACP Formatters"]["read - non-verbose returns label only"] = function()
  h.eq(
    "Read: /Users/test/config.json",
    format({
      toolCallId = "read-1",
      kind = "read",
      status = "completed",
      title = "Read config.json",
      locations = { { path = "/Users/test/config.json" } },
      content = {},
    })
  )
end

T["ACP Formatters"]["read - verbose appends content summary"] = function()
  h.eq(
    'Read: /Users/test/config.json — {"name": "test"} formatted',
    format({
      toolCallId = "read-1",
      kind = "read",
      status = "completed",
      title = "Read config.json",
      locations = { { path = "/Users/test/config.json" } },
      content = {
        {
          type = "content",
          content = { type = "text", text = '{"name": "test"}\n```json\nformatted\n```' },
        },
      },
    }, { verbose = true })
  )
end

T["ACP Formatters"]["execute - parses backtick-wrapped command from title"] = function()
  h.eq(
    "Execute: ls -la lua/codecompanion/interactions/chat/acp/formatters/",
    format({
      toolCallId = "exec-1",
      kind = "execute",
      status = "completed",
      title = "`ls -la lua/codecompanion/interactions/chat/acp/formatters/`",
      content = {
        {
          type = "content",
          content = {
            type = "text",
            text = "total 56\ndrwxr-xr-x@ 6 Oli  staff    192  4 Nov 18:04 .",
          },
        },
      },
    })
  )
end

T["ACP Formatters"]["search - verbose appends content summary"] = function()
  h.eq(
    "Search: Find **/*add_buf_message* — No files found",
    format({
      toolCallId = "search-1",
      kind = "search",
      status = "completed",
      title = "Find `**/*add_buf_message*`",
      content = {
        { type = "content", content = { type = "text", text = "No files found" } },
      },
    }, { verbose = true })
  )
end

T["ACP Formatters"]["missing kind defaults to 'Other'"] = function()
  h.eq(
    "Other: doing something",
    format({
      toolCallId = "x-1",
      status = "pending",
      title = "doing something",
    })
  )
end

T["ACP Formatters"]["snake_case kind is title-cased with space"] = function()
  h.eq(
    "Switch mode: plan",
    format({
      toolCallId = "sm-1",
      kind = "switch_mode",
      status = "completed",
      title = "plan",
    })
  )
end

T["ACP Formatters"]["title with trailing ' => ...' preview is stripped"] = function()
  h.eq(
    "Fetch: GET /api/users",
    format({
      toolCallId = "f-1",
      kind = "fetch",
      status = "pending",
      title = "GET /api/users => 200 OK",
    })
  )
end

T["ACP Formatters"]["nil tool_call is normalised to 'Other: Invalid tool call'"] = function()
  h.eq("Other: Invalid tool call", child.lua_get("formatters.tool_message(nil, { opts = {} })"))
end

return T
