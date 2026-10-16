---
description: "Run a chain of prompts that CodeCompanion sends to the LLM in turn, from the Action Palette."
---

# Using Workflows

<p>
  <video muted controls title="Agentic workflows demo" src="https://github.com/user-attachments/assets/362b7cfd-e794-4d9c-9a74-90d5e2a87a32"></video>
</p>

A _workflow_ is a series of prompts that CodeCompanion sends to the LLM one turn at a time. Combined with [tools](/usage/chat-buffer/agents-tools), a workflow can automate a loop such as editing a file, running the tests and fixing what fails.

Workflows started as a way to bring reflection and planning prompts into the plugin, as described in [Issue 242 of The Batch](https://www.deeplearning.ai/the-batch/issue-242/).

## Running a Workflow

Open the [Action Palette](/usage/action-palette) and select a workflow. CodeCompanion ships with one, `Code workflow`.

> [!NOTE]
> Workflows can only be started from the Action Palette

To write your own, see [workflows](/configuration/prompt-library#workflows) in the prompt library and [Extending with Agentic Workflows](/extending/agentic-workflows).
