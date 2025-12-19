# Tools

In the CodeCompanion plugin, tools can be leveraged by an LLM to execute lua functions or shell commands on the users machine. CodeCompanion uses an LLM's native function calling to receive a response in JSON, parse the response and call the corresponding tool. This feature has been implemented via the tools/init.lua file, which passes all of the tools and adds them to a queue. Then those tools are run consecutively by the orchestrator.lua file.

## Relevant Docs

### Tool System

@./lua/codecompanion/interactions/chat/tools/init.lua

This is the entry point for the tool system. If an LLM's response includes a function call (or tool call) then this file is triggered which in turns add tools to a queue before calling the orchestrator

### Orchestrator

@./lua/codecompanion/interactions/chat/tools/orchestrator.lua

The orchestrator file runs the tools in the queue, according to first in, first out.

### Queue

@./lua/codecompanion/interactions/chat/tools/runtime/queue.lua
@./tests/stubs/queue.txt

The implementation of the tool queue, alongside an example queue.

### Runtime Runner

@./lua/codecompanion/interactions/chat/tools/runtime/runner.lua

Runs a specific tool.

## Example Tool

@./lua/codecompanion/interactions/chat/tools/builtin/read_file.lua

This is an example of a tool in CodeCompanion that reads a file in the current working directory. It's a great example of a function tool.

@./tests/interactions/chat/tools/builtin/test_read_file.lua

This is the corresponding test for the tool.

## Chat Buffer

Tool calls and their output are stored in the chat buffer's messages like so:

````lua
{
  {
    _meta = {
      cycle = 1,
      id = 1362698421,
      index = 3,
      sent = true
    },
    content = "Can you use the cmd_runner tool to run `ls` on my machine and `pwd`?",
    opts = {
      visible = true
    },
    role = "user"
  }, {
  _meta = {
    cycle = 1,
    id = 282816993,
    index = 6
  },
  content = "I'll run both commands for you using the cmd_runner tool.",
  opts = {
    visible = true
  },
  role = "llm"
}, {
  _meta = {
    cycle = 1,
    id = 1231881590,
    index = 7
  },
  opts = {
    visible = false
  },
  role = "llm",
  tools = {
    calls = { {
      _index = 2,
      ["function"] = {
        arguments = '{"cmd": "pwd", "flag": null}',
        name = "cmd_runner"
      },
      id = "toolu_016Uw6yn4984i4nZU7Heexyj",
      type = "function"
    }, {
      _index = 3,
      ["function"] = {
        arguments = '{"cmd": "ls", "flag": null}',
        name = "cmd_runner"
      },
      id = "toolu_01ACfkNf4PsYAWDWNYjWPv8z",
      type = "function"
    } }
  }
}, {
  _meta = {
    cycle = 1,
    id = 787433392
  },
  content = "`pwd`\n```\n/Users/Oli/Code/Neovim/codecompanion.nvim\n```",
  opts = {
    visible = true
  },
  role = "tool",
  tools = {
    call_id = "toolu_016Uw6yn4984i4nZU7Heexyj",
    is_error = false,
    type = "tool_result"
  }
}, {
  _meta = {
    cycle = 1,
    id = 2065553209
  },
  content =
  "`ls`\n```\n_typos.toml\nadapter_refactor.md\nCHANGELOG.md\nCLAUDE.md\ncodecompanion-workspace.json\nCONTRIBUTING.md\ndeps\ndoc\nexamples\nLICENSE\nlua\nMakefile\nmedia\nminimal.lua\nplugin\nqueries\nREADME.md\nscripts\nstylua.toml\nsyntax\ntests\nvar\n```",
  opts = {
    visible = true
  },
  role = "tool",
  tools = {
    call_id = "toolu_01ACfkNf4PsYAWDWNYjWPv8z",
    is_error = false,
    type = "tool_result"
  }
}
}
````
