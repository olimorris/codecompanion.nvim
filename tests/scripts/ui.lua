--[[
Manual UI render harness for the chat buffer (WS-A of the UI builder refactor).
NOTE: Debug/eyeball script - not part of the automated Mini.Test suite. No screenshots.

Usage: with CodeCompanion loaded in Neovim, edit the CONFIG block below, then:
  :luafile tests/scripts/ui.lua
It opens a real chat buffer and streams content into it at a fixed cadence so you
can watch exactly how the builder renders.

Two modes:

  MODE = "logical"  Replays a hand-written profile of { role, type, content } events
                    straight through chat:add_buf_message. Adapter-independent: it
                    isolates the builder/formatters from any adapter parsing. Use the
                    profiles to compare how different streaming shapes (fragmented
                    reasoning, an empty chunk before a tool, batched tools) render.

  MODE = "stub"     Replays a real captured adapter payload from
                    tests/adapters/http/stubs/<STUB>.txt through the genuine pipeline
                    (parse_chat -> process_chunk -> add_buf_message -> done) by patching
                    the HTTP client. This reproduces adapter-specific quirks faithfully,
                    which is where the streamed-data inconsistencies usually live.

No LLM completion request leaves the machine: the HTTP client is swapped for one that
feeds the captured lines back through the real callbacks, and it absorbs any follow-up
request (title generation, a compaction check) with an empty completion. The adapter may
still perform its usual model-list fetch when it resolves (normal plugin behaviour). The
swap persists for the session, so restart Neovim to return the plugin to normal use.
--]]

-- ============================================================================
-- CONFIG - edit, then :luafile %
-- ============================================================================

local MODE = "logical" -- "logical" | "stub"
local DELAY_MS = 40 -- fixed delay between chunks (streaming cadence)

-- MODE = "logical"
-- Profiles: reasoning_then_response, reasoning_then_tool, text_then_tools,
--           empty_llm_before_tool, reasoning_fragmented, tools_batch
local PROFILE = "tools_batch"

-- MODE = "stub" (STUB is a filename in tests/adapters/http/stubs/ without .txt)
local ADAPTER = "anthropic"
local STUB = "anthropic_reasoning_streaming"

-- ============================================================================

local stub_dir = (function()
  local this = debug.getinfo(1, "S").source:gsub("^@", "")
  local dir = vim.fn.fnamemodify(this, ":h")
  return vim.fs.normalize(vim.fs.joinpath(dir, "..", "adapters", "http", "stubs"))
end)()

--- Hand-written streaming profiles. Each event mirrors add_buf_message args, so a
--- profile IS an adapter behaviour we want the builder to render consistently.
--- type is one of: "reasoning", "llm", "tool". status (optional) drives a tool icon
--- and, when set, suppresses folds (mimics the ACP path); omit it for HTTP-style folds.
local profiles = {
  reasoning_then_response = {
    { type = "reasoning", content = "The user wants a two word description. " },
    { type = "reasoning", content = "Let me pick something evocative." },
    { type = "llm", content = "**Elegant simplicity** - " },
    { type = "llm", content = "clean syntax with expressive power." },
  },

  -- Decision 3: a tool call closes the reasoning run, so "### Response" appears
  -- before the tool, not before the following prose.
  reasoning_then_tool = {
    { type = "reasoning", content = "I should read the config before answering. " },
    { type = "reasoning", content = "It'll tell me which adapters are in use." },
    {
      type = "tool",
      content = "read_file: lua/codecompanion/config.lua\nreturn { adapters = {...}, display = {...} }\n-- 1200 lines total",
    },
    { type = "llm", content = "The config defines adapters, tools and display options." },
  },

  text_then_tools = {
    { type = "llm", content = "Let me gather some context first." },
    { type = "tool", content = "grep_search: 'context_management'\n12 matches across 4 files" },
    { type = "tool", content = "read_file: helpers.lua\n-- module contents..." },
    { type = "llm", content = "Found the relevant code in helpers.lua." },
  },

  -- The OpenRouter quirk: an empty llm content chunk arrives before the tool call.
  empty_llm_before_tool = {
    { type = "llm", content = "" },
    { type = "tool", content = "web_search: 'neovim lua'\n5 results returned" },
    { type = "llm", content = "Here's what I found in the search results." },
  },

  -- Reasoning arriving as many tiny chunks must render identically to one chunk.
  reasoning_fragmented = {
    { type = "reasoning", content = "Let me " },
    { type = "reasoning", content = "think " },
    { type = "reasoning", content = "about " },
    { type = "reasoning", content = "this " },
    { type = "reasoning", content = "carefully, " },
    { type = "reasoning", content = "step " },
    { type = "reasoning", content = "by " },
    { type = "reasoning", content = "step." },
    { type = "llm", content = "Done thinking - here's the answer." },
  },

  tools_batch = {
    { type = "llm", content = "Reading the three modules." },
    { type = "tool", content = "read_file: a.lua\n-- contents of a" },
    { type = "tool", content = "read_file: b.lua\n-- contents of b" },
    { type = "tool", content = "read_file: c.lua\n-- contents of c" },
    { type = "llm", content = "Read all three files." },
  },
}

---Replay a logical profile straight through add_buf_message at a fixed cadence
---@param profile_name string
local function run_logical(profile_name)
  local events = profiles[profile_name]
  if not events then
    error(
      ("[ui.lua] Unknown profile %q. Available: %s"):format(profile_name, table.concat(vim.tbl_keys(profiles), ", "))
    )
  end

  local chat = require("codecompanion").chat({})
  local type_map = {
    reasoning = chat.MESSAGE_TYPES.REASONING_MESSAGE,
    llm = chat.MESSAGE_TYPES.LLM_MESSAGE,
    tool = chat.MESSAGE_TYPES.TOOL_MESSAGE,
  }

  local index = 0
  local function step()
    index = index + 1
    local event = events[index]
    if not event then
      return vim.notify("[ui.lua] Finished logical profile: " .. profile_name)
    end
    chat:add_buf_message(
      { role = event.role or "llm", content = event.content or "" },
      { type = type_map[event.type], status = event.status }
    )
    vim.defer_fn(step, DELAY_MS)
  end
  vim.defer_fn(step, DELAY_MS)
end

---Build an HTTP client stand-in that replays captured chunks through the real callbacks
---@param chunks string[] The lines read from a stub file
---@param is_stream boolean Whether to stream line-by-line or deliver one final body
---@return table A client exposing :send, matching the real client's contract
local function stub_client(chunks, is_stream)
  local handle = {
    id = "ui.lua",
    cancel = function() end,
    status = function()
      return "streaming"
    end,
  }
  local sent = false

  return {
    send = function(_, _payload, opts)
      -- Only replay once. Any follow-up request (e.g. a compaction check) gets an
      -- empty completion so the pipeline settles instead of looping on the fixture.
      if sent then
        vim.schedule(function()
          if opts.on_done then
            opts.on_done(nil, { id = "ui.lua" })
          end
        end)
        return handle
      end
      sent = true

      if not is_stream then
        vim.defer_fn(function()
          if opts.on_done then
            opts.on_done({ status = 200, body = table.concat(chunks, "\n") }, { id = "ui.lua" })
          end
        end, DELAY_MS)
        return handle
      end

      local index = 0
      local function step()
        index = index + 1
        local line = chunks[index]
        if line == nil then
          if opts.on_done then
            opts.on_done(nil, { id = "ui.lua" })
          end
          return
        end
        if line ~= "" and opts.on_chunk then
          opts.on_chunk(line, { id = "ui.lua" })
        end
        vim.defer_fn(step, DELAY_MS)
      end
      vim.defer_fn(step, DELAY_MS)
      return handle
    end,
  }
end

---Replay a captured adapter payload through the genuine chat pipeline
---@param adapter_name string
---@param stub_name string
local function run_stub(adapter_name, stub_name)
  local path = vim.fs.joinpath(stub_dir, stub_name .. ".txt")
  if vim.fn.filereadable(path) ~= 1 then
    error("[ui.lua] Stub not found: " .. path)
  end
  local chunks = vim.fn.readfile(path)
  if #chunks == 0 then
    error("[ui.lua] Stub is empty: " .. path)
  end

  local adapters = require("codecompanion.adapters")
  local cc_config = require("codecompanion.config")
  local resolved = adapters.resolve(cc_config.adapters.http[adapter_name] or adapter_name)
  local is_stream = not not (resolved and resolved.opts and resolved.opts.stream)

  -- get_client() caches the http module table and calls .new on it, so patching
  -- .new on the shared module reaches that cache whether or not it's warm. The patch
  -- stays for the session; the stub client absorbs any follow-up request, so nothing
  -- escapes to the network.
  local http = require("codecompanion.http")
  local client = stub_client(chunks, is_stream)
  http.new = function()
    return client
  end

  require("codecompanion").chat({
    params = { adapter = adapter_name },
    user_prompt = "[ui.lua] Replaying stub: " .. stub_name,
  })
end

if MODE == "logical" then
  run_logical(PROFILE)
elseif MODE == "stub" then
  run_stub(ADAPTER, STUB)
else
  error("[ui.lua] Unknown MODE: " .. tostring(MODE))
end
