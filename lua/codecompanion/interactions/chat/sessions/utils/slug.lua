---Slugify and disambiguate session titles for use as filenames.

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

---Convert a title into a filesystem-safe slug.
---Lowercase, ASCII alphanumerics + hyphens, collapsed and trimmed.
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

---Resolve a slug against an existing-slug check, appending `-2`, `-3` etc. on collision.
---@param base string Base slug from slugify()
---@param exists fun(slug: string): boolean Predicate: is this slug taken on disk?
---@param current_slug? string The session's own existing slug (treated as available)
---@return string
function M.disambiguate(base, exists, current_slug)
  if base == current_slug or not exists(base) then
    return base
  end

  local n = 2
  while true do
    local candidate = base .. "-" .. n
    if candidate == current_slug or not exists(candidate) then
      return candidate
    end
    n = n + 1
  end
end

return M
