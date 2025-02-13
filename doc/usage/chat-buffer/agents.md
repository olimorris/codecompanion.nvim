# Using Agents and Tools

> [!TIP]
> More information on how agents and tools work and how you can create your own can be found in the [Creating Tools](/extending/tools.md) guide.

<p align="center">
<img src="https://github.com/user-attachments/assets/f4a5d52a-0de5-422d-a054-f7e97bb76f62" />
</p>

As outlined by Andrew Ng in [Agentic Design Patterns Part 3, Tool Use](https://www.deeplearning.ai/the-batch/agentic-design-patterns-part-3-tool-use), LLMs can act as agents by leveraging external tools. Andrew notes some common examples such as web searching or code execution that have obvious benefits when using LLMs.

In the plugin, tools are simply context and actions that are shared with an LLM via a `system` prompt. The LLM and the chat buffer act as an agent by orchestrating their use within Neovim. Tools give LLM's knowledge and a defined schema which can be included in the response for the plugin to parse, execute and feedback on. Agents and tools can be added as a participant to the chat buffer by using the `@` key.

> [!IMPORTANT]
> The agentic use of some tools in the plugin results in you, the developer, acting as the human-in-the-loop and
> approving their use. I intend on making this easier in the coming releases

## How Tools Work

LLMs are instructured by the plugin to return a structured XML block which has been defined for each tool. The chat buffer parses the LLMs response and detects any tool use before calling the appropriate tool. The chat buffer will then be updated with the outcome. Depending on the tool, flags may be inserted on the chat buffer for later processing.

## @cmd_runner

The _@cmd_runner_ tool enables an LLM to execute commands on your machine, subject to your authorization. A common example can be asking the LLM to run your test suite and provide feedback on any failures. Some commands do not write any data to [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_output_(stdout)) which means the plugin can't pass the output of the execution to the LLM. When this occurs, the tool will instead share the exit code.

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

The _@editor_ tool enables an LLM to modify the code in a Neovim buffer. If a buffer's content has been shared with the LLM then the tool can be used to add, edit or delete specific lines. Consider pinning or watching a buffer to avoid manually re-sending a buffer's content to the LLM.

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

## @rag

The _@rag_ tool uses [jina.ai](https://jina.ai) to parse a given URL's content and convert it into plain text before sharing with the LLM. It also gives the LLM the ability to search the internet for information.

## @full_stack_dev

The _@full_stack_dev_ agent is a combination of the _@cmd_runner_, _@editor_ and _@files_ tools.

## Useful Tips

### Automatic Tool Mode

The plugin allows you to run tools on autopilot. This automatically approves any tool use instead of prompting the user, disables any diffs, and automatically saves any buffers that the agent has edited. Simply set the global variable `vim.g.codecompanion_auto_tool_mode` to enable this or set it to `nil` to undo this. Alternatively, the keymap `gta` will toggle  the feature whist from the chat buffer.

