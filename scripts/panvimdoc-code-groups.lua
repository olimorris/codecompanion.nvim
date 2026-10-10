-- Pandoc can't parse a VitePress fence such as ```lua [Old], so code groups vanish from the vimdoc

local pandoc = _G.pandoc

local M = {}

local function flatten_code_groups(text)
  local lines = {}
  local fence

  for line in (text .. "\n"):gmatch("(.-)\n") do
    local ticks, lang, label = line:match("^(```+)(%S+)%s+%[(.-)%]%s*$")
    if not fence and ticks then
      table.insert(lines, "**" .. label .. "**")
      table.insert(lines, "")
      table.insert(lines, ticks .. lang)
      fence = ticks
    elseif not fence and (line:match("^:::%s*code%-group%s*$") or line:match("^:::%s*$")) then
      table.insert(lines, "")
    else
      local opening = line:match("^(```+)")
      if opening and not fence then
        fence = opening
      elseif opening and opening == fence and line:match("^```+%s*$") then
        fence = nil
      end
      table.insert(lines, line)
    end
  end

  return table.concat(lines, "\n")
end

function M.CodeBlock(block)
  if not block.classes:includes("include") then
    return
  end

  for path in block.text:gmatch("[^\n]+") do
    if path:sub(1, 2) ~= "//" then
      local file = io.open(path, "r")
      if file then
        local contents = file:read("*a")
        file:close()
        -- include-files fetches through the mediabag, which is checked before the file on disk
        pandoc.mediabag.insert(path, "text/markdown", flatten_code_groups(contents))
      end
    end
  end
end

return { M }
