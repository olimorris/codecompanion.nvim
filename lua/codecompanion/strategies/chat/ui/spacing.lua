---Centralized spacing management for chat UI
---Provides consistent spacing rules across all formatters

---@class CodeCompanion.Chat.UI.Spacing
local Spacing = {}

---@class CodeCompanion.Chat.UI.SpacingContext
---@field is_new_role boolean Whether this is a new role (triggers header)
---@field is_new_section boolean Whether this is a new section under same role
---@field previous_type string|nil The type of the previous message
---@field current_type string The type of the current message
---@field has_reasoning_transition boolean Whether transitioning from reasoning to response
---@field is_reasoning_start boolean Whether starting reasoning output

---Determine spacing needed before content
---@param context CodeCompanion.Chat.UI.SpacingContext
---@param message_types table Available message type constants
---@return table lines Array of spacing lines (empty strings)
function Spacing.get_pre_content_spacing(context, message_types)
  local lines = {}

  -- Handle reasoning transitions first (highest priority)
  if context.has_reasoning_transition then
    table.insert(lines, "")
    table.insert(lines, "")
    return lines
  end

  -- Handle new sections (when type changes but role stays the same)
  if context.is_new_section then
    -- Only add spacing for LLM to Tool transitions
    if context.previous_type == message_types.LLM_MESSAGE 
       and context.current_type == message_types.TOOL_MESSAGE then
      table.insert(lines, "")
    end
    return lines
  end

  return lines
end

---Determine spacing needed after content
---@param context CodeCompanion.Chat.UI.SpacingContext
---@param message_types table Available message type constants
---@return table lines Array of spacing lines (empty strings)
function Spacing.get_post_content_spacing(context, message_types)
  local lines = {}

  -- Most content doesn't need trailing spacing
  -- The builder will handle spacing between messages
  
  -- Only tool output might need a trailing line for folding purposes
  if context.current_type == message_types.TOOL_MESSAGE then
    table.insert(lines, "")
  end

  return lines
end

---Determine spacing needed before headers
---@param context CodeCompanion.Chat.UI.SpacingContext
---@param message_types table Available message type constants
---@return table lines Array of spacing lines (empty strings)
function Spacing.get_header_spacing(context, message_types)
  local lines = {}

  -- Less aggressive spacing before headers
  if context.previous_type == message_types.TOOL_MESSAGE then
    -- Single line after tool messages
    table.insert(lines, "")
  elseif context.previous_type then
    -- Double line for other transitions (standard)
    table.insert(lines, "")
    table.insert(lines, "")
  end

  return lines
end

return Spacing