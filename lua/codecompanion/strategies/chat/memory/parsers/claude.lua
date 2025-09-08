return {
  ---@param rule CodeCompanion.Chat.Memory.ProcessedRule
  ---@return string
  content = function(rule)
    local text = rule.content or ""
    -- naive "summary": first 120 chars
    return text:sub(1, 120)
  end,
}
