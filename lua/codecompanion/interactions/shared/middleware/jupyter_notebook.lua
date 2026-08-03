--[[
  Formats Jupyter Notebooks for LLM consumption. Cell outputs with image or
  HTML MIME types are stripped.
]]
local M = {}

local fmt = string.format

---Format a Jupyter Notebook's raw JSON
---@param raw string The raw notebook JSON
---@return string|nil
function M.format(raw)
  local ok, notebook = pcall(vim.json.decode, raw)
  if not ok or not notebook or not notebook.cells then
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

  local parts = { "Jupyter Notebook (image and HTML outputs have been removed):" }
  for _, cell in ipairs(notebook.cells) do
    local cell_parts = {}
    table.insert(cell_parts, fmt("## %s", cell.cell_type))

    local source
    if type(cell.source) == "table" then
      source = table.concat(cell.source, "")
    else
      source = cell.source or ""
    end

    if cell.cell_type == "code" then
      table.insert(cell_parts, fmt("````%s\n%s\n````", language, source))
    elseif cell.cell_type == "markdown" then
      table.insert(cell_parts, fmt("````markdown\n%s\n````", source))
    else
      table.insert(cell_parts, source)
    end

    if cell.outputs and #cell.outputs > 0 then
      local output_parts = {}
      for _, output in ipairs(cell.outputs) do
        if output.output_type == "stream" then
          table.insert(output_parts, table.concat(output.text or {}, ""))
        elseif output.output_type == "error" then
          table.insert(output_parts, fmt("%s: %s", output.ename or "Error", output.evalue or ""))
        elseif output.data then
          -- Keep text/plain only, removing everything especially images and HTML
          if output.data["text/plain"] then
            local text = output.data["text/plain"]
            if type(text) == "table" then
              text = table.concat(text, "")
            end
            table.insert(output_parts, text)
          end
        end
      end

      if #output_parts > 0 then
        table.insert(cell_parts, "### Output")
        table.insert(cell_parts, fmt("````\n%s\n````", table.concat(output_parts, "\n")))
      end
    end

    table.insert(parts, table.concat(cell_parts, "\n"))
  end

  return table.concat(parts, "\n\n")
end

return M
