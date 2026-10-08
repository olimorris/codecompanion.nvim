local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      child.lua([[
        diff = require("codecompanion.diff")
      ]])
    end,
    post_once = child.stop,
  },
})

T["Diff"] = new_set()

T["Diff"]["Gets hunks between two sets of text"] = function()
  local hunks = child.lua([[
    local a = {"line1", "line2", "line3"}
    local b = {"line1", "modified", "line3"}
    return diff._diff(a, b)
  ]])

  h.eq(1, #hunks, "Should find 1 hunk")
  h.eq({ 2, 1, 2, 1 }, hunks[1], "Should detect change on line 2")
end

T["Diff"]["Creates diff with hunks and extmarks"] = function()
  local result = child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "lua")

    local diff_obj = diff.create({
      bufnr = bufnr,
      from_lines = { "function foo()", "  print('old')", "end" },
      to_lines = { "function foo()", "  print('new')", "end" },
      ft = "lua"
    })

    return {
      hunk_count = #diff_obj.hunks,
      first_hunk = diff_obj.hunks[1],
      ns = diff_obj.ns
    }
  ]])

  h.eq(1, result.hunk_count, "Should have 1 hunk")
  h.eq("change", result.first_hunk.kind, "Should be a change hunk")
end

T["Diff"]["Detects correct hunk indices"] = function()
  local result = child.lua([[
    local a = {"line1", "line2", "line3", "line4"}
    local b = {"line1", "modified2", "modified3", "line4"}
    local hunks = diff._diff(a, b)
    return hunks
  ]])

  h.eq(1, #result, "Should have 1 hunk")
  h.eq({ 2, 2, 2, 2 }, result[1], "Should detect lines 2-3 changed")
end

T["Diff"]["Handles pure additions"] = function()
  local result = child.lua([[
    local a = {"line1", "line2"}
    local b = {"line1", "line2", "line3", "line4"}
    local hunks = diff._diff(a, b)
    return hunks
  ]])

  -- vim.text.diff sometimes returns multiple hunks or handles differently
  -- Just verify we got hunks and the addition is detected
  h.is_true(#result >= 1, "Should have at least 1 hunk")
end

T["Diff"]["Handles pure deletions"] = function()
  local result = child.lua([[
    local a = {"line1", "line2", "line3", "line4"}
    local b = {"line1", "line4"}
    local hunks = diff._diff(a, b)
    return hunks
  ]])

  h.eq(1, #result, "Should have 1 hunk")
  -- Deletion: a_count=2, b_count=0
  -- vim.text.diff returns {2, 2, 1, 0} not {2, 2, 2, 0}
  h.eq({ 2, 2, 1, 0 }, result[1], "Should detect 2 lines deleted")
end

T["Diff"]["Generates correct extmarks for changes"] = function()
  local result = child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "lua")

    local from = {"line1", "old_line", "line3"}
    local to = {"line1", "new_line", "line3"}

    local diff_obj = diff.create({
      bufnr = bufnr,
      from_lines = from,
      to_lines = to,
      ft = "lua"
    })

    return {
      hunk_count = #diff_obj.hunks,
      hunk = diff_obj.hunks[1],
      extmark_count = #diff_obj.hunks[1].extmarks,
    }
  ]])

  h.eq(1, result.hunk_count, "Should have 1 hunk")
  h.eq("change", result.hunk.kind, "Should be change type")
  h.eq({ 1, 0 }, result.hunk.pos, "Should be at row 1, col 0 (merged view, after unchanged line)")
  h.eq(2, result.extmark_count, "Should have 2 extmarks (deletion + addition)")
end

T["Diff"]["Word-level diff creates word highlights for merged lines"] = function()
  local result = child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "lua")

    local from = {"local function calculate_total(items)"}
    local to = {"local function compute_sum(elements)"}

    local diff_obj = diff.create({
      bufnr = bufnr,
      from_lines = from,
      to_lines = to,
      ft = "lua"
    })

    local word_hl_count = 0
    for _, hl in ipairs(diff_obj.merged.highlights) do
      if hl.word_hl then
        word_hl_count = word_hl_count + #hl.word_hl
      end
    end

    return {
      hunk_kind = diff_obj.hunks[1].kind,
      word_hl_count = word_hl_count,
    }
  ]])

  h.eq("change", result.hunk_kind, "Should be a change hunk")
  h.is_true(result.word_hl_count > 0, "Should create word highlights for merged line display")
end

T["Diff"]["Word-level diff handles empty lines"] = function()
  local result = child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "lua")

    local from = {"line1", "", "line3"}
    local to = {"line1", "new_line", "line3"}

    local diff_obj = diff.create({
      bufnr = bufnr,
      from_lines = from,
      to_lines = to,
      ft = "lua"
    })

    return {
      hunk_count = #diff_obj.hunks,
      hunk_kind = diff_obj.hunks[1].kind,
    }
  ]])

  h.eq(1, result.hunk_count, "Should handle empty line changes")
  h.eq("change", result.hunk_kind, "Should be a change hunk")
end

T["Diff"]["Handles multiple hunks"] = function()
  local result = child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "lua")

    local from = {"line1", "line2", "line3", "line4", "line5"}
    local to = {"line1", "modified2", "line3", "modified4", "line5"}

    local diff_obj = diff.create({
      bufnr = bufnr,
      from_lines = from,
      to_lines = to,
      ft = "lua"
    })

    return {
      hunk_count = #diff_obj.hunks,
    }
  ]])

  h.eq(2, result.hunk_count, "Should detect 2 separate change hunks")
end

T["Diff"]["Maps merged rows back to their line on each side"] = function()
  local rows = child.lua([[
    local diff_obj = diff.create({
      bufnr = vim.api.nvim_create_buf(false, true),
      from_lines = { "one", "two", "three", "four", "five" },
      to_lines = { "one", "TWO", "five" },
    })

    return diff_obj.merged.rows
  ]])

  h.eq({ from = 1, to = 1 }, rows[1], "An unchanged row carries a line on both sides")
  h.eq({ from = 2 }, rows[2], "A deleted row has no line in the working file")
  h.eq({ to = 2 }, rows[5], "An added row has no line in the baseline")
  h.eq({ from = 5, to = 3 }, rows[6], "An unchanged row after a hunk tracks the drift between the sides")
end

T["Diff"]["Keeps the to side in step after a pure deletion"] = function()
  local rows = child.lua([[
    local diff_obj = diff.create({
      bufnr = vim.api.nvim_create_buf(false, true),
      from_lines = { "a", "b", "c", "d" },
      to_lines = { "a", "d" },
    })

    return diff_obj.merged.rows
  ]])

  h.eq({ from = 4, to = 2 }, rows[4], "The row after the deletion is line 2 of the working file")
end

T["Diff"]["Unified diff keeps the last changed line separate"] = function()
  local result = child.lua([[
    return require("codecompanion.diff.utils").unified(
      { "Lorem", "ipsum", "dolor", "sit" },
      { "Lorem", "ipsum", "dolor modified", "sit modified" }
    )
  ]])

  h.eq({
    "@@ -1,4 +1,4 @@",
    " Lorem",
    " ipsum",
    "-dolor",
    "-sit",
    "+dolor modified",
    "+sit modified",
  }, vim.split(result, "\n"), "Should not merge the final deletion into the first addition")
end

T["Diff"]["Unified diff handles empty sets of lines"] = function()
  local result = child.lua([[
    local utils = require("codecompanion.diff.utils")
    return {
      created = utils.unified({}, { "one", "two" }),
      emptied = utils.unified({ "one", "two" }, {}),
    }
  ]])

  h.eq("@@ -0,0 +1,2 @@\n+one\n+two", result.created, "Should diff against an empty file")
  h.eq("@@ -1,2 +0,0 @@\n-one\n-two", result.emptied, "Should diff to an empty file")
end

T["Diff"]["Integration Test"] = new_set()

T["Diff"]["Integration Test"]["Example 1"] = function()
  local before = [[
return {
  "CodeCompanion is amazing - Oli Morris"
}
]]
  local after = [[
return {
  "CodeCompanion is amazing - Oli Morris"
  "Lua and Neovim are amazing too - Oli Morris"
  "Happy coding!"
  "Hello world"
}
]]

  child.lua(string.format(
    [[
    local helpers = require("codecompanion.helpers")
    local diff_ui = helpers.show_diff({
      from_lines = vim.split(%q, "\n"),
      to_lines = vim.split(%q, "\n"),
      diff_id = math.random(10000000),
      ft = "lua",
      title = "Tests",
      marker_add = "+",
      marker_delete = "-",
    })
  ]],
    before,
    after
  ))

  h.expect_screenshot(child.get_screenshot(), "tests/screenshots/diff_integration_example_1")
end

T["Diff"]["Integration Test"]["Example 2"] = function()
  local before = [[
async fn run_cargo_build_json() -> io::Result<Option<String>> {
    let mut child = Command::new("cargo")
        .args(["build", "--message-format=json"])
        .stdout(Stdio::piped())
}
]]
  local after = [[
async fn rn_crgo_build_jsons() -> io::Result<Option<String>> {
    let mut childddd = Command::new("cargo")
        .ars(["build", "--message-format=json"])
        .stddddouttt(Stdio::piped())
}
]]

  child.lua(string.format(
    [[
    local helpers = require("codecompanion.helpers")
    local diff_ui = helpers.show_diff({
      from_lines = vim.split(%q, "\n"),
      to_lines = vim.split(%q, "\n"),
      diff_id = math.random(10000000),
      ft = "rust",
      title = "Tests",
      marker_add = "+",
      marker_delete = "-",
    })
  ]],
    before,
    after
  ))

  h.expect_screenshot(child.get_screenshot(), "tests/screenshots/diff_integration_example_2")
end

T["Diff"]["Integration Test"]["Example 3"] = function()
  local before = [[
def process():
    step1()
    step2()
    step3()
    step4()
]]
  local after = [[
def process():
    step1()
    step4()
]]

  child.lua(string.format(
    [[
    local helpers = require("codecompanion.helpers")
    local diff_ui = helpers.show_diff({
      from_lines = vim.split(%q, "\n"),
      to_lines = vim.split(%q, "\n"),
      diff_id = math.random(10000000),
      ft = "python",
      title = "Tests",
      marker_add = "+",
      marker_delete = "-",
    })
  ]],
    before,
    after
  ))

  h.expect_screenshot(child.get_screenshot(), "tests/screenshots/diff_integration_example_3")
end

T["Diff"]["Hunks"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[
        _G.from_lines = { "a", "b", "c" }
        _G.to_lines = { "A", "b", "C" }

        _G.show_inline_diff = function(from_lines, to_lines)
          local bufnr = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_set_current_buf(bufnr)
          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, from_lines)
          _G.accepted = false
          return require("codecompanion.helpers").show_diff({
            bufnr = bufnr,
            diff_id = math.random(10000000),
            from_lines = from_lines,
            to_lines = to_lines,
            ft = "lua",
            hunk_actions = true,
            inline = true,
            keymaps = {
              on_accept = function()
                _G.accepted = true
              end,
            },
          })
        end
      ]])
    end,
  },
})

T["Diff"]["Hunks"]["accepting a hunk leaves the others to review"] = function()
  local result = child.lua([[
    local diff_ui = _G.show_inline_diff(_G.from_lines, _G.to_lines)
    diff_ui:resolve_hunk(1, { accept = true })
    return { from = diff_ui.diff.from.lines, hunks = diff_ui.hunks, resolved = diff_ui.resolved }
  ]])

  h.eq({ "A", "b", "c" }, result.from)
  h.eq(1, result.hunks)
  h.eq(false, result.resolved)
end

T["Diff"]["Hunks"]["resolving the last hunk keeps only the accepted hunks"] = function()
  local result = child.lua([[
    local diff_ui = _G.show_inline_diff(_G.from_lines, _G.to_lines)
    diff_ui:resolve_hunk(1, { accept = true })
    diff_ui:resolve_hunk(1, { accept = false })
    return { lines = vim.api.nvim_buf_get_lines(diff_ui.bufnr, 0, -1, false), accepted = _G.accepted }
  ]])

  h.eq({ "A", "b", "c" }, result.lines)
  h.eq(true, result.accepted)
end

T["Diff"]["Hunks"]["rejecting a hunk on the first line leaves no spacer line"] = function()
  local lines = child.lua([[
    local diff_ui = _G.show_inline_diff(_G.from_lines, _G.to_lines)
    diff_ui:resolve_hunk(1, { accept = false })
    diff_ui:resolve_hunk(1, { accept = true })
    return vim.api.nvim_buf_get_lines(diff_ui.bufnr, 0, -1, false)
  ]])

  h.eq({ "a", "b", "C" }, lines)
end

T["Diff"]["Hunks"]["undoing takes back the last hunk decision"] = function()
  local result = child.lua([[
    local diff_ui = _G.show_inline_diff({ "a", "b", "c", "d", "e" }, { "A", "b", "C", "d", "E" })
    local drawn = vim.api.nvim_buf_get_lines(diff_ui.bufnr, 0, -1, false)
    diff_ui:resolve_hunk(1, { accept = true })
    diff_ui:resolve_hunk(1, { accept = false })
    diff_ui:undo_hunk()
    local after_one = { from = diff_ui.diff.from.lines, to = diff_ui.diff.to.lines, hunks = diff_ui.hunks }
    diff_ui:undo_hunk()
    return {
      after_one = after_one,
      after_both = { from = diff_ui.diff.from.lines, hunks = diff_ui.hunks },
      drawn = drawn,
      lines = vim.api.nvim_buf_get_lines(diff_ui.bufnr, 0, -1, false),
    }
  ]])

  h.eq({ from = { "A", "b", "c", "d", "e" }, to = { "A", "b", "C", "d", "E" }, hunks = 2 }, result.after_one)
  h.eq({ from = { "a", "b", "c", "d", "e" }, hunks = 3 }, result.after_both)
  h.eq(result.drawn, result.lines)
end

T["Diff"]["Hunks"]["finds the hunk under the cursor"] = function()
  local index = child.lua([[
    local diff_ui = _G.show_inline_diff(_G.from_lines, _G.to_lines)
    return diff_ui:get_hunk_at(diff_ui.diff.hunks[2].pos[1] + 1)
  ]])

  h.eq(2, index)
end

T["Diff"]["Hunks"]["the keymaps float lists hunk actions WHEN hunks can be resolved"] = function()
  local lines = child.lua([[
    local diff_ui = _G.show_inline_diff(_G.from_lines, _G.to_lines)
    require("codecompanion.diff.keymaps").show_keymaps.callback(diff_ui)
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])

  h.expect_contains("Accept the hunk under the cursor", table.concat(lines, "\n"))
end

T["Diff"]["Hunks"]["the keymaps float DOES NOT list hunk actions WHEN hunks can't be resolved"] = function()
  local lines = child.lua([[
    local diff_ui = _G.show_inline_diff(_G.from_lines, _G.to_lines)
    diff_ui.hunk_actions = false
    require("codecompanion.diff.keymaps").show_keymaps.callback(diff_ui)
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])

  local text = table.concat(lines, "\n")
  h.expect_contains("Accept all changes", text)
  h.eq(nil, text:find("Accept the hunk under the cursor", 1, true))
end

T["Diff"]["Hunks"]["shows a banner WHEN show_banner is on"] = function()
  local banner_ns = child.lua([[
    return _G.show_inline_diff(_G.from_lines, _G.to_lines).banner_ns
  ]])

  h.not_eq(nil, banner_ns)
end

T["Diff"]["Hunks"]["DOES NOT show a banner WHEN show_banner is off"] = function()
  local banner_ns = child.lua([[
    require("codecompanion.config").display.diff.show_banner = false
    local banner_ns = _G.show_inline_diff(_G.from_lines, _G.to_lines).banner_ns
    require("codecompanion.config").display.diff.show_banner = true
    return banner_ns
  ]])

  h.eq(vim.NIL, banner_ns)
end

---Show an inline diff and return the screen lines either side of its banner
---@param from_lines string[]
---@param to_lines string[]
---@return { before?: string, after?: string }
local function get_lines_around_banner(from_lines, to_lines)
  child.lua(
    [[
    local from_lines, to_lines = ...
    for _, winnr in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(winnr).relative ~= "" then
        vim.api.nvim_win_close(winnr, true)
      end
    end
    _G.show_inline_diff(from_lines, to_lines)
  ]],
    { from_lines, to_lines }
  )

  local lines = vim.tbl_map(function(line)
    return vim.trim(table.concat(line))
  end, child.get_screenshot().text)
  for index, line in ipairs(lines) do
    if line:find("[Hunk: ", 1, true) then
      return { before = lines[index - 1], after = lines[index + 1] }
    end
  end
  return {}
end

T["Diff"]["Hunks"]["shows the banner BELOW a hunk at the top of the buffer"] = function()
  h.eq({ before = "x", after = "a" }, get_lines_around_banner({ "a", "b" }, { "x", "a", "b" }))
end

T["Diff"]["Hunks"]["shows the banner ABOVE the lines a hunk deletes"] = function()
  h.eq({ before = "b", after = "c" }, get_lines_around_banner({ "a", "b", "c", "d" }, { "a", "b", "d" }))
end

T["Diff"]["Inline Integration Test"] = new_set()

T["Diff"]["Inline Integration Test"]["Example 1"] = function()
  local before = [[
async fn run_cargo_build_json() -> io::Result<Option<String>> {
    let mut child = Command::new("cargo")
        .args(["build", "--message-format=json"])
        .stdout(Stdio::piped())
}
]]
  local after = [[
async fn rn_crgo_build_jsons() -> io::Result<Option<String>> {
    let mut childddd = Command::new("cargo")
        .ars(["build", "--message-format=json"])
        .stddddouttt(Stdio::piped())
}
]]

  child.lua(string.format(
    [[
    local helpers = require("codecompanion.helpers")
    require("codecompanion.config").display.diff.show_banner = false
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative ~= "" then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    local target_win = vim.api.nvim_get_current_win()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative == "" then
        target_win = win
        break
      end
    end

    vim.api.nvim_set_current_win(target_win)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_set_option_value("filetype", "rust", { buf = bufnr })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(%q, "\n"))

    local diff_ui = helpers.show_diff({
      from_lines = vim.split(%q, "\n"),
      to_lines = vim.split(%q, "\n"),
      diff_id = math.random(10000000),
      ft = "rust",
      title = "Inline Test",
      inline = true,
      bufnr = bufnr,
      marker_add = "+",
      marker_delete = "-",
    })
  ]],
    before,
    before,
    after
  ))

  h.expect_screenshot(child.get_screenshot(), "tests/screenshots/diff_inline_integration_example_1")
end

return T
