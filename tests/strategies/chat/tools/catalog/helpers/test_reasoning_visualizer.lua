local ReasoningVisualizer =
  require("codecompanion.strategies.chat.tools.catalog.helpers.reasoning.reasoning_visualizer")
local h = require("tests.helpers")

local new_set = MiniTest.new_set

local T = new_set({
  hooks = {},
})

T["ReasoningVisualizer"] = new_set()

T["ReasoningVisualizer"]["visualize_chain"] = function()
  local chain = {
    problem = "Solve a math problem",
    steps = {
      {
        content = "First, identify the variables",
        reasoning = "We need to understand what x and y represent",
        step_type = "analysis",
      },
      {
        content = "Set up the equations",
        reasoning = "Based on the problem constraints, we can form equations",
        step_type = "task",
      },
      {
        content = "Solve for x",
        reasoning = "Using substitution method",
        step_type = "reasoning",
      },
    },
    conclusion = "x = 5, y = 3",
  }

  local result = ReasoningVisualizer.visualize_chain(chain)

  -- Should contain the problem
  h.expect_contains("Solve a math problem", result)

  -- Should contain steps
  h.expect_contains("Step 1:", result)
  h.expect_contains("identify the variables", result)
  h.expect_contains("Reasoning:", result)

  -- Should use Unicode characters by default
  h.expect_contains("└", result)
end

T["ReasoningVisualizer"]["visualize_tree"] = function()
  -- Create a simple tree structure
  local root = {
    content = "Root problem: Find optimal solution",
    score = 0.8,
    children = {
      {
        content = "Approach A: Use algorithm X",
        score = 0.6,
        children = {
          {
            content = "Sub-step A1: Initialize data structures",
            score = 0.7,
            children = {},
          },
        },
      },
      {
        content = "Approach B: Use algorithm Y",
        score = 0.9,
        children = {},
      },
    },
  }

  local result = ReasoningVisualizer.visualize_tree(root)

  -- Should contain the title
  h.expect_contains("Tree of Thoughts", result)

  -- Should contain root
  h.expect_contains("Root problem", result)

  -- Should contain children
  h.expect_contains("Approach A", result)
  h.expect_contains("Approach B", result)
  h.expect_contains("Sub-step A1", result)

  -- Should use Unicode characters
  h.expect_contains("├", result)
  h.expect_contains("└", result)
end

T["ReasoningVisualizer"]["visualize_graph"] = function()
  local graph = {
    nodes = {
      node1 = {
        content = "Start node: Define problem",
        state = "completed",
        score = 1.0,
        created_at = os.time() - 100,
      },
      node2 = {
        content = "Middle node: Analyze requirements",
        state = "processing",
        score = 0.7,
        created_at = os.time() - 50,
      },
      node3 = {
        content = "End node: Implement solution",
        state = "pending",
        score = 0.0,
        created_at = os.time(),
      },
    },
    edges = {
      node1 = {
        node2 = { weight = 1.0, type = "depends_on" },
      },
      node2 = {
        node3 = { weight = 0.8, type = "leads_to" },
      },
    },
  }

  local result = ReasoningVisualizer.visualize_graph(graph)

  -- Should contain the title
  h.expect_contains("Graph of Thoughts", result)

  -- Should contain nodes section
  h.expect_contains("## Nodes:", result)
  h.expect_contains("Define problem", result)
  h.expect_contains("Analyze requirements", result)
  h.expect_contains("Implement solution", result)

  -- Should show states and scores
  h.expect_contains("completed", result)
  h.expect_contains("processing", result)
  h.expect_contains("pending", result)

  -- Should contain dependencies section
  h.expect_contains("## Dependencies:", result)
  h.expect_contains("→", result)
end

return T
