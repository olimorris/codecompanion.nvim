---@param file CodeCompanion.Chat.Rules.ProcessedFile
---@return CodeCompanion.Chat.Rules.Parser
return function(file)
  return { content = file.content or "" }
end
