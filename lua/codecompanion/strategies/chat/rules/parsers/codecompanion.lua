--[[
===============================================================================
    File:       codecompanion/strategies/chat/rules/parsers/codecompanion.lua
    Author:     Oli Morris
-------------------------------------------------------------------------------
    Description:
      Parses a markdown file and extracts anything under a "## System Prompt"
      header as the system prompt content. Everything else is a user prompt.
===============================================================================
--]]

---@param file CodeCompanion.Chat.Rules.ProcessedFile
---@return CodeCompanion.Chat.Rules.Parser
return function(file)
  local system_prompt = ""
  local user_content = {}
  local content = file.content or ""
  local included_files = {}

  if content == "" then
    return { system_prompt = system_prompt, content = "" }
  end

  -- Parse the markdown content
  local ok, parser = pcall(vim.treesitter.get_string_parser, content, "markdown")
  if not ok then
    return { system_prompt = system_prompt, content = content }
  end

  local tree = parser:parse()[1]
  if not tree then
    return { system_prompt = system_prompt, content = content }
  end
  local root = tree:root()

  -- Query for sections with h2 headings
  local query_str = [[
    (section
      (atx_heading
        (atx_h2_marker)
        heading_content: (_) @heading
      )
      (_)* @section_content
    )
  ]]

  local query = vim.treesitter.query.parse("markdown", query_str)
  local get_text = vim.treesitter.get_node_text

  -- Track seen files
  local seen = {}

  -- Iterate over all captures
  for id, node in query:iter_captures(root, content, 0, -1) do
    local capture_name = query.captures[id]

    if capture_name == "heading" then
      local heading_text = get_text(node, content):lower():gsub("^%s*(.-)%s*$", "%1")

      -- Find the section node (parent of the heading)
      local section_node = node:parent():parent()

      if heading_text == "system prompt" and section_node then
        -- Extract all content after the heading in this section (exclude heading itself)
        local section_text_parts = {}

        -- Get all children of the section except the heading
        for child in section_node:iter_children() do
          if child:type() ~= "atx_heading" then
            local child_text = get_text(child, content)
            -- Filter out lines starting with "@" from system prompt
            local filtered_lines = {}
            for line in child_text:gmatch("[^\n]+") do
              if not line:match("^%s*@%S+") then
                table.insert(filtered_lines, line)
              end
            end
            if #filtered_lines > 0 then
              table.insert(section_text_parts, table.concat(filtered_lines, "\n"))
            end
          end
        end

        system_prompt = table.concat(section_text_parts, "\n"):gsub("^%s*(.-)%s*$", "%1")
      elseif section_node then
        -- This is user content - extract all content from this section (include heading)
        -- Get the full section text and process it
        local section_text = get_text(section_node, content)
        local filtered_lines = {}

        local last_was_empty = false

        for line in (section_text .. "\n"):gmatch("([^\n]*)\n") do
          local path = line:match("^%s*@(%S+)")
          if path then
            if not seen[path] then
              seen[path] = true
              table.insert(included_files, path)
            end
            -- Treat @ lines as empty for consecutive blank line detection
            last_was_empty = true
          else
            local is_empty = not line:match("%S")
            -- Skip consecutive empty lines
            if not (is_empty and last_was_empty) then
              table.insert(filtered_lines, line)
            end
            last_was_empty = is_empty
          end
        end

        if #filtered_lines > 0 then
          -- Trim trailing empty lines
          while #filtered_lines > 0 and not filtered_lines[#filtered_lines]:match("%S") do
            table.remove(filtered_lines)
          end
          -- Trim leading empty lines
          while #filtered_lines > 0 and not filtered_lines[1]:match("%S") do
            table.remove(filtered_lines, 1)
          end
          if #filtered_lines > 0 then
            table.insert(user_content, table.concat(filtered_lines, "\n"))
          end
        end
      end
    end
  end

  -- Join user content and trim
  local final_content = table.concat(user_content, "\n"):gsub("^%s*(.-)%s*$", "%1")

  return {
    system_prompt = system_prompt,
    content = final_content,
    meta = (#included_files > 0) and { included_files = included_files } or nil,
  }
end
