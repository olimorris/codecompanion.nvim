---
description: "Run agentic workflows in CodeCompanion — chain multi-step LLM interactions to automate complex coding tasks, launched from the Action Palette."
---

# Using Workflows

<p>
  <video muted controls title="Agentic workflows demo" src="https://github.com/user-attachments/assets/362b7cfd-e794-4d9c-9a74-90d5e2a87a32"></video>
</p>


Workflows in CodeCompanion, are successive prompts which can be automatically sent to the LLM in a turn-based manner. This allows for actions such as reflection and planning to be easily implemented into your ways of working. They can be combined with tools to create agentic workflows, which could be used to automate common activities like editing files and then running a test suite.

I fully recommend reading [Issue 242 of The Batch](https://www.deeplearning.ai/the-batch/issue-242/) to understand the origin of workflows. They were originally [implemented](https://github.com/olimorris/codecompanion.nvim/commit/73e5a27075749b3ff60cfc796438d302d4b08715) in the plugin as an early form of [Chain-of-thought](https://en.wikipedia.org/wiki/Prompt_engineering#Chain-of-thought) prompting, via the use of reflection and planning prompts.

## Usage

Workflows can only be initiated from the [Action Palette](/usage/action-palette). This is because they are a complex Lua table structure which needs to be processed and added to a new chat buffer. Simply open up the Action Palette and select your desired workflow.

You can create your own workflows by following the [workflows](/configuration/prompt-library#workflows) configuration guide and the [agentic workflows](/extending/agentic-workflows) guide.

