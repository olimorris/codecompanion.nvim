local pandoc = _G.pandoc
local stringify = pandoc.utils.stringify

local M = {}

-- Sections to completely skip (won't appear in TOC or vimdoc)
local excluded_sections = {
  "^Upgrading",
  "^v%d+%.%d+", -- Version number headers like "v18.6.0 to v19.0.0"
  "default_memory", -- Specific upgrade-related headers
  "autoload", -- Related to the default_memory change
}

-- Aggressive header cleanup patterns
local header_substitution = {
  -- Remove boilerplate words
  { " has been renamed to ", " → " },
  { " has been ", " " },
  { " %(ACP%)", "" },
  { " %(MCP%)", "" },
  { " Support$", "" },
  { " %(%#%d+%)$", "" }, -- Remove GitHub issue refs like (#2509)

  -- Simplify common phrases
  { "^Welcome to CodeCompanion%.nvim", "Welcome" },
  { "^Configuring an ", "Setup: " },
  { "^Configuring the ", "" },
  { "^Configuring ", "" },
  { "^Using the ", "" },
  { "^Using ", "" },
  { "^Other Configuration Options", "Other Options" },
  { "^Extending CodeCompanion with ", "Extending with " },
  { "^Creating Your Own ", "Custom " },
  { "^The CodeCompanion ", "" },
  { " in CodeCompanion$", "" },
  { " for CodeCompanion$", "" },
  { " General$", "" },
  { "CodeCompanion$", "" },
  { "Plugin%s*", "" },

  -- Shorten specific sections
  { "^Agent Client Protocol", "ACP" },
  { "^Model Context Protocol", "MCP" },
}

function M.Header(el)
  local text = stringify(el.content)

  -- Check if this header should be excluded entirely
  for _, pattern in ipairs(excluded_sections) do
    if text:match(pattern) then
      -- Return empty list to remove the element from the AST
      return {}
    end
  end

  -- Apply all substitutions in order
  for _, sub in ipairs(header_substitution) do
    local pat, repl = sub[1], sub[2]
    text = text:gsub(pat, repl)
  end

  -- Aggressive whitespace cleanup
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  text = text:gsub("%s+", " ")

  -- Remove standalone single letters (artifacts from aggressive substitution)
  if text:match("^%a%s*$") then
    text = "Options"
  end

  -- Truncate if too long
  local max_length = 80
  if #text > max_length then
    text = text:sub(1, max_length - 3) .. "..."
  end

  el.content = text
  return el
end

function M.Link(el)
  if not el.target:find("^http") then
    el.content = el.target:gsub("^/", ""):gsub("/", "-"):gsub("%.md", ""):gsub("#", "-")
    el.target = "#"
  end
  return el
end

function M.Emph(el)
  local text = stringify(el.content)
  if text:find("^[@,]") and #el.content > 1 then
    el.content:insert(1, pandoc.Str("_"))
    el.content:insert(pandoc.Str("_"))
    return el.content
  end
  return pandoc.Code(text)
end

function M.Cite(el)
  return pandoc.Str(stringify(el.content))
end

function M.Str(el)
  if el.text:find(":[%a_]+:") then
    el.text = ""
  end
  return el
end

function M.Inlines(inlines)
  for i = #inlines - 1, 1, -1 do
    local e1, e2 = inlines[i], inlines[i + 1]
    if e1.t == "Str" and e2.t == "Str" then
      if e2.text == "_" and e1.text:sub(1, 1) == "@" then
        e1.text = e1.text .. "_"
        inlines:remove(i + 1)
      else
        local cite, sfx = e2.text:match("^(@.+)_$")
        if cite and e1.text == "_" then
          inlines[i] = pandoc.Code(cite)
          inlines:remove(i + 1)
        end
      end
    end
  end
  return inlines
end

return { M }
