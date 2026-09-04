-- Tool output must be wrapped in a code fence that its own payload cannot
-- terminate.
--
-- The chat buffer is rendered as Markdown, so the measurement instrument here is
-- Tree-sitter: what it sees is what the user sees. A wrapper whose fence is a
-- fixed four backticks is closed early by any payload line that starts with four
-- or more backticks, which truncates the payload; the wrapper's own closing fence
-- then *opens* a block, inverting fence parity for the rest of the buffer.
--
-- The primary assertion is payload survival rather than the number of blocks:
-- an orphaned fence at the very end of a string does not always materialise as a
-- `fenced_code_block` node, so counting alone can miss the corruption.
--
-- Run with `make test_file FILE=tests/interactions/chat/test_fence_integrity.lua`.
local h = require("tests.helpers")
local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

---Is `line` (1-based) inside any of the given block ranges?
---@param ranges table[] List of { start_line, end_line }, 1-based inclusive
---@param line number
---@return boolean
local function inside(ranges, line)
  for _, range in ipairs(ranges) do
    if line >= range[1] and line <= range[2] then
      return true
    end
  end
  return false
end

---Format `payload` with the real MCP tool bridge, then recover what a Markdown
---reader actually sees: the first code block's content, and how many blocks the
---wrapper produced.
---@param payload string
---@return { blocks: number, content: string|nil }
local function roundtrip(payload)
  return child.lua_get(
    [[(function(payload)
      -- Complete the final line: the chat buffer always holds whole lines, and a
      -- closing fence at end-of-string with no trailing newline is not recognised
      -- as a closer, which would be an artefact of the harness rather than a defect.
      local markdown = _G.format_mcp_result(payload) .. '\n'
      local parser = vim.treesitter.get_string_parser(markdown, 'markdown')
      local tree = parser:parse()[1]
      local query = vim.treesitter.query.parse('markdown', '(code_fence_content) @content')
      local content
      for _, node in query:iter_captures(tree:root(), markdown) do
        content = content or vim.treesitter.get_node_text(node, markdown)
      end
      return { blocks = #_G.blocks(markdown), content = content }
    end)(...)]],
    { payload }
  )
end

---Assert that `payload` survives being wrapped, in exactly one code block
---@param payload string
---@return nil
local function expect_survives(payload)
  local result = roundtrip(payload)
  h.eq(payload .. "\n", result.content)
  h.eq(1, result.blocks)
end

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        _G.chat, _G.tools = h.setup_chat_buffer()

        --- Count the `fenced_code_block` nodes in a Markdown string.
        --- @return table[] List of { start_line, end_line }, 1-based inclusive
        _G.blocks = function(markdown)
          local parser = vim.treesitter.get_string_parser(markdown, 'markdown')
          local tree = parser:parse()[1]
          local query = vim.treesitter.query.parse('markdown', '(fenced_code_block) @block')
          local ranges = {}
          for _, node in query:iter_captures(tree:root(), markdown) do
            local start_row, _, end_row, _ = node:range()
            ranges[#ranges + 1] = { start_row + 1, end_row }
          end
          return ranges
        end

        --- Run the real `mcp/tool_bridge` success handler over `payload` and
        --- return the exact string it would put in the chat buffer. The chat is
        --- stubbed so nothing but the formatter is exercised.
        _G.format_mcp_result = function(payload)
          local bridge = require('codecompanion.mcp.tool_bridge')
          -- `build` returns (name, tool_cfg); the tool itself is behind the
          -- registry callback, which is how CodeCompanion instantiates it.
          local _, tool_cfg = bridge.build(
            { name = 'srv', cfg = {} },
            { name = 'echo', description = 'echoes', inputSchema = { type = 'object' } }
          )
          local tool = tool_cfg.callback()
          local captured
          local fake_chat = {
            add_tool_output = function(_, _, _, for_user)
              captured = for_user
            end,
          }
          tool.output.success(tool, { payload }, { tools = { chat = fake_chat } })
          return captured
        end

        --- A tool call, as the orchestrator would hand it to `add_tool_output`.
        _G.tool_call = function(id)
          return {
            name = 'srv_echo',
            function_call = {
              id = id,
              type = 'function',
              ['function'] = { name = 'srv_echo', arguments = '{}' },
            },
          }
        end
      ]])
    end,
    post_case = function()
      child.lua([[h.teardown_chat_buffer()]])
    end,
    post_once = child.stop,
  },
})

T["Fence integrity"] = new_set()

T["Fence integrity"]["a payload with no backticks survives"] = function()
  expect_survives("Exit Code: 0\nhello")
end

T["Fence integrity"]["a payload containing a bare four-backtick line survives"] = function()
  expect_survives("a\n````\nb")
end

T["Fence integrity"]["a four-backtick line indented by three spaces survives"] = function()
  expect_survives("a\n   ````\nb")
end

T["Fence integrity"]["a four-backtick line indented by four spaces survives"] = function()
  expect_survives("a\n    ````\nb")
end

T["Fence integrity"]["a five-backtick line survives"] = function()
  expect_survives("a\n`````\nb")
end

T["Fence integrity"]["a three-backtick block survives and stays inside one block"] = function()
  expect_survives("a\n```\nb\n```\nc")
end

T["Fence integrity"]["a fenced Markdown document survives"] = function()
  expect_survives("# Title\n\n````lua\nlocal x = 1\n````\n\nProse.")
end

T["Fence integrity"]["a second tool result is not swallowed by the first"] = function()
  child.lua([[
    _G.chat:add_tool_output(_G.tool_call('call_1'), 'llm-1', _G.format_mcp_result('a\n````\nb'))
    _G.chat:add_tool_output(_G.tool_call('call_2'), 'llm-2', _G.format_mcp_result('plain output'))
  ]])

  local result = child.lua_get([[(function()
    local lines = vim.api.nvim_buf_get_lines(_G.chat.bufnr, 0, -1, false)
    local headers = {}
    for i, line in ipairs(lines) do
      if line:match('^MCP: srv_echo executed successfully:$') then
        headers[#headers + 1] = i
      end
    end
    return { blocks = _G.blocks(table.concat(lines, '\n')), headers = headers }
  end)()]])

  h.eq(2, #result.headers)
  -- The orphaned fence of the first result must not have swallowed the second
  -- result's header line into a code block.
  h.eq(false, inside(result.blocks, result.headers[2]))
end

return T
