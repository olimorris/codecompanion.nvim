# Tools

In the CodeCompanion plugin, tools can be leveraged by an LLM to execute lua functions or shell commands on the users machine. CodeCompanion uses an LLM's native function calling to receive a response in JSON, parse the response and call the corresponding tool. This feature has been implemented via the tools/init.lua file, which passes all of the tools and adds them to a queue. Then those tools are run consecutively by the orchestrator.lua file.

## Relevant Files

### Tool System

@./lua/codecompanion/strategies/chat/tools/init.lua

This is the entry point for the tool system. If an LLM's response includes a function call (or tool call) then this file is triggered which in turns add tools to a queue before calling the orchestrator

### Orchestrator

@./lua/codecompanion/strategies/chat/tools/orchestrator.lua

The orchestrator file runs the tools in the queue, according to first in, first out.

### Queue

@./lua/codecompanion/strategies/chat/tools/runtime/queue.lua
@./tests/stubs/queue.txt

The implementation of the tool queue, alongside an example queue.

### Runtime Runner

@./lua/codecompanion/strategies/chat/tools/runtime/runner.lua

Runs a specific tool.

## Example Tool

@./lua/codecompanion/strategies/chat/tools/catalog/read_file.lua

This is an example of a tool in CodeCompanion that reads a file in the current working directory. It's a great example of a function tool.

@./tests/strategies/chat/tools/catalog/test_read_file.lua

This is the corresponding test for the tool.
