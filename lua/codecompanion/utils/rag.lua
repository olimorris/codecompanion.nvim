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

--- URL-encode a string
--- @param url string
--- @return string
function M.encode(url)
  if type(url) ~= "number" then
    url = url:gsub("\r?\n", "\r\n")
    url = url:gsub("([^%w%-%.%_%~%'%\"%? ])", function(c)
      return string.format("%%%02X", c:byte())
    end)
    url = url:gsub(" ", "+")
    return url
  else
    return tostring(url)
  end
end

return M
