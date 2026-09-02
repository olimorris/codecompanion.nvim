--[[
  Formats Jupyter Notebooks for LLM consumption. Rich cell outputs (images,
  HTML etc.) are replaced with in-place placeholders.
]]
local M = {}

local markdown = require("codecompanion.utils.markdown")

local fmt = string.format

---Join notebook text, which may be a string or a list of strings, into one string
---@param text string|table|nil
---@return string
local function to_text(text)
  if type(text) == "table" then
    return table.concat(text, "")
  end
  if type(text) == "string" then
    return text
  end
  return ""
end

---Remove the ANSI color codes that Jupyter embeds in tracebacks
---@param text string
---@return string
local function strip_ansi(text)
  return (text:gsub("\27%[[%d;]*m", ""))
end

---Format a Jupyter Notebook's raw JSON
---@param raw string The raw notebook JSON
---@return string|nil
function M.format(raw)
  local ok, notebook = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
  if not ok or type(notebook) ~= "table" or not notebook.cells then
    return nil
  end

  local language = "python"
  if notebook.metadata then
    local kernelspec = notebook.metadata.kernelspec
    local language_info = notebook.metadata.language_info
    if kernelspec and kernelspec.language then
      language = kernelspec.language
    elseif language_info and language_info.name then
      language = language_info.name
    end
  end

  local parts = { "\n# Jupyter Notebook" }
  for position, cell in ipairs(notebook.cells) do
    local cell_parts = {}

    local heading = fmt("## Cell %d (%s)", position, cell.cell_type)
    if cell.cell_type == "code" then
      heading = fmt("%s In [%s]", heading, cell.execution_count or " ")
    end
    table.insert(cell_parts, heading)

    local source = to_text(cell.source)
    if cell.cell_type == "code" then
      table.insert(cell_parts, markdown.code_block(source, { info = language }))
    elseif cell.cell_type == "markdown" then
      table.insert(cell_parts, markdown.code_block(source, { info = "markdown" }))
    else
      table.insert(cell_parts, source)
    end

    if cell.outputs and #cell.outputs > 0 then
      local output_parts = {}
      for _, output in ipairs(cell.outputs) do
        if output.output_type == "stream" then
          local text = to_text(output.text)
          if output.name == "stderr" then
            text = "[stderr]\n" .. text
          end
          table.insert(output_parts, text)
        elseif output.output_type == "error" then
          if output.traceback and #output.traceback > 0 then
            table.insert(output_parts, strip_ansi(table.concat(output.traceback, "\n")))
          else
            table.insert(output_parts, fmt("%s: %s", output.ename or "Error", output.evalue or ""))
          end
        elseif output.data then
          if output.data["text/plain"] then
            table.insert(output_parts, to_text(output.data["text/plain"]))
          end
          local removed = {}
          for mime_type in pairs(output.data) do
            if mime_type ~= "text/plain" then
              table.insert(removed, mime_type)
            end
          end
          table.sort(removed)
          for _, mime_type in ipairs(removed) do
            table.insert(output_parts, fmt("[%s output removed]", mime_type))
          end
        end
      end

      if #output_parts > 0 then
        table.insert(cell_parts, "### Output")
        table.insert(cell_parts, markdown.code_block(table.concat(output_parts, "\n")))
      end
    end

    table.insert(parts, table.concat(cell_parts, "\n"))
  end

  return table.concat(parts, "\n\n")
end

return M
