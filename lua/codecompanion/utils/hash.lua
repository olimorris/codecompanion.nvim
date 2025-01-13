local M = {}

local B = bit or bit32 or require("codecompanion.utils.native_bit")

local function hash_str(str) -- djb2, https://theartincode.stanis.me/008-djb2/
  local hash = 5381
  for i = 1, #str do
    hash = B.band((B.lshift(hash, 5) + hash + string.byte(str, i)), 0x7fffffff)
  end
  return hash
end

function M.hash(v) -- Xor hashing: https://codeforces.com/blog/entry/85900
  local t = type(v)
  if t == "table" then
    local hash = 0
    for p, u in next, v do
      hash = B.band(B.bxor(hash, hash_str(p .. M.hash(u))), 0x7fffffff)
    end
    return hash
  elseif t == "function" then
    return M.hash(string.dump(v))
  end
  return hash_str(tostring(v))
end

return M
