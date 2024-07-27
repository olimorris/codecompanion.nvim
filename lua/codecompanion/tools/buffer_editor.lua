local log = require("codecompanion.utils.log")
local config = require("codecompanion").config
local xml2lua = require("codecompanion.utils.xml.xml2lua")

local M = {}

M.schema = {
  parameters = {
    inputs = {
      content = "string containing file paths and SEARCH/REPLACE blocks",
    },
  },
  name = "buffer_editor",
}

M.system_prompt = function(schema)
  return [[You are an expert in writing and reviewing code. Always use best practices when coding. If the user request is ambiguous, ask questions. Always reply to the user in the same language they are using.

Once you understand the request you MUST:
1. Decide if you need to use block editor to edits any files that haven't been added to the chat. You can create new files without asking.  You can keep asking if you then decide you need to edit more files.
2. Think step-by-step and explain the needed changes with a numbered list of short sentences.

To aid you further, I'm giving you access to a block editor that can make changes to the code in the current buffer. This enables you to propose edits, trigger their execution, and immediately see the results of your efforts.

To use the block editor, you need to return an XML markdown code block (with backticks) which follows the below schema:
```xml
]] .. xml2lua.toXml(schema, "tool") .. [[

```
The content parameter should contain one or more SEARCH/REPLACE blocks, wrapped in a CDATA section. Each block MUST have the following exact format:

<content><![CDATA[
file_path
<<<<<<< SEARCH
[exact lines to search for]
=======
[lines to replace with]
>>>>>>> REPLACE
]] .. "]]>" .. [[></content>

IMPORTANT RULES:
1. The SEARCH section must EXACTLY match the existing code, including all whitespace, comments, and indentation.
2. Do not include any explanations or additional text outside the XML and SEARCH/REPLACE blocks.
3. The REPLACE section should contain the new or modified code.
4. You can include multiple SEARCH/REPLACE blocks for different files or different parts of the same file within the same CDATA section.
5. Always wrap your entire response in a code block with XML syntax highlighting.
6. Always use CDATA to wrap the content to avoid XML parsing issues with special characters in the code.
7. DO NOT include line numbers in either the SEARCH or REPLACE sections. Line numbers are provided for your reference only and should not be part of the actual code blocks.
8. For empty lines in the SEARCH section, do not include any whitespace characters. Just use a blank line.
9. In the REPLACE section, maintain the same indentation as the original code for consistency.
10. Each SEARCH/REPLACE should contain as few modifications as possible
11. Please use tabs instead of spaces for indentation

Be extremely careful and precise when creating these blocks. If the SEARCH section doesn't match exactly, the edit will fail.

Here's an example of how to use the buffer_editor tool:

```xml
<tool>
  <name>buffer_editor</name>
  <parameters>
    <inputs>
      <content><![CDATA[
/Users/user/projects/myproject/main.go
<<<<<<< SEARCH
func main() {
    fmt.Println("Hello, world!")
}
=======
func main() {
    // Starting the main function
    fmt.Println("Hello, world!") // Printing Hello, world! to the console
}
>>>>>>> REPLACE

/Users/user/projects/myproject/config.go
<<<<<<< SEARCH
// package main
import "fmt"

=======
// package main
// Importing the fmt package
import "fmt"

>>>>>>> REPLACE
]] .. "]]>" .. [[</content>
    </inputs>
  </parameters>
</tool>
```

This example demonstrates how to add comments to the main.go and config.go files. Note how each SEARCH/REPLACE block starts with the file path, and how the SEARCH section exactly matches the existing code. Also, notice that the entire content is wrapped in a CDATA section to prevent XML parsing issues with special characters in the code.]]
end

local function remove_line_numbers(lines)
  local function remove_line_number(line)
    return line:gsub("^%s*(%d+)%s*", function(num)
      if #num <= 6 then
        return ""
      else
        return num
      end
    end)
  end

  -- Split the string into lines, process each line, then recombine
  for i, line in ipairs(lines) do
    lines[i] = remove_line_number(line)
  end
  return lines
end

local function find_blocks(content)
  local blocks = {}
  local current_block = {}
  local current_file = nil
  local in_block = false
  local lines = vim.split(content, "\n", { plain = true })

  for _, line in ipairs(lines) do
    if line:match("^<<<<<<<%s*SEARCH%s*$") then
      in_block = true
      current_block = { search = {}, replace = {} }
    elseif line:match("^=======%s*$") and in_block then
      current_block.current = "replace"
    elseif line:match("^>>>>>>>%s*REPLACE%s*$") and in_block then
      in_block = false
      if current_file and #current_block.search > 0 then
        log:trace("Found block for file: %s", current_file)
        log:trace("Search: %s", vim.inspect(current_block.search))
        log:trace("Replace: %s", vim.inspect(current_block.replace))
        table.insert(blocks, { file = current_file, block = current_block })
      end
    elseif in_block then
      table.insert(current_block[current_block.current or "search"], line)
    elseif not in_block and line ~= "" then
      current_file = line
    end
  end
  return blocks
end

local function apply_edit(bufnr, search_lines, replace_lines)
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  local search = table.concat(search_lines, "\n")
  local replace = table.concat(replace_lines, "\n")

  log:debug("Content length: %d", #content)
  log:debug("Search length: %d", #search)
  log:debug("Replace length: %d", #replace)
  -- stylua: ignore
  log:trace("Content (hex):\n%s", content:gsub(".", function(c) return string.format("%02X ", string.byte(c)) end))
  -- stylua: ignore
  log:trace("Search (hex):\n%s", search:gsub(".", function(c) return string.format("%02X ", string.byte(c)) end))

  local function find_fuzzy(text, pattern)
    pattern = pattern:gsub("%s+", "%%s*")
    pattern = pattern:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") -- 转义特殊字符
    return text:match("()" .. pattern)
  end

  local start_pos = content:find(search, 1, true)
  if not start_pos then
    log:debug("Exact match failed, trying fuzzy match")
    start_pos = find_fuzzy(content, search)
    if not start_pos then
      log:error("Could not find the search block in the buffer, even with fuzzy matching")
      return false, "Could not find the search block in the buffer"
    end
  end

  local end_pos = start_pos + #search - 1
  local start_line = select(2, content:sub(1, start_pos):gsub("\n", "")) + 1
  local end_line = select(2, content:sub(1, end_pos):gsub("\n", "")) + 1

  log:debug("Match found at position %d-%d (lines %d-%d)", start_pos, end_pos, start_line, end_line)

  vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, vim.split(replace, "\n"))
  return true, string.format("Edit applied successfully at lines %d-%d", start_line, end_line)
end

local function create_rollback_point(bufnr)
  return {
    bufnr = bufnr,
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
    view = vim.fn.winsaveview(),
  }
end

local function rollback(rollback_point)
  if rollback_point then
    vim.api.nvim_buf_set_lines(rollback_point.bufnr, 0, -1, false, rollback_point.lines)
    vim.fn.winrestview(rollback_point.view)
    return true, "Changes rolled back successfully"
  end
  return false, "No rollback point available"
end

-- New function to handle the actual execution
local function perform_edits(params)
  local blocks = find_blocks(params.content)
  local results = {}
  local modified_files = {}
  local rollback_points = {}

  for _, item in ipairs(blocks) do
    local file_path = item.file
    local block = item.block

    local bufnr = vim.fn.bufnr(file_path)
    if bufnr == -1 then
      bufnr = vim.fn.bufadd(file_path)
      vim.fn.bufload(bufnr)
    end

    if vim.api.nvim_buf_is_valid(bufnr) then
      local rollback_point = create_rollback_point(bufnr)
      table.insert(rollback_points, rollback_point)

      local success, result = apply_edit(bufnr, block.search, block.replace)

      table.insert(results, {
        success = success,
        message = result,
        file = file_path,
        search = table.concat(block.search, "\n"),
        replace = table.concat(block.replace, "\n"),
      })

      if success then
        if not modified_files[file_path] then
          modified_files[file_path] = {}
        end
        table.insert(modified_files[file_path], {
          search = table.concat(block.search, "\n"),
          replace = table.concat(block.replace, "\n"),
        })
      end
    else
      table.insert(results, { success = false, message = "Invalid buffer for file: " .. file_path })
    end
  end

  return results, modified_files, rollback_points
end

-- Executes code modifications and handles the results.
--
---@param chat CodeCompanion.Chat The chat object containing buffer information.
---@param params table Parameters for the code modifications.
--
---@return CodeCompanion.ToolExecuteResult
function M.execute(chat, params)
  local bufnr = chat.bufnr

  -- Announce start
  vim.api.nvim_exec_autocmds("User", {
    pattern = "CodeCompanionAgent",
    data = { bufnr = bufnr, status = "started" },
  })

  -- Perform edits
  local results, modified_files, rollback_points = perform_edits(params)

  -- Process results
  local overall_success = vim.tbl_count(vim.tbl_filter(function(r)
    return r.success
  end, results)) == #results
  local messages = vim.tbl_map(function(r)
    return string.format("%s: %s", r.file, r.message)
  end, results)

  for file_path, _ in pairs(modified_files) do
    local file_bufnr = vim.fn.bufnr(file_path)
    modified_files[file_path].content = table.concat(vim.api.nvim_buf_get_lines(file_bufnr, 0, -1, false), "\n")
  end

  -- Handle rollback if necessary
  if
    not overall_success
    and vim.fn.confirm("Some changes failed. Do you want to rollback all changes?", "&Yes\n&No", 1) == 1
  then
    for i = #rollback_points, 1, -1 do
      rollback(rollback_points[i])
    end
    modified_files = {}
  end

  -- Prepare final result
  local result = {
    success = overall_success,
    message = table.concat(messages, "\n"),
    modified_files = modified_files,
    details = results,
  }

  -- Announce end
  vim.api.nvim_exec_autocmds("User", {
    pattern = "CodeCompanionAgent",
    data = {
      bufnr = bufnr,
      status = overall_success and "success" or "error",
      error = not overall_success and result.message or nil,
      output = overall_success and result.message or nil,
    },
  })

  return result
end

-- The prompt to share with the LLM if an error is encountered
M.output_error_prompt = function(error)
  return "The buffer editor encountered an error: " .. error .. "\n\nCan you fix this issue?"
end

M.output_prompt = function(output)
  if config.strategies.agent.tools.opts.auto_submit_success then
    return "The buffer editor completed successfully with the following output:\n\n"
      .. output
      .. "\nWhat do you want to do next?"
  else
    return "The buffer editor completed successfully with the following output:\n\n" .. output .. "\nNow I need you "
  end
end

return M
