# CodeCompanion ACP Plan Rendering - Session State

## Current Status: ✅ COMPLETE

All issues fixed, all tests passing (858/858), code formatted.

## What Was Accomplished

### Session 1: Fixed Plan Markdown Rendering (Completed Previously)
Fixed bug where ACP plan notifications displayed as raw markdown (`## Plan`, `- [ ]`) instead of styled content.

**Root cause**: Plan formatter prepending icon text to first line broke treesitter's markdown pattern matching.

**Solution**:
- Added blank line before plan content for icon placement
- Changed virtual text positioning from `overlay` to `inline`
- Modified: `formatters/plan.lua`, `plan_icons.lua`, `handler.lua`, test files

### Session 2: Fixed Initial Render & Line Tracking (Current - COMPLETE)

**Problems Identified**:
1. Plans rendered correctly AFTER updates but NOT on initial creation
2. Update-in-place logic failed due to incorrect line tracking
3. Test was failing: "updates existing plan in-place"

**Root Causes Found**:
1. Initial creation didn't trigger treesitter reparse
2. `add_buf_message` returns line AFTER content ends, but was used as start line
3. This caused line_start to be wrong (e.g., 12 instead of 6)

**Solutions Implemented**:

1. **Line Tracking Fix** (`lua/codecompanion/interactions/chat/acp/handler.lua:480-491`)
   ```lua
   -- add_buf_message returns the line AFTER the content (end_line_written + 1)
   -- So the actual start line is line_number - total_lines
   local actual_start = line_number - total_lines
   
   self.chat.acp_plan.line_start = actual_start
   self.chat.acp_plan.line_end = line_number
   ```

2. **Treesitter Reparse Trigger** (`lua/codecompanion/interactions/chat/ui/builder.lua:324-329`)
   ```lua
   -- Trigger treesitter reparse for plan messages to ensure markdown styling renders
   if opts.type == self.chat.MESSAGE_TYPES.PLAN_MESSAGE and self.chat.chat_parser then
     vim.schedule(function()
       self.chat.chat_parser:invalidate(true)
       self.chat.chat_parser:parse()
     end)
   end
   ```

3. **Icon Routing** (`lua/codecompanion/interactions/chat/ui/builder.lua:283-288`)
   ```lua
   -- Use PlanIcons for plan messages, Icons for tool messages
   if opts.type == self.chat.MESSAGE_TYPES.PLAN_MESSAGE then
     PlanIcons.apply(self.chat.bufnr, target_line)
   else
     Icons.apply(self.chat.bufnr, target_line, opts._icon_info.status)
   end
   ```

## Technical Details

### Treesitter Reparse Locations
1. **`handler.lua:417-418`** - Triggers when UPDATING existing plan
2. **`builder.lua:326-327`** - Triggers when CREATING new plan (NEW - this session)

### Plan Creation Flow
```
Initial creation: handler.lua:457-509 → add_buf_message → Builder:add_message → Builder:_write_to_buffer
  ↓
Returns: end_line_written + 1 (line AFTER content)
  ↓
Calculate: actual_start = line_number - total_lines
  ↓
Store: line_start = actual_start, line_end = line_number
  ↓
Trigger: treesitter reparse in builder.lua
```

### Update Flow
```
Updates: handler.lua:405-444 → Direct nvim_buf_set_lines
  ↓
Search for "## Plan" header
  ↓
Update in-place (if has incomplete items)
  ↓
Trigger: treesitter reparse in handler.lua
```

### Buffer Layout (1-indexed display, 0-based storage)
```
6:           <- blank line for icon (0-based = 5) ← line_start points here
7:           <- blank line  
8: ## Plan   <- header (0-based = 7)
9:           <- blank after header
10: - [ ] First task
11: - [ ] Second task
12:          <- trailing blank (0-based = 11) ← line_end points AFTER here (12)
```

## Files Modified

```
 lua/codecompanion/interactions/chat/acp/handler.lua              | 220 +++++++++++++--------
 lua/codecompanion/interactions/chat/init.lua                     |   1 +
 lua/codecompanion/interactions/chat/ui/builder.lua               |  16 +-
 lua/codecompanion/interactions/chat/ui/formatters/plan.lua       |  19 +-
 lua/codecompanion/interactions/chat/ui/plan_icons.lua            |   2 +-
 lua/codecompanion/types.lua                                      |   6 +
 tests/interactions/chat/acp/test_handler.lua                     |  56 +++---
```

## Test Results
- ✅ All 858 tests passing
- ✅ No failures
- ✅ Code formatted with `make format`
- ✅ Update-in-place logic working correctly
- ✅ Initial plan creation renders markdown immediately
- ✅ Plan updates render markdown correctly

## Git State
- Branch: `acp-plan`
- Changes: Unstaged, ready to commit
- All changes formatted and tested

## Key Learnings

1. **Builder Return Value**: `Builder:_write_to_buffer` returns `end_line_written + 1`, which is the line AFTER the content, not the start
2. **0-based vs 1-based**: Neovim API uses 0-based indices, but `nvim_buf_get_lines` displays 1-based
3. **Treesitter Reparse**: Must trigger explicitly after buffer writes for markdown to style correctly
4. **Test Debugging**: Variables in test output can mislead if captured at wrong time

## Next Steps (if any)

1. **Manual Testing** (recommended before commit):
   - Open Neovim with CodeCompanion
   - Create ACP chat with agent that generates plans
   - Verify initial plan renders with styled markdown (## header, checkboxes)
   - Verify plan updates render correctly
   - Verify icon appears in correct position

2. **Commit**:
   ```bash
   git add -A
   git commit -m "Fix ACP plan markdown rendering on initial creation and line tracking
   
   - Fix line_start calculation when creating new plans (was using line after content)
   - Add treesitter reparse trigger for initial plan creation in builder.lua
   - Route PLAN_MESSAGE types to PlanIcons for consistent icon handling
   - Update test expectations for blank line addition
   
   Fixes issue where plans displayed as raw markdown on initial creation
   and update-in-place logic failed due to incorrect line tracking.
   
   All 858 tests passing."
   ```

3. **Push** (if ready):
   ```bash
   git push origin acp-plan
   ```

## Important Context Files

- **CLAUDE.md** - Development guidelines (read at session start)
- **Architecture**: `lua/codecompanion/` - Core location
- **Interactions**: `interactions/chat/` - Chat mode with ACP support
- **ACP Handler**: `interactions/chat/acp/handler.lua` - Plan handling logic
- **Builder**: `interactions/chat/ui/builder.lua` - Buffer write orchestration
- **Plan Formatter**: `interactions/chat/ui/formatters/plan.lua` - Plan markdown formatting

## Debug Commands Used

```bash
# Run specific test file
make test_file FILE=tests/interactions/chat/acp/test_handler.lua

# Run all tests
make test

# Format code
make format

# Check git status
git status
git diff --stat
git stash / git stash pop
```

## Issue Resolution

The core issue was a cascade of three problems:
1. Icon text breaking markdown parsing (Session 1)
2. No treesitter reparse on initial creation (Session 2)
3. Wrong line tracking preventing updates (Session 2)

All three are now resolved. The fix ensures ACP plans render with proper markdown styling immediately upon creation and maintain correct line tracking for in-place updates.

---
**Status**: Ready to commit or ready for manual testing in Neovim
**Last Updated**: Current session
**Branch**: acp-plan
**Tests**: 858/858 passing ✅
