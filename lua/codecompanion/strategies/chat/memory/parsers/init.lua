local config = require("codecompanion.config")

local M = {}

local function is_likely_file_path(s)
  if type(s) ~= "string" then
    return false
  end
  -- starts with /, ./, ../, or ~ or ends with .lua
  return s:match("^/") or s:match("^%.") or s:match("^~") or s:match("%.lua$")
end

local function normalize_module(mod)
  if type(mod) == "function" then
    return { parse = mod }
  end
  if type(mod) == "table" then
    if type(mod.parse) == "function" then
      return { parse = mod.parse }
    end
    if type(mod.output) == "function" then
      -- Backwards compatibility: accept `output` field
      return { parse = mod.output }
    end
  end
  return nil
end

---Resolve parser spec (string|function|table) into { parse }
---@param spec string|function|table
---@return table|nil
function M.resolve(spec)
  if not spec then
    return nil
  end

  -- Allow users to reference a named parser configured in config.memory.parsers
  if type(spec) == "string" and config and config.memory and config.memory.parsers and config.memory.parsers[spec] then
    spec = config.memory.parsers[spec]
  end

  -- If it's already a normalized table with parse, accept it
  if type(spec) == "table" then
    -- If table is like { path = "...", parser = "name" } normalize to the parser value
    if spec.path and spec.parser then
      -- caller should pass the parser spec (spec.parser) to resolve again,
      -- but keep this behavior consistent: return table with parse from parser spec
      return M.resolve(spec.parser)
    end

    -- If table already contains parse/output function
    local norm = normalize_module(spec)
    if norm then
      return norm
    end

    -- If it's a plain table that contains a string spec (e.g. { "name" }), try first element
    if #spec > 0 and type(spec[1]) == "string" then
      return M.resolve(spec[1])
    end

    return nil
  end

  -- If it's a function, treat as parse-only
  if type(spec) == "function" then
    return { parse = spec }
  end

  -- If it's a string: try module under parsers folder first, then require(spec), then file path
  if type(spec) == "string" then
    local tries = {
      "codecompanion.strategies.chat.memory.parsers." .. spec,
      spec,
    }

    for _, modname in ipairs(tries) do
      local ok, mod = pcall(require, modname)
      if ok and mod ~= nil then
        local norm = normalize_module(mod)
        if norm then
          return norm
        end
      end
    end

    -- If looks like a file path, try loadfile
    if is_likely_file_path(spec) then
      local expanded = vim.fn.expand(spec)
      local ok_load, chunk = pcall(loadfile, expanded)
      if ok_load and type(chunk) == "function" then
        local ok_call, mod = pcall(chunk)
        if ok_call and mod ~= nil then
          local norm = normalize_module(mod)
          if norm then
            return norm
          end
        end
      end
    end
  end

  return nil
end

-- Builtin parsers: use `parse(rule)` signature
M.registered = {
  identity = {
    parse = function(processed)
      return processed.content or ""
    end,
  },

  -- crude markdown codeblock extractor: returns first fenced block body or full content
  markdown = {
    parse = function(processed)
      local c = processed.content or ""
      local _, _, body = c:find("```[%w%-%_%.]*\n(.-)```")
      if body then
        return body
      end
      return c
    end,
  },
}

---Resolve but check builtins by name first
---@param spec string|function|table
---@return table|nil
function M.resolve_with_builtins(spec)
  if type(spec) == "string" and M.registered[spec] then
    return M.registered[spec]
  end
  return M.resolve(spec)
end

return M
