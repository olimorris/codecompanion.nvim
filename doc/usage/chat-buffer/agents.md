# Using Agents and Tools

> [!TIP]
> More information on how agents and tools work and how you can create your own can be found in the [Creating Tools](/extending/tools.md) guide.

<p align="center">
<img src="https://github.com/user-attachments/assets/f4a5d52a-0de5-422d-a054-f7e97bb76f62" />
</p>

As outlined by Andrew Ng in [Agentic Design Patterns Part 3, Tool Use](https://www.deeplearning.ai/the-batch/agentic-design-patterns-part-3-tool-use), LLMs can act as agents by leveraging external tools. Andrew notes some common examples such as web searching or code execution that have obvious benefits when using LLMs.

In the plugin, tools are simply context and actions that are shared with an LLM via a `system` prompt. The LLM can act as an agent by requesting tools via the chat buffer which in turn orchestrates their use within Neovim. Agents and tools can be added as a participant to the chat buffer by using the `@` key.

> [!IMPORTANT]
> The agentic use of some tools in the plugin results in you, the developer, acting as the human-in-the-loop and
> approving their use. I intend on making this easier in the coming releases

## How Tools Work

When a tool is added to the chat buffer, the LLM is instructured by the plugin to return a structured XML block which has been defined for each tool. The chat buffer parses the LLMs response and detects any tool use before triggering the _agent/init.lua_ file. The agent triggers off a series of events, which sees tool's added to a queue and sequentially worked with their putput being shared back to the LLM via the chat buffer. Depending on the tool, flags may be inserted on the chat buffer for later processing.

An outline of the architecture can be seen [here](/extending/tools#architecture).

## Community Tools

There is also a thriving ecosystem of user created tools:

- [VectorCode](https://github.com/Davidyz/VectorCode/tree/main) - A code repository indexing tool to supercharge your LLM experience
- [mcphub.nvim](https://github.com/ravitemer/mcphub.nvim) - A powerful Neovim plugin for managing MCP (Model Context Protocol) servers

The section of the discussion forums which is dedicated to user created tools can be found [here](https://github.com/olimorris/codecompanion.nvim/discussions/categories/tools).

## @cmd_runner

The _@cmd_runner_ tool enables an LLM to execute commands on your machine, subject to your authorization. For example:

```md
Can you use the @cmd_runner tool to run my test suite with `pytest`?
```

```md
Use the @cmd_runner tool to install any missing libraries in my project
```

Some commands do not write any data to [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)) which means the plugin can't pass the output of the execution to the LLM. When this occurs, the tool will instead share the exit code.

The LLM is specifically instructed to detect if you're running a test suite, and if so, to insert a flag in its XML request. This is then detected and the outcome of the test is stored in the corresponding flag on the chat buffer. This makes it ideal for [workflows](/extending/workflows) to hook into.

An example of the XML that an LLM may generate for the tool:

```xml
<tools>
  <tool name="cmd_runner">
    <action>
      <command><![CDATA[make test]]></command>
      <flag>testing</flag>
    </action>
  </tool>
</tools>
```

## @editor

The _@editor_ tool enables an LLM to modify the code in a Neovim buffer. If a buffer's content has been shared with the LLM then the tool can be used to add, edit or delete specific lines. Consider pinning or watching a buffer to avoid manually re-sending a buffer's content to the LLM:

```md
Use the @editor tool refactor the code in #buffer{watch}
```

```md
Can you apply the suggested changes to the buffer with the @editor tool?
```

An example of the XML that an LLM may generate for the tool:

```xml
<tools>
  <tool name="editor">
    <action type="add">
      <code><![CDATA[
    def transfer(self, amount, account):
        pass
      ]]></code>
      <buffer>3</buffer>
      <line>15</line>
    </action>
    <action type="delete">
      <buffer>3</buffer>
      <start_line>17</start_line>
      <end_line>18</end_line>
    </action>
    <action type="update">
      <code><![CDATA[
    def deposit(self, amount):
        print(f"Depositing {amount}")
      ]]></code>
      <buffer>3</buffer>
      <start_line>11</start_line>
      <end_line>12</end_line>
    </action>
  </tool>
</tools>
```

## @files

> [!NOTE]
> All file operations require approval from the user before they're executed

The _@files_ tool leverages the [Plenary.Path](https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/path.lua) module to enable an LLM to perform various file operations on the user's disk:

- Creating a file
- Reading a file
- Reading lines from a file
- Editing a file
- Deleting a file
- Renaming a file
- Copying a file
- Moving a file

An example of the XML that an LLM may generate for the tool:

```xml
<tools>
  <tool name="files">
    <action type="create">
      <contents><![CDATA[
<example>
  <title>Sample XML</title>
  <description>This is an example XML file for the files tool.</description>
  <items>
    <item>
      <name>Item 1</name>
      <value>Value 1</value>
    </item>
    <item>
      <name>Item 2</name>
      <value>Value 2</value>
    </item>
  </items>
</example>
      ]]></contents>
      <path>/Users/Oli/Code/Python/benchmarking/exercises/practice/bank-account/example.xml</path>
    </action>
  </tool>
</tools>
```

## @full_stack_dev

The plugin enables tools to be grouped together. The _@full_stack_dev_ agent is a combination of the _@cmd_runner_, _@editor_ and _@files_ tools.

## Approvals

Some tools, such as the _@cmd_runner_, require the user to approve any actions before they can be executed. If the tool requires this a `vim.fn.confirm` dialog will prompt you for a response.

## Useful Tips

### Combining Tools

Consider combining tools for complex tasks:

```md
@full_stack_dev I want to play Snake. Can you create the game for me in Python and install any packages you need. Let's save it to ~/Code/Snake. When you've finished writing it, can you open it so I can play?
```

### Automatic Tool Mode

The plugin allows you to run tools on autopilot. This automatically approves any tool use instead of prompting the user, disables any diffs, and automatically saves any buffers that the agent has edited. Simply set the global variable `vim.g.codecompanion_auto_tool_mode` to enable this or set it to `nil` to undo this. Alternatively, the keymap `gta` will toggle  the feature whist from the chat buffer.

