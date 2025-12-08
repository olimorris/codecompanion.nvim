# Chat Buffer User Interface

The Chat UI group contains the files responsible for rendering and formatting content in the chat buffer. This includes the message builder pattern that coordinates how different types of content (tool output, reasoning, standard messages) are formatted and displayed to the user.

## Key components

- **Builder Pattern**: The main orchestrator that handles the flow of adding headers, formatting content, and writing to the buffer with centralized state management
- **Formatters**: Specialized classes that handle different message types (tools, reasoning, standard content)
- **UI Management**: Methods for handling buffer operations, folding, and visual presentation
- **State Management**: Rich formatting state objects that track role changes, content transitions, and section boundaries
- **Section Detection**: Logic for identifying when new sections are needed (e.g., LLM message → tool output transitions)

## Key files

### Chat UI Builder

@./lua/codecompanion/interactions/chat/ui/builder.lua

The message builder coordinates the entire process of adding content to the chat buffer. It uses a fluent interface to chain operations: adding headers when roles change, formatting content through specialized formatters, writing to the buffer with proper folding, and updating internal state. It is called from the chat buffer's `add_buf_message` method which occurs throughout the codebase.

### Chat UI Formatters - Base

@./lua/codecompanion/interactions/chat/ui/formatters/base.lua

The base formatter class that defines the interface all formatters must implement. It requires formatters to implement `can_handle`, `get_tag`, and `format` methods. Each formatter receives the chat instance, allowing access to state like `last_tag` and `has_reasoning_output`.

### Chat UI Formatters - Tools

@./lua/codecompanion/interactions/chat/ui/formatters/tools.lua

Handles formatting of tool output messages. It manages spacing rules (extra line breaks after LLM messages), calculates fold information for multi-line tool output, and ensures proper visual separation between tool results and other content types.

### Chat UI Formatters - Reasoning

@./lua/codecompanion/interactions/chat/ui/formatters/reasoning.lua

Formats reasoning content from LLMs that support chain-of-thought responses. It adds the '### Reasoning' header only once per reasoning sequence and manages the `_has_reasoning_output` state to coordinate with the standard formatter for proper transitions.

### Chat UI Formatters - Standard

@./lua/codecompanion/interactions/chat/ui/formatters/standard.lua

The fallback formatter that handles regular message content. It manages transitions from reasoning to response content (adding '### Response' headers), handles spacing after tool output, and processes standard text content with proper line splitting.

### Chat UI Folds

@./lua/codecompanion/interactions/chat/ui/folds.lua

Manages visual presentation of tool output and chat context including folding functionality. It creates collapsible folds for tool output with custom fold text that shows success/failure icons and summarized content alongside folding the chat context at the top of the chat buffer. The fold text adapts based on keywords in the tool output to indicate success or failure states.

### Chat UI Icons

@./lua/codecompanion/interactions/chat/ui/icons.lua

Manages the overlaying of icons in the chat buffer for tools, based on their status. It manages this by applying extmarks in a given position which places the icon at the start of a given line. The icons are then used to indicate the status of a tool, whether it was successful or not.

### Tests

@./tests/interactions/chat/test_builder.lua

Comprehensive tests for the builder pattern covering state management, section detection, reasoning transitions, and header logic. Tests verify that the builder correctly manages formatting state across multiple message additions and properly detects when new sections or headers are needed.
