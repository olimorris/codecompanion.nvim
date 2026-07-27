# Chat Buffer User Interface

The Chat UI group contains the files responsible for rendering and formatting content in the chat buffer. This includes the builder which decides where each piece of content (tool output, reasoning, standard messages) is placed, along with the window, folds and icons that present it.

## Key components

- **Builder**: The single route for writing to the chat buffer. It tracks whose section is open and which type of block is being written, and assembles the lines for each write
- **Separators**: Tables which decide the blank lines and sub-headers that sit between one block and the next
- **Folds**: Collapsible tool output, chat context and reasoning, with custom fold text
- **Icons**: Extmark overlays which show the status of a tool call
- **Window and cursor**: Opening, hiding and locking the chat window, rendering headers, and keeping the cursor with the response as it streams

## Key files

### Chat UI Builder

@./lua/codecompanion/interactions/chat/ui/builder.lua

The message builder coordinates the entire process of adding content to the chat buffer and is driven by the chat buffer's `add_buf_message` method, which is called throughout the codebase. A section is the content under a role header, and a block is a contiguous run of one type within it: reasoning, standard LLM output, or tool output. `add_message` works out whether a write opens a new section or a new block, uses `FIRST_BLOCK` and `SEPARATORS` to decide the blank lines and sub-headers which precede the content, then hands the assembled lines to `_write`. Each tool call opens its own block even though the type repeats, so every call gets its own fold and status icon. `add_message` returns the line the write finished on and the id of any icon it placed, which callers hold onto so they can update a tool's status in place with `update_line`.

### Chat UI Window and Cursor

@./lua/codecompanion/interactions/chat/ui/init.lua

Owns the chat window: opening and hiding it, rendering the role headers and separators, locking the buffer whilst the LLM responds, and displaying the settings and token count. It also owns the cursor. Whilst a response streams the cursor follows the last line of the buffer, unless the user has moved it themselves to read back over the response. That claim is held in `cursor.moved_by_user`, which stops the autoscroll, saves their position for when the chat is reopened, and is only released when they return to the end of the buffer or send a new prompt. `is_following` is the single test for whether the cursor is still with the response and the builder samples it before every write.

### Chat UI Folds

@./lua/codecompanion/interactions/chat/ui/folds.lua

Manages visual presentation of tool output and chat context including folding functionality. It creates collapsible folds for tool output with custom fold text that shows success/failure icons and summarized content alongside folding the chat context at the top of the chat buffer. The fold text adapts based on keywords in the tool output to indicate success or failure states.

### Chat UI Icons

@./lua/codecompanion/interactions/chat/ui/icons.lua

Manages the overlaying of icons in the chat buffer for tools, based on their status. It manages this by applying extmarks in a given position which places the icon at the start of a given line. The icons are then used to indicate the status of a tool, whether it was successful or not.

### Tests

@./tests/interactions/chat/ui/test_builder_state.lua
@./tests/interactions/chat/ui/test_fold_reasoning_output.lua
@./tests/interactions/chat/tools/builtin/test_tool_output.lua

The builder state tests follow the block type through a section, check that the section anchors move when the role changes, and check that a tool fold lands on the tool's content rather than the section above it. The reasoning and tool output tests render a real chat buffer and compare screenshots, which is the closest thing to checking the layout by eye.
