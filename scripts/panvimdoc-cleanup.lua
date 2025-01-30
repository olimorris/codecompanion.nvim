local pandoc = _G.pandoc
local stringify = pandoc.utils.stringify

local M = {}

-- headers to shorten, so the toc stays pretty
local header_substitution = {
  { "^Welcome to CodeCompanion.nvim", "Welcome" },
  { "^Configuring an", "With an" },
  { "^Configuring the%s*", "" },
  { "^Configuring%s*", "" },
  { "CodeCompanion$", "General" },
  { "Plugin%s*", "" },
  { "^Using the%s*", "" },
  { "^Using%s*", "" },
  { "^Other Configuration Options", "Other Options" },
}

function M.Header(el)
  local text = stringify(el.content)
  for _, sub in ipairs(header_substitution) do
    local pat, repl = sub[1], sub[2]
    text = text:gsub(pat, repl)
  end
  el.content = text

  return el
end

function M.Link(el)
  if not el.target:find('^http') then
    -- start with / is root
    -- otherwise, it's relative. can't easily track
    -- make sure that tags are now #s here
    el.content = el.target:gsub("^/", ""):gsub("/", "-"):gsub('%.md', ''):gsub('#', '-')
    el.target = '#' -- ensures it makes a tag
  end
  return el
end

-- convert _neovim_ -> `Neovim`
function M.Emph(el)
  local text = stringify(el.content)

  -- special handling for citations
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

-- _@cmd_ -> {'_', '@cmd_'} or {'_', '@cmd', '_'}, so find and replace those with code
function M.Inlines(inlines)
  -- iterates backwards over each line
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
