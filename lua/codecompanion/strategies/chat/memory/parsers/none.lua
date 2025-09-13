---@param file CodeCompanion.Chat.Memory.ProcessedFile
---@return CodeCompanion.Chat.Memory.Parser
return function(file)
  return { content = file.content or "" }
end
