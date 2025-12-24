---@brief Visual testing utility for CodeCompanion diff implementation
---
---This module provides a command to visually test the diff provider with multiple test cases.

local M = {}

---Test cases for diff visualization
M.test_cases = {
  {
    name = "Zed Example - Multiple small changes",
    filetype = "rust",
    before = [[
async fn run_cargo_build_json() -> io::Result<Option<String>> {
    let mut child = Command::new("cargo")
        .args(["build", "--message-format=json"])
        .stdout(Stdio::piped())
}
]],
    after = [[
async fn rn_crgo_build_jsons() -> io::Result<Option<String>> {
    let mut childddd = Command::new("cargo")
        .ars(["build", "--message-format=json"])
        .stddddouttt(Stdio::piped())
}
]],
  },
  {
    name = "Simple rename",
    filetype = "lua",
    before = [[
local function calculate_sum(numbers)
  local total = 0
  for _, num in ipairs(numbers) do
    total = total + num
  end
  return total
end
]],
    after = [[
local function compute_total(numbers)
  local total = 0
  for _, num in ipairs(numbers) do
    total = total + num
  end
  return total
end
]],
  },
  {
    name = "Word additions",
    filetype = "javascript",
    before = [[
function fetchData(url) {
  return fetch(url)
    .then(response => response.json())
    .catch(error => console.error(error));
}
]],
    after = [[
async function fetchUserData(url) {
  return fetch(url)
    .then(response => response.json())
    .catch(error => console.error("Failed:", error));
}
]],
  },
  {
    name = "Inline parameter change",
    filetype = "python",
    before = [[
def process_data(data, limit=10):
    results = []
    for item in data[:limit]:
        results.append(item.upper())
    return results
]],
    after = [[
def process_data(data, max_items=100):
    results = []
    for item in data[:max_items]:
        results.append(item.upper())
    return results
]],
  },
  {
    name = "Line additions",
    filetype = "lua",
    before = [[
local M = {}

function M.setup()
  print("setup")
end

return M
]],
    after = [[
local M = {}

function M.setup()
  print("setup")
  vim.notify("initialized")
end

function M.teardown()
  print("teardown")
end

return M
]],
  },
  {
    name = "Line deletions",
    filetype = "python",
    before = [[
def process():
    step1()
    step2()
    step3()
    step4()
]],
    after = [[
def process():
    step1()
    step4()
]],
  },
}

---Create a test command for visual diff testing
function M.setup()
  vim.api.nvim_create_user_command("CodeCompanionDiffTest", function(opts)
    local test_num = tonumber(opts.args) or 1
    M.run_visual_test(test_num, "new")
  end, {
    desc = "Test CodeCompanion diff provider (optional: test case number 1-" .. #M.test_cases .. ")",
    nargs = "?",
  })

  vim.api.nvim_create_user_command("CodeCompanionDiffTestOld", function(opts)
    local test_num = tonumber(opts.args) or 1
    M.run_visual_test(test_num, "old")
  end, {
    desc = "Test old inline diff provider (optional: test case number 1-" .. #M.test_cases .. ")",
    nargs = "?",
  })
end

---Run the visual diff test
---@param test_num? number Test case number (1-based)
---@param provider? "new"|"old" Which diff provider to use (default: "new")
function M.run_visual_test(test_num, provider)
  test_num = test_num or 1
  provider = provider or "new"

  if test_num < 1 or test_num > #M.test_cases then
    vim.notify(string.format("Invalid test case %d. Available: 1-%d", test_num, #M.test_cases), vim.log.levels.ERROR)
    return
  end

  local test_case = M.test_cases[test_num]
  local before_content = test_case.before
  local after_content = test_case.after

  -- Create a new buffer with the "after" content
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(bufnr, "filetype", test_case.filetype)

  -- Split content into lines
  local after_lines = vim.split(after_content, "\n", { plain = true })
  local before_lines = vim.split(before_content, "\n", { plain = true })

  -- Set buffer content to "after" state
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, after_lines)

  -- Create floating window
  local width = math.min(100, vim.o.columns - 10)
  local height = math.min(25, vim.o.lines - 5)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local title = string.format(" %s (Test %d/%d) ", test_case.name, test_num, #M.test_cases)
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  }

  local winnr = vim.api.nvim_open_win(bufnr, true, win_opts)

  -- Create the diff using the specified provider
  local diff_obj
  if provider == "old" then
    local InlineDiff = require("codecompanion.providers.diff.inline")
    diff_obj = InlineDiff.new({
      bufnr = bufnr,
      contents = before_lines,
      id = "test_diff_old_" .. os.time(),
      is_floating = true,
      show_hints = false,
      winnr = winnr,
    })
  else
    -- New diff provider
    local Diff = require("codecompanion.diff")
    diff_obj = Diff.create({
      bufnr = bufnr,
      from_lines = before_lines,
      to_lines = after_lines,
      ft = test_case.filetype,
    })

    -- Apply the diff visualization
    Diff.apply(diff_obj)
  end

  -- Set up keymaps for testing
  local keymap_opts = { buffer = bufnr, silent = true }

  -- Navigation keymaps (placeholder for future hunk navigation)
  vim.keymap.set("n", "]c", function()
    vim.notify("Hunk navigation not yet implemented", vim.log.levels.INFO)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Next hunk (TODO)" }))

  vim.keymap.set("n", "[c", function()
    vim.notify("Hunk navigation not yet implemented", vim.log.levels.INFO)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Previous hunk (TODO)" }))

  vim.keymap.set("n", "ga", function()
    vim.notify("Per-hunk accept not yet implemented", vim.log.levels.INFO)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Accept hunk (TODO)" }))

  vim.keymap.set("n", "gr", function()
    vim.notify("Per-hunk reject not yet implemented", vim.log.levels.INFO)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Reject hunk (TODO)" }))

  vim.keymap.set("n", "gA", function()
    -- Accept all: replace buffer with "to" lines
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, after_lines)

    if provider == "new" then
      local Diff = require("codecompanion.diff")
      Diff.clear(diff_obj)
    else
      diff_obj:reject()
    end

    vim.notify("All changes accepted", vim.log.levels.INFO)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Accept all" }))

  vim.keymap.set("n", "gR", function()
    -- Reject all: replace buffer with "from" lines
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, before_lines)

    if provider == "new" then
      local Diff = require("codecompanion.diff")
      Diff.clear(diff_obj)
    else
      diff_obj:reject()
    end

    vim.notify("All changes rejected", vim.log.levels.INFO)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Reject all" }))

  vim.keymap.set("n", "n", function()
    -- Cycle to next test case
    local next_test = test_num % #M.test_cases + 1

    if provider == "new" then
      local Diff = require("codecompanion.diff")
      Diff.clear(diff_obj)
    else
      diff_obj:teardown()
    end

    if vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_close(winnr, true)
    end
    M.run_visual_test(next_test, provider)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Next test case" }))

  vim.keymap.set("n", "p", function()
    -- Cycle to previous test case
    local prev_test = test_num == 1 and #M.test_cases or test_num - 1

    if provider == "new" then
      local Diff = require("codecompanion.diff")
      Diff.clear(diff_obj)
    else
      diff_obj:teardown()
    end

    if vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_close(winnr, true)
    end
    M.run_visual_test(prev_test, provider)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Previous test case" }))

  vim.keymap.set("n", "q", function()
    if provider == "new" then
      local Diff = require("codecompanion.diff")
      Diff.clear(diff_obj)
    else
      diff_obj:teardown()
    end

    if vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_close(winnr, true)
    end
  end, vim.tbl_extend("force", keymap_opts, { desc = "Close" }))

  -- Show instructions
  local provider_name = provider == "old" and "Old Inline" or "New"
  local keymaps_msg = "Keymaps:\n  n/p - Next/prev test case\n  gA/gR - Accept/reject all"
  keymaps_msg = keymaps_msg .. "\n  ]c/[c/ga/gr - TODO (hunk navigation)"
  keymaps_msg = keymaps_msg .. "\n  q - Quit"

  vim.notify(
    string.format("%s Diff Test %d/%d: %s\n\n%s", provider_name, test_num, #M.test_cases, test_case.name, keymaps_msg),
    vim.log.levels.INFO,
    { title = "CodeCompanion Diff Test" }
  )

  return diff_obj
end

return M
