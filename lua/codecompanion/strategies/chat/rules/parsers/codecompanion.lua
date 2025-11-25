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

  local ok, parser = pcall(vim.treesitter.get_string_parser, content, "markdown")
  if not ok then
    return { system_prompt = system_prompt, content = content }
  end

  local tree = parser:parse()[1]
  if not tree then
    return { system_prompt = system_prompt, content = content }
  end
  local root = tree:root()

  local query = vim.treesitter.query.get("markdown", "chat")
  local get_text = vim.treesitter.get_node_text

  -- Track seen files and processed sections
  local seen = {}
  local processed_sections = {}

  for id, node in query:iter_captures(root, content, 0, -1) do
    local capture_name = query.captures[id]

    if capture_name == "role" then
      local heading_text = get_text(node, content):lower()

      local section_node = node:parent():parent()
      if section_node and processed_sections[section_node:id()] then
        goto continue
      end

      if section_node then
        processed_sections[section_node:id()] = true
      end

      if heading_text == "system prompt" and section_node then
        -- Extract all content after the heading, except for the heading
        local section_text_parts = {}

        for child in section_node:iter_children() do
          if child:type() ~= "atx_heading" then
            local child_text = get_text(child, content)
            -- Filter out lines that include files with @
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

        system_prompt = table.concat(section_text_parts, "\n")
      elseif section_node then
        local section_text = get_text(section_node, content)
        local result = {}

        for _, line in ipairs(vim.split(section_text, "\n", { plain = true })) do
          local path = line:match("^%s*@(%S+)")

          if path and not seen[path] then
            seen[path] = true
            table.insert(included_files, path)
          elseif not path then
            table.insert(result, line)
          end
        end

        local trimmed = vim.trim(table.concat(result, "\n"))
        if trimmed ~= "" then
          table.insert(user_content, trimmed)
        end
      end
    end

    ::continue::
  end

  local final_content = table.concat(user_content, "\n")

  return {
    content = final_content,
    meta = (#included_files > 0) and { included_files = included_files } or nil,
    system_prompt = system_prompt,
  }
end
