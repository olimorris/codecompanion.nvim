local log = require("codecompanion.utils.log")
local config = require("codecompanion").config
local xml2lua = require("codecompanion.utils.xml.xml2lua")
local api = vim.api
local util = require("codecompanion.utils.agent")

---@type CodeCompanion.Agent
local M = {}

M.schema = {
  parameters = {
    inputs = {
      content = "<![CDATA[string containing file paths and SEARCH/REPLACE blocks]]>",
    },
  },
  name = "buffer_editor",
}

M.prompts = {
  {
    role = "system",
    content = function(schema)
      return [[To aid you further, I'm giving you access to a Buffer Editor which can modify existing code within a buffer or create a new buffer to write code. 

To use the block editor, you need to return an XML markdown code block (with backticks) which follows the below schema:
```xml
]] .. xml2lua.toXml(schema, "agent") .. [[

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

*SEARCH/REPLACE block* Rules:

Every *SEARCH/REPLACE block* must use this format:
1. The file path alone on a line, verbatim. No bold asterisks, no quotes around it, no escaping of characters, etc.
2. The start of search block: <<<<<<< SEARCH
3. A contiguous chunk of lines to search for in the existing source code
4. The dividing line: =======
5. The lines to replace into the source code
6. The end of the replace block: >>>>>>> REPLACE

Every *SEARCH* section must *EXACTLY MATCH* the existing source code, character for character, including all comments, docstrings, etc.

*SEARCH/REPLACE* blocks will replace *all* matching occurrences.
Include enough lines to make the SEARCH blocks uniquely match the lines to change.

Keep *SEARCH/REPLACE* blocks concise.
Break large *SEARCH/REPLACE* blocks into a series of smaller blocks that each change a small portion of the file.
Include just the changing lines, and a few surrounding lines if needed for uniqueness.
Do not include long runs of unchanging lines in *SEARCH/REPLACE* blocks.

To move code within a file, use 2 *SEARCH/REPLACE* blocks: 1 to delete it from its current location, 1 to insert it in the new location.

If you want to put code in a new file, use a *SEARCH/REPLACE block* with:
- A new file path, including dir name if needed
- An empty `SEARCH` section
- The new file's contents in the `REPLACE` section

Be extremely careful and precise when creating these blocks. If the SEARCH section doesn't match exactly, the edit will fail.

ONLY EVER RETURN CODE IN A *SEARCH/REPLACE BLOCK*!

Here's an example of how to use the buffer_editor agent:

```xml
<agent>
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
package main

import "fmt"

=======
package main

// Importing the fmt package
import "fmt"

>>>>>>> REPLACE

/Users/user/projects/myproject/config_test.go
<<<<<<< SEARCH
=======
package main

>>>>>>> REPLACE
]] .. "]]>" .. [[</content>
    </inputs>
  </parameters>
</agent>
```

This example demonstrates how to add comments to the main.go and config.go files and creat a new file config_test.go. Note how each SEARCH/REPLACE block starts with the file path, and how the SEARCH section exactly matches the existing code. Also, notice that the entire content is wrapped in a CDATA section to prevent XML parsing issues with special characters in the code.]]
    end,
  },
  {
    role = "user",
    ---@param context CodeCompanion.Context
    content = function(context)
      return [[Here are the code files you need to focus, these codes are always in the most up-to-date state

@buffers

]]
    end,
  },
}

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

  -- 分割字符串为行，处理每一行，然后重新组合
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
  local block_type = nil
  local lines = vim.split(content, "\n", { plain = true })

  for _, line in ipairs(lines) do
    if line:match("^<<<<<<<%s*SEARCH%s*$") then
      in_block = true
      block_type = "search"
      current_block = { search = {}, replace = {}, is_new_file = false }
    elseif line:match("^<<<<<<<%s*REPLACE%s*$") then
      in_block = true
      block_type = "replace"
      current_block = { search = {}, replace = {}, is_new_file = true }
    elseif line:match("^=======%s*$") and in_block then
      block_type = "replace"
    elseif line:match("^>>>>>>>%s*REPLACE%s*$") and in_block then
      in_block = false
      if current_file then
        log:trace("Found block for file: %s", current_file)
        log:trace("Search: %s", vim.inspect(current_block.search))
        log:trace("Replace: %s", vim.inspect(current_block.replace))
        log:trace("Is new file: %s", tostring(current_block.is_new_file))
        table.insert(blocks, { file = current_file, block = current_block })
      end
      current_block = {}
      block_type = nil
    elseif in_block then
      table.insert(current_block[block_type], line)
    elseif not in_block and line ~= "" then
      current_file = line
    end
  end

  return blocks
end

local function apply_edit(bufnr, search_lines, replace_lines, is_new_file)
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")

  if is_new_file then
    -- if it is a new file, directly set the entire content of the buffer
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, replace_lines)
    return true, "New file content set"
  elseif #search_lines == 0 then
    -- if the search line is empty, but it is not a new file, we add new content at the end of the file
    local new_content = content .. "\n" .. table.concat(replace_lines, "\n")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(new_content, "\n"))
    return true, "New content added to existing file"
  else
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

    api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, vim.split(replace, "\n"))
    return true, string.format("Edit applied successfully at lines %d-%d", start_line, end_line)
  end
end

local function create_rollback_point(bufnr)
  return {
    bufnr = bufnr,
    lines = api.nvim_buf_get_lines(bufnr, 0, -1, false),
    view = vim.fn.winsaveview(),
  }
end

local function rollback(rollback_point)
  if rollback_point then
    api.nvim_buf_set_lines(rollback_point.bufnr, 0, -1, false, rollback_point.lines)
    vim.fn.winrestview(rollback_point.view)
    return true, "Changes rolled back successfully"
  end
  return false, "No rollback point available"
end

--- Finds an appropriate window to open a file or creates a new left split window if no suitable window is found.
---@param file_path string: The path of the file to be opened.
---@return integer: Window ID of the found or newly created window.
local function find_or_create_appropriate_window(file_path)
  local chat_bufnr = api.nvim_get_current_buf()
  local target_filetype = vim.fn.fnamemodify(file_path, ":e")

  -- find the non-chat buffer window on the left
  for _, win in ipairs(api.nvim_list_wins()) do
    local buf = api.nvim_win_get_buf(win)
    if buf ~= chat_bufnr and api.nvim_win_get_config(win).relative == "" then
      local win_file_type = vim.bo[buf].filetype
      if win_file_type == target_filetype or win_file_type == "" then
        return win
      end
    end
  end

  -- if no suitable window is found, create a new left split
  vim.cmd("leftabove vnew")
  return api.nvim_get_current_win()
end

-- Edits the specified blocks in the content of the buffers.
---@param params table: A table containing the fields needed for the edits.
---@return table: A table containing the results of each edit operation including success status and messages.
---@return table: A table that maps modified file paths to their respective edits.
---@return table: A table containing rollback points for the buffers that were modified.
local function perform_edits(params)
  local blocks = find_blocks(params.content)
  local results = {}
  local modified_files = {}
  local rollback_points = {}
  local new_buffers = {}
  local chat_win = api.nvim_get_current_win()

  for _, item in ipairs(blocks) do
    local file_path = item.file
    local block = item.block
    local bufnr = vim.fn.bufnr(file_path)
    local is_new_buffer = false

    log:trace("Buffer number for file: %s is %d", file_path, bufnr)

    -- if bufnr is -1, the buffer does not exist, so create it
    if bufnr == -1 then
      bufnr = vim.fn.bufadd(file_path)
      vim.fn.bufload(bufnr)
      is_new_buffer = true
      table.insert(new_buffers, bufnr)
      log:trace("Created new buffer for file: %s with number %d", file_path, bufnr)
    end

    if api.nvim_buf_is_valid(bufnr) then
      local rollback_point = create_rollback_point(bufnr)
      table.insert(rollback_points, rollback_point)

      local success, result = apply_edit(bufnr, block.search, block.replace, block.is_new_file)

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

        -- Save the buffer to disk if auto_submit_success is enabled
        if config.strategies.agent.agents.opts.auto_submit_success then
          local save_success, save_error = pcall(function()
            vim.api.nvim_buf_call(bufnr, function()
              vim.cmd("silent! write")
            end)
          end)

          if not save_success then
            log:error("Failed to save file: " .. file_path .. ". Error: " .. save_error)
            table.insert(results, {
              success = false,
              message = "Failed to save file: " .. file_path .. ". Error: " .. save_error,
              file = file_path,
            })
          else
            log:info("Successfully saved file: " .. file_path)
            table.insert(results, {
              success = true,
              message = "Successfully saved file: " .. file_path,
              file = file_path,
            })
          end
        end
      end

      -- if the buffer is newly created, set some options
      if is_new_buffer then
        local target_win = find_or_create_appropriate_window(file_path)
        api.nvim_win_set_buf(target_win, bufnr)
        api.nvim_set_option_value("buflisted", true, { buf = bufnr })
        api.nvim_set_option_value("modifiable", true, { buf = bufnr })
        api.nvim_set_option_value("modified", false, { buf = bufnr })
      end
    else
      table.insert(results, { success = false, message = "Invalid buffer for file: " .. file_path })
    end
  end

  -- return focus to the chat buffer
  api.nvim_set_current_win(chat_win)

  return results, modified_files, rollback_points
end

function M.execute(chat, params, last_execute)
  local bufnr = chat.bufnr

  -- Announce start
  util.announce_start(bufnr)

  -- Perform edits
  local results, modified_files, rollback_points = perform_edits(params)
  log:trace("result: %s", results)

  -- Process results
  local overall_success = vim.tbl_count(vim.tbl_filter(function(r)
    return r.success
  end, results)) == #results
  local messages = vim.tbl_map(function(r)
    return string.format("%s: %s", r.file, r.message)
  end, results)

  for file_path, _ in pairs(modified_files) do
    local file_bufnr = vim.fn.bufnr(file_path)
    modified_files[file_path].content = table.concat(api.nvim_buf_get_lines(file_bufnr, 0, -1, false), "\n")
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

  util.announce_end(
    bufnr,
    overall_success and "success" or "error",
    not overall_success and messages or {},
    overall_success and messages or {},
    last_execute
  )
end

-- The prompt to share with the LLM if an error is encountered
M.output_error_prompt = function(error)
  return "After the buffer_editor completed, there was an error:" .. "\n```\n" .. table.concat(error, "\n") .. "\n```"
end

M.output_prompt = function(output)
  return "After the buffer_editor completed the output was:" .. "\n```\n" .. table.concat(output, "\n") .. "\n```\n"
end

return M
