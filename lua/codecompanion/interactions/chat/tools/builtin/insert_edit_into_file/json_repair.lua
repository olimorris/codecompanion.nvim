local fmt = string.format

local M = {}

---Fix edits field if it's a string instead of a table (handles LLM JSON formatting issues)
---@param args table
---@return table|nil, string|nil
function M.fix_edits(args)
  -- If there's no issues, return early
  if type(args.edits) == "table" then
    return args, nil
  end

  if type(args.edits) ~= "string" then
    return nil, "edits must be an array or parseable string"
  end

  local success, parsed_edits = pcall(vim.json.decode, args.edits)
  if success and type(parsed_edits) == "table" then
    args.edits = parsed_edits
    return args, nil
  end

  -- Try minimal fixes for common LLM JSON issues
  local fixed_json = args.edits

  -- Convert Python dict syntax to JSON object syntax
  fixed_json = fixed_json:gsub("{'oldText':", '{"oldText":')
  fixed_json = fixed_json:gsub("'newText':", '"newText":')
  fixed_json = fixed_json:gsub("'replaceAll':", '"replaceAll":')

  -- Convert single quotes to double quotes for values
  fixed_json = fixed_json:gsub(": '([^']*)'", ': "%1"')
  fixed_json = fixed_json:gsub(", '([^']*)'", ', "%1"')

  -- Capture delimiters ([,}%]]) to preserve array/object structure
  fixed_json = fixed_json:gsub(": False([,}%]])", ": false%1")
  fixed_json = fixed_json:gsub(": True([,}%]])", ": true%1")

  success, parsed_edits = pcall(vim.json.decode, fixed_json)
  if success and type(parsed_edits) == "table" then
    args.edits = parsed_edits
    return args, nil
  end

  -- FALLBACK: Try enhanced Python-like parser
  local tool_utils = require("codecompanion.interactions.chat.tools.builtin.insert_edit_into_file.utils")
  local python_converted = tool_utils.parse_python_json(args.edits)
  if python_converted then
    success, parsed_edits = pcall(vim.json.decode, python_converted)
    if success and type(parsed_edits) == "table" then
      args.edits = parsed_edits
      return args, nil
    end
  end

  return nil, fmt("Could not parse edits as JSON. Original: %s", args.edits:sub(1, 200))
end

return M
