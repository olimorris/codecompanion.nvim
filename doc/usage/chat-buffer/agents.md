# Using Agents and Tools

> [!TIP]
> More information on how agents and tools work and how you can create your own can be found in the [Creating Tools](/extending/tools.md) guide.

<img src="https://github.com/user-attachments/assets/f4a5d52a-0de5-422d-a054-f7e97bb76f62" />

As outlined by Andrew Ng in [Agentic Design Patterns Part 3, Tool Use](https://www.deeplearning.ai/the-batch/agentic-design-patterns-part-3-tool-use), LLMs can act as agents by leveraging external tools. Andrew notes some common examples such as web searching or code execution that have obvious benefits when using LLMs.

In the plugin, tools are simply context and actions that are shared with an LLM via a `system` prompt. The LLM and the chat buffer act as an agent by orchestrating their use within Neovim. Tools give LLM's knowledge and a defined schema which can be included in the response for the plugin to parse, execute and feedback on. Agents and tools can be added as a participant to the chat buffer by using the `@` key.

> [!IMPORTANT]
> The agentic use of some tools in the plugin results in you, the developer, acting as the human-in-the-loop and
> approving their use. I intend on making this easier in the coming releases

## @cmd_runner

The _@cmd_runner_ tool enables an LLM to execute commands on your machine, subject to your authorization. A common example can be asking the LLM to run your test suite and provide feedback on any failures.

## @editor

The _@editor_ tool enables an LLM to modify the code in a Neovim buffer. If a buffer's content has been shared with the LLM then the tool can be used to add, edit or delete specific lines. Consider pinning or watching a buffer to avoid manually re-sending a buffer's content to the LLM.

## @files

The _@files_ tool enables an LLM to perform various file operations on the user's disk, such as:

- Creating a file
- Reading a file
- Editing a file
- Deleting a file
- Renaming a file
- Copying a file
- Moving a file

> [!NOTE]
> All file operations require approval from the user before they can take place

## @rag

The _@rag_ tool uses [jina.ai](https://jina.ai) to parse a given URL's content and convert it into plain text before sharing with the LLM. It also gives the LLM the ability to search the internet for information.

## @full_stack_dev

The _@full_stack_dev_ agent is a combination of the _@cmd_runner_, _@editor_ and _@files_ tools.

