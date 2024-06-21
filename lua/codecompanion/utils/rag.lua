local M = {}

function M.strip_markdown(str)
  -- Remove code blocks
  str = str:gsub("```.-```", "")

  -- Remove inline code
  str = str:gsub("`.-`", "")

  -- Remove headings
  str = str:gsub("#+%s*(.-)\n", "%1\n")

  -- Remove bold and italic emphasis
  str = str:gsub("%*%*(.-)%*%*", "%1")
  str = str:gsub("__(.-)__", "%1")
  str = str:gsub("%*(.-)%*", "%1")
  str = str:gsub("_(.-)_", "%1")

  -- Remove links
  str = str:gsub("%[.-%]%((.-)%)", "%1")

  -- Remove images
  str = str:gsub("!%[.-%]%((.-)%)", "")

  -- Remove blockquotes
  str = str:gsub("> (.-)\n", "%1\n")

  -- Remove horizontal rules
  str = str:gsub("%-%-%-\n", "")
  str = str:gsub("%*%*%*\n", "")

  -- Remove lists
  str = str:gsub("%* (.-)\n", "%1\n")
  str = str:gsub("%d+%. (.-)\n", "%1\n")

  -- Remove extra newlines
  str = str:gsub("\n\n+", "\n")

  -- Trim leading and trailing whitespace
  str = str:match("^%s*(.-)%s*$")

  return str
end

local char_to_hex = function(c)
  return string.format("%%%02X", string.byte(c))
end

function M.encode(url)
  if url == nil then
    return
  end
  url = url:gsub("\n", "\r\n")
  url = url:gsub("([^%w _%%%-%.~])", char_to_hex)
  url = url:gsub(" ", "+")
  return url
end

local hex_to_char = function(x)
  return string.char(tonumber(x, 16))
end

function M.decode(url)
  if url == nil then
    return
  end
  url = url:gsub("+", " ")
  url = url:gsub("%%(%x%x)", hex_to_char)
  return url
end

return M
