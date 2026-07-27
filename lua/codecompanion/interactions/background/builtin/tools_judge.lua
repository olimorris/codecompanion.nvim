local log = require("codecompanion.utils.log")

local fmt = string.format

local M = {}

local VERDICT_SCHEMA = {
  name = "safety",
  schema = {
    type = "object",
    properties = {
      safe = {
        type = "boolean",
        description = "True if the action is safe to run without asking the user, false if it needs their approval",
      },
      reason = {
        type = "string",
        description = "A short explanation of the verdict, shown to the user when approval is required",
      },
    },
    required = { "safe", "reason" },
    additionalProperties = false,
  },
  strict = true,
}

local SYSTEM_PROMPT =
  [[You are a security reviewer for an AI coding assistant. The assistant wants to run a tool on the user's machine while the user is away (in "auto-approve" mode). Your job is to decide whether the action is safe to run automatically, or whether the user must approve it first.

Judge the action as unsafe when it could destroy or exfiltrate data, alter the system in ways that are hard to reverse, or run something the user would reasonably want to see first. Prefer caution: when in doubt, require approval.

Reply only through the provided schema.]]

---Parse the structured verdict from the request result
---@param result table|nil
---@return { safe: boolean, reason: string }|nil
local function parse_verdict(result)
  if not result or (result.status and result.status == "error") then
    return nil
  end

  local content = result.output and result.output.content
  if not content then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok or type(decoded) ~= "table" or type(decoded.safe) ~= "boolean" then
    return nil
  end

  return { safe = decoded.safe, reason = decoded.reason or "" }
end

---Ask the judge whether a tool's action is safe to run automatically
---@param background CodeCompanion.Background
---@param request { tool_name: string, context: string }
---@param callback fun(verdict: { safe: boolean, reason: string })
function M.request(background, request, callback)
  -- Fail closed: any failure to reach a clear verdict requires user approval
  local function require_approval(reason)
    callback({ safe = false, reason = reason })
  end

  background:ask({
    { role = "system", content = SYSTEM_PROMPT },
    {
      role = "user",
      content = fmt("The `%s` tool wants to perform this action:\n\n%s", request.tool_name, request.context),
    },
  }, {
    method = "async",
    silent = true,
    structured_output = VERDICT_SCHEMA,
    on_done = function(result)
      local verdict = parse_verdict(result)
      if not verdict then
        log:debug("[background::tools_judge] Could not read a verdict; requiring approval")
        return require_approval("The judge returned an unreadable response")
      end
      log:debug("[background::tools_judge] Verdict for `%s`: safe=%s", request.tool_name, verdict.safe)
      callback(verdict)
    end,
    on_error = function(err)
      log:debug("[background::tools_judge] Request failed: %s", err)
      require_approval("The judge request failed")
    end,
  })
end

return M
