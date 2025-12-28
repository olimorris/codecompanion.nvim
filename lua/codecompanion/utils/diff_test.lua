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
  {
    name = "No treesitter parser - Fortran",
    filetype = "fortran",
    before = [[
PROGRAM HelloWorld
  IMPLICIT NONE
  INTEGER :: counter
  counter = 10
  PRINT *, 'Hello, World!'
  PRINT *, 'Counter:', counter
END PROGRAM HelloWorld
]],
    after = [[
PROGRAM HelloUniverse
  IMPLICIT NONE
  INTEGER :: count
  count = 20
  PRINT *, 'Hello, Universe!'
  PRINT *, 'Count:', count
END PROGRAM HelloUniverse
]],
  },
}

---Create a test command for visual diff testing
function M.setup()
  vim.api.nvim_create_user_command("CodeCompanionDiffTest", function(opts)
    local test_num = tonumber(opts.args) or 1
    M.run_visual_test(test_num)
  end, {
    desc = "Test CodeCompanion diff provider (optional: test case number 1-" .. #M.test_cases .. ")",
    nargs = "?",
  })
end

---Run the visual diff test
---@param test_num? number Test case number (1-based)
function M.run_visual_test(test_num)
  test_num = test_num or 1

  if test_num < 1 or test_num > #M.test_cases then
    vim.notify(string.format("Invalid test case %d. Available: 1-%d", test_num, #M.test_cases), vim.log.levels.ERROR)
    return
  end

  local test_case = M.test_cases[test_num]
  local before_lines = vim.split(test_case.before, "\n", { plain = true })
  local after_lines = vim.split(test_case.after, "\n", { plain = true })

  local helpers = require("codecompanion.helpers")
  local diff_id = math.random(10000000)

  local diff_obj, bufnr, winnr = helpers.show_diff({
    from_lines = before_lines,
    to_lines = after_lines,
    ft = test_case.filetype,
    title = string.format("%s (Test %d/%d)", test_case.name, test_num, #M.test_cases),
    diff_id = diff_id,
  })

  -- Add keymaps for cycling through test cases
  local keymap_opts = { buffer = bufnr, silent = true, nowait = true }

  vim.keymap.set("n", "n", function()
    local next_test = test_num % #M.test_cases + 1
    local Diff = require("codecompanion.diff")
    Diff.clear(diff_obj)
    if vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_close(winnr, true)
    end
    M.run_visual_test(next_test)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Next test case" }))

  vim.keymap.set("n", "p", function()
    local prev_test = test_num == 1 and #M.test_cases or test_num - 1
    local Diff = require("codecompanion.diff")
    Diff.clear(diff_obj)
    if vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_close(winnr, true)
    end
    M.run_visual_test(prev_test)
  end, vim.tbl_extend("force", keymap_opts, { desc = "Previous test case" }))

  -- Listen for diff events
  local group = vim.api.nvim_create_augroup("CodeCompanionDiffTest_" .. diff_id, { clear = true })

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionDiffAccepted",
    group = group,
    callback = function(event)
      if event.data.diff_id == diff_id then
        vim.notify(
          string.format("Test %d/%d: Changes ACCEPTED", test_num, #M.test_cases),
          vim.log.levels.INFO,
          { title = "CodeCompanion Diff Test" }
        )
        vim.api.nvim_del_augroup_by_id(group)
      end
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionDiffRejected",
    group = group,
    callback = function(event)
      if event.data.diff_id == diff_id then
        local status = event.data.timeout and "CLOSED" or "REJECTED"
        vim.notify(
          string.format("Test %d/%d: Changes %s", test_num, #M.test_cases, status),
          vim.log.levels.WARN,
          { title = "CodeCompanion Diff Test" }
        )
        vim.api.nvim_del_augroup_by_id(group)
      end
    end,
  })

  return diff_obj
end

return M
