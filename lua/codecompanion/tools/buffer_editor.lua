local BaseTool = require("codecompanion.tools.base_tool")
local ctcr = require("codecompanion.tools.chunk")
local log = require("codecompanion.utils.log")
local api = vim.api

local function create_rollback_point(bufnr)
  return {
    bufnr = bufnr,
    lines = api.nvim_buf_get_lines(bufnr, 0, -1, false),
    view = vim.fn.winsaveview(),
  }
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

---@class CodeCompanion.BufferEditorTool : CodeCompanion.CopilotTool
local BufferEditorTool = setmetatable({}, { __index = BaseTool })
BufferEditorTool.__index = BufferEditorTool

---@param copilot CodeCompanion.Copilot
function BufferEditorTool.new(copilot)
  local self = setmetatable(BaseTool.new(copilot), BufferEditorTool)
  self.name = "buffer_editor"
  return self
end

-- Executes the buffer editing tool with the provided arguments.
--
---@param args string A table containing the arguments necessary for execution.
---@param callback fun(response: CodeCompanion.CopilotToolChunkResp)
function BufferEditorTool:execute(args, callback)
  -- Implementation remains largely the same, but now works directly with 'args'
  local blocks = self:find_blocks(args)
  local results, _, _ = self:perform_edits(blocks)

  callback(ctcr.new_final(self.copilot.bufnr, self:format_results(results)))
end

---returns the result of the tool execution
---@param results table
---@private
function BufferEditorTool:format_results(results)
  local messages = vim.tbl_map(function(r)
    return string.format("%s: %s", r.file, r.message)
  end, results)

  return table.concat(messages, "\n")
end

---@private
function BufferEditorTool:find_blocks(content)
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

---@private
function BufferEditorTool:perform_edits(blocks)
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

function BufferEditorTool:description()
  return "Performs complex buffer editing operations across multiple files, including search, replace, and block manipulations."
end

function BufferEditorTool:input_format()
  return [[
Input should contain a series of *SEARCH/REPLACE* blocks, each block representing a file edit operation.:

file_path1
<<<<<<< SEARCH
[exact lines to search for]
=======
[lines to replace with]
>>>>>>> REPLACE

file_path2
<<<<<<< SEARCH
[another block to search for]
=======
[lines to replace with]
>>>>>>> REPLACE


*SEARCH/REPLACE block* Rules:

Every *SEARCH/REPLACE block* must use this format:
1. The file path alone on a line, verbatim. No bold asterisks, no quotes around it, no escaping of characters, etc. note user code file path.
2. The start of search block: <<<<<<< SEARCH even if there is no content needed to search for. 注意请忽视掉给你的代码中每行最前面的行号,行号只是给你参考位置的
3. A contiguous chunk of lines to search for in the existing source code.
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

Be extremely careful and precise when creating these blocks dot not forget code indentation same as the workspace code content. If the SEARCH section doesn't match exactly, the edit will fail.

ONLY EVER RETURN CODE IN A *SEARCH/REPLACE BLOCK*! USE TAB FOR INDENTATION.

CRITICAL INDENTATION RULES:
1. ALWAYS preserve the exact indentation of the original code in the SEARCH block.
2. In the REPLACE block, use the SAME TYPE of indentation (tabs or spaces) as in the SEARCH block.
3. Do NOT convert tabs to spaces or vice versa. Use whatever indentation type is present in the original code.
4. Pay close attention to the indentation in the workspace content provided to you. Mirror this indentation precisely in your SEARCH and REPLACE blocks.
5. If you're unsure about the indentation, examine the provided workspace content carefully to determine whether tabs or spaces are being used.

Remember: Incorrect indentation can cause the edit to fail or introduce bugs. Be extremely precise with indentation in both SEARCH and REPLACE blocks.
  ]]
end

function BufferEditorTool:example()
  return [[
When using the buffer_editor tool to add or modify file content:

1. For files not in the workspace yet:
   - First, ask the user whether to create a new file directly or to have the user add the file to the workspace, in order to prevent buffer_editor from directly modifying a file that exists but is not in the workspace. 
   - Use a SEARCH/REPLACE block with:
     - A new file path, including directory name if needed
     - An empty `SEARCH` section
     - The new file's contents in the `REPLACE` section

2. For files already in the workspace:
   - Use a SEARCH/REPLACE block with:
     - The existing file path
     - An empty `SEARCH` section if you want to append content to the end of the file
     - The content to be added in the `REPLACE` section

Important notes:
- If the specified file already exists and you use an empty `SEARCH` section, the content in the `REPLACE` section will be appended to the end of the existing file.
- To replace the entire content of an existing file, include the entire current file content in the `SEARCH` section and the new content in the `REPLACE` section.
- Always verify the current content of files in the workspace before making modifications to avoid unintended changes.
- If you're unsure about the current state of a file, use the command_runner tool to check its content before using the buffer_editor tool.

Example for appending to an existing file:
```
existing_file.txt
<<<<<<< SEARCH
=======
This content will be appended to the end of the existing file.
>>>>>>> REPLACE
```

Remember: The workspace contents are continuously updated, so always base your actions on the most recent information provided about the files in the workspace.

Some Example conversations:

### USER: Change get_factorial() to use math.factorial
### ASSISTANT: To make this change we need to modify `mathweb/flask/app.py` to:

1. Import the math package.
2. Remove the existing factorial() function.
3. Update get_factorial() to call math.factorial instead.

(buffer_editor)
```
main.py
<<<<<<< SEARCH
def hello():
    print("Hello, World!")
=======
def greet(name):
    print(f"Hello, {name}!")
>>>>>>> REPLACE

mathweb/flask/app.py
<<<<<<< SEARCH
from flask import Flask
=======
import math
from flask import Flask
>>>>>>> REPLACE

mathweb/flask/app.py
<<<<<<< SEARCH
def factorial(n):
    "compute factorial"

    if n == 0:
        return 1
    else:
        return n * factorial(n-1)

=======
>>>>>>> REPLACE

mathweb/flask/app.py
<<<<<<< SEARCH
    return str(factorial(n))
=======
    return str(math.factorial(n))
>>>>>>> REPLACE
```
output:==
```


### USER: Refactor hello() into its own file.
### ASSISTANT: To make this change we need to modify `main.py` and make a new file `hello.py`:

1. Make a new hello.py file with hello() in it.
2. Remove hello() from main.py and replace it with an import.


(buffer_editor)
```
hello.py
<<<<<<< SEARCH
=======
def hello():
    "print a greeting"

    print("hello")
>>>>>>> REPLACE

main.py
<<<<<<< SEARCH
def hello():
    "print a greeting"

    print("hello")
=======
from hello import hello
>>>>>>> REPLACE
```
output:==
```

]]
end

function BufferEditorTool:output_format()
  return "A list of messages indicating the success or failure of the buffer editing operations."
end

return BufferEditorTool
