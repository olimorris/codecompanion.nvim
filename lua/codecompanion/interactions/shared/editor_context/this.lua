local log = require("codecompanion.utils.log")

---@class CodeCompanion.EditorContext.This: CodeCompanion.EditorContext
local EditorContext = {}

---@param args CodeCompanion.EditorContextArgs
function EditorContext.new(args)
  local self = setmetatable({
    buffer_context = args.buffer_context or (args.Chat and args.Chat.buffer_context),
    config = args.config,
    params = args.params,
  }, { __index = EditorContext })

  return self
end

---Return inline label and context block: delegates to selection or buffer
---@return { inline: string, block: string }|nil
function EditorContext:cli_render()
  local ctx = self.buffer_context
  if not ctx then
    log:warn("No buffer context available for #this")
    return nil
  end

  if ctx.is_visual and ctx.lines and #ctx.lines > 0 then
    return require("codecompanion.interactions.shared.editor_context.selection")
      .new({ buffer_context = ctx, config = self.config, params = self.params })
      :cli_render()
  end

  return require("codecompanion.interactions.shared.editor_context.buffer")
    .new({ buffer_context = ctx, config = self.config, params = self.params })
    :cli_render()
end

return EditorContext
