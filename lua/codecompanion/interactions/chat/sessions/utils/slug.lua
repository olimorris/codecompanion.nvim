--[[
===============================================================================
    File:       codecompanion/interactions/chat/sessions/utils/slug.lua
-------------------------------------------------------------------------------
    Description:
      Turns session titles into filenames.

      A slug is an identifier, not the title. The full title lives in the
      session's `_meta.json`, so a slug is free to be truncated and stripped
      down to what a filesystem will accept.
===============================================================================
--]]

local M = {}

local MAX_LENGTH = 50

---Trim to MAX_LENGTH on a hyphen boundary so a slug never ends mid-word
---@param slug string
---@return string
local function truncate(slug)
  if #slug <= MAX_LENGTH then
    return slug
  end
  local boundary = slug:sub(1, MAX_LENGTH + 1):match("^(.*)%-")
  return (boundary and boundary ~= "") and boundary or slug:sub(1, MAX_LENGTH)
end

---Convert a title into a lowercase, hyphenated, filesystem safe slug
---@param title string
---@return string
function M.slugify(title)
  if type(title) ~= "string" or title == "" then
    return "untitled"
  end

  local slug = title:lower()
  slug = slug:gsub("[^%w%s%-_]", "")
  slug = slug:gsub("[%s_]+", "-")
  slug = slug:gsub("%-+", "-")
  slug = slug:gsub("^%-+", ""):gsub("%-+$", "")

  if slug == "" then
    return "untitled"
  end
  return truncate(slug)
end

---Append `-2`, `-3` and so on to a slug until it is one no other session holds
---@param base string
---@param opts { is_taken: fun(slug: string): boolean, own_slug?: string }
---@return string
function M.disambiguate(base, opts)
  if base == opts.own_slug or not opts.is_taken(base) then
    return base
  end

  local suffix = 2
  while true do
    local candidate = base .. "-" .. suffix
    if candidate == opts.own_slug or not opts.is_taken(candidate) then
      return candidate
    end
    suffix = suffix + 1
  end
end

return M
