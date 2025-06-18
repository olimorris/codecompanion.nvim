local h = require("tests.helpers")
local patch = require("codecompanion.strategies.chat.agents.tools.helpers.patch")

local new_set = MiniTest.new_set

local function readfile(path)
  local lines = vim.fn.readfile(path)
  return table.concat(lines, "\n")
end

local function apply_patch(input_str, patch_str)
  -- 1. parse changes
  local changes, had_begin_end_markers = patch.parse_changes(patch_str)

  -- 2. read file into lines
  local lines = vim.split(input_str, "\n", { plain = true })

  -- 3. apply changes
  for _, change in ipairs(changes) do
    local new_lines = patch.apply_change(lines, change)
    if new_lines == nil then
      if had_begin_end_markers then
        error(string.format("Bad/Incorrect diff:\n\n%s\n\nNo changes were applied", patch.get_change_string(change)))
      else
        error("Invalid patch format: missing Begin/End markers")
      end
    else
      lines = new_lines
    end
  end
  return table.concat(lines, "\n")
end

T = new_set()

T["patch"] = new_set()
T["patch"]["simple patch"] = function()
  local input_str = "line1\nline2\nline3"
  local patch_str = "*** Begin Patch\nline1\n-line2\n+new_line2\nline3\n*** End Patch"
  local output_str = apply_patch(input_str, patch_str)
  local expected_output = "line1\nnew_line2\nline3"
  h.eq(output_str, expected_output)
end

T["patch"]["lines starting by '-'"] = function()
  local input_str = "- item1"
  local patch_str = "*** Begin Patch\n - item1\n+- item2\n*** End Patch"
  local output_str = apply_patch(input_str, patch_str)
  local expected_output = "- item1\n- item2"
  h.eq(output_str, expected_output)
end

T["patch"]["simple test from fixtures"] = function()
  local input_str = readfile("tests/fixtures/files-input-1.html")
  local patch_str = readfile("tests/fixtures/files-diff-1.1.patch")
  local output_str = apply_patch(input_str, patch_str)
  local expected_output = readfile("tests/fixtures/files-output-1.1.html")
  h.eq(output_str, expected_output)
end

T["patch"]["empty lines"] = function()
  local input_str = readfile("tests/fixtures/files-input-1.html")
  local patch_str = readfile("tests/fixtures/files-diff-1.3.patch")
  local output_str = apply_patch(input_str, patch_str)
  local expected_output = readfile("tests/fixtures/files-output-1.3.html")
  h.eq(output_str, expected_output)
end

T["patch"]["multiple patches"] = function()
  local input_str = readfile("tests/fixtures/files-input-1.html")
  local patch_str = readfile("tests/fixtures/files-diff-1.4.patch")
  local output_str = apply_patch(input_str, patch_str)
  local expected_output = readfile("tests/fixtures/files-output-1.4.html")
  h.eq(output_str, expected_output)
end

T["patch"]["no BEGIN and END markers"] = function()
  local input_str = readfile("tests/fixtures/files-input-1.html")
  local patch_str = readfile("tests/fixtures/files-diff-1.5.patch")
  local output_str = apply_patch(input_str, patch_str)
  local expected_output = readfile("tests/fixtures/files-output-1.5.html")
  h.eq(output_str, expected_output)
end

T["patch"]["multiple continuation"] = function()
  local input_str = readfile("tests/fixtures/files-input-2.html")
  local patch_str = readfile("tests/fixtures/files-diff-2.1.patch")
  local output_str = apply_patch(input_str, patch_str)
  local expected_output = readfile("tests/fixtures/files-output-2.1.html")
  h.eq(output_str, expected_output)
end

T["patch"]["spaces"] = function()
  local input_str = readfile("tests/fixtures/files-input-2.html")
  local patch_str = readfile("tests/fixtures/files-diff-2.2.patch")
  local output_str = apply_patch(input_str, patch_str)
  local expected_output = readfile("tests/fixtures/files-output-2.2.html")
  h.eq(output_str, expected_output)
end

T["patch"]["html spaces flexible"] = function()
  local input_str = readfile("tests/fixtures/files-input-3.html")
  local patch_str = readfile("tests/fixtures/files-diff-3.patch")
  local output_str = apply_patch(input_str, patch_str)
  local expected_output = readfile("tests/fixtures/files-output-3.html")
  h.eq(output_str, expected_output)
end

T["patch"]["html line breaks"] = function()
  local input_str = readfile("tests/fixtures/files-input-4.html")
  local patch_str = readfile("tests/fixtures/files-diff-4.patch")
  local output_str = apply_patch(input_str, patch_str)
  local expected_output = readfile("tests/fixtures/files-output-4.html")
  h.eq(output_str, expected_output)
end

T["patch"]["lua dashes"] = function()
  local input_str = readfile("tests/fixtures/files-input-5.lua")
  local patch_str = readfile("tests/fixtures/files-diff-5.patch")
  local output_str = apply_patch(input_str, patch_str)
  local expected_output = readfile("tests/fixtures/files-output-5.lua")
  h.eq(output_str, expected_output)
end

return T
