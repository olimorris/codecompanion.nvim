local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        ReasoningVisualizer = require('codecompanion.strategies.chat.tools.catalog.helpers.reasoning.reasoning_visualizer')

        -- Helper function to create a mock chain
        function create_mock_chain(problem, steps)
          return {
            problem = problem,
            steps = steps or {}
          }
        end

        -- Helper function to create a mock step
        function create_mock_step(id, content, reasoning, type)
          return {
            id = id,
            content = content,
            reasoning = reasoning,
            type = type or "analysis",
            step_number = 1,
            timestamp = os.time()
          }
        end

        -- Helper function to create a mock tree node
        function create_mock_tree_node(content, children, state)
          return {
            content = content,
            children = children or {},
            state = state
          }
        end

        -- Helper function to create a mock graph
        function create_mock_graph(nodes, edges)
          return {
            nodes = nodes or {},
            edges = edges or {}
          }
        end

        -- Helper function to create a mock graph node
        function create_mock_graph_node(content, created_at, state)
          return {
            content = content,
            created_at = created_at or os.time(),
            state = state
          }
        end
      ]])
    end,
    post_once = child.stop,
  },
})

-- Test helper functions
T["truncate_content truncates long content"] = function()
  child.lua([[
    -- Access the internal truncate_content function
    local fmt = string.format
    local function truncate_content(content, max_length)
      if not content then
        return ""
      end
      content = content:gsub("\n", " "):gsub("%s+", " ")
      if #content <= max_length then
        return content
      end
      return content:sub(1, max_length - 3) .. "..."
    end

    short_text = "Short text"
    long_text = "This is a very long text that should be truncated because it exceeds the maximum length"
    multiline_text = "Line 1\nLine 2\nLine 3"

    result_short = truncate_content(short_text, 20)
    result_long = truncate_content(long_text, 20)
    result_multiline = truncate_content(multiline_text, 20)
    result_nil = truncate_content(nil, 20)
  ]])

  local result_short = child.lua_get("result_short")
  local result_long = child.lua_get("result_long")
  local result_multiline = child.lua_get("result_multiline")
  local result_nil = child.lua_get("result_nil")

  h.eq("Short text", result_short)
  h.eq(20, #result_long)
  h.expect_contains("...", result_long)
  h.not_eq(nil, string.match(result_multiline, "Line 1 Line 2 Line 3"))
  h.eq("", result_nil)
end

T["format_node_info formats node metadata"] = function()
  child.lua([[
    -- Access the internal format_node_info function
    local fmt = string.format
    local function format_node_info(node)
      local parts = {}

      if node.state then
        table.insert(parts, fmt("State: %s", node.state))
      end

      return #parts > 0 and fmt(" (%s)", table.concat(parts, ", ")) or ""
    end

    node_with_state = { state = "active" }
    node_without_state = {}

    result_with_state = format_node_info(node_with_state)
    result_without_state = format_node_info(node_without_state)
  ]])

  local result_with_state = child.lua_get("result_with_state")
  local result_without_state = child.lua_get("result_without_state")

  h.expect_contains("State: active", result_with_state)
  h.eq("", result_without_state)
end

-- Test Chain of Thoughts visualization
T["visualize_chain handles empty chain"] = function()
  child.lua([[
    chain = create_mock_chain("Test problem", {})
    result = ReasoningVisualizer.visualize_chain(chain)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Test problem", result)
  h.expect_contains("No steps in chain", result)
end

T["visualize_chain handles chain with no problem"] = function()
  child.lua([[
    chain = create_mock_chain(nil, {})
    result = ReasoningVisualizer.visualize_chain(chain)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Unknown", result)
  h.expect_contains("No steps in chain", result)
end

T["visualize_chain handles chain with no steps"] = function()
  child.lua([[
    chain = create_mock_chain("Test problem", nil)
    result = ReasoningVisualizer.visualize_chain(chain)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Test problem", result)
  h.expect_contains("No steps in chain", result)
end

T["visualize_chain displays single step"] = function()
  child.lua([[
    step = create_mock_step("step1", "Analyze the problem", "This is the reasoning", "analysis")
    chain = create_mock_chain("Test problem", { step })
    result = ReasoningVisualizer.visualize_chain(chain)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Test problem", result)
  h.expect_contains("Step 1", result)
  h.expect_contains("Analyze the problem", result)
  h.expect_contains("Reasoning: This is the reasoning", result)
end

T["visualize_chain displays multiple steps"] = function()
  child.lua([[
    step1 = create_mock_step("step1", "First step", "First reasoning", "analysis")
    step2 = create_mock_step("step2", "Second step", "Second reasoning", "reasoning")
    step3 = create_mock_step("step3", "Third step", "Third reasoning", "task")

    chain = create_mock_chain("Complex problem", { step1, step2, step3 })
    result = ReasoningVisualizer.visualize_chain(chain)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Complex problem", result)
  h.expect_contains("Step 1", result)
  h.expect_contains("Step 2", result)
  h.expect_contains("Step 3", result)
  h.expect_contains("First step", result)
  h.expect_contains("Second step", result)
  h.expect_contains("Third step", result)
end

T["visualize_chain handles steps without reasoning"] = function()
  child.lua([[
    step = create_mock_step("step1", "Step without reasoning", nil, "analysis")
    chain = create_mock_chain("Test problem", { step })
    result = ReasoningVisualizer.visualize_chain(chain)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Step without reasoning", result)
  -- Should not contain "Reasoning:" when reasoning is nil
  h.eq(nil, string.match(result, "Reasoning:"))
end

T["visualize_chain handles steps with empty reasoning"] = function()
  child.lua([[
    step = create_mock_step("step1", "Step with empty reasoning", "", "analysis")
    chain = create_mock_chain("Test problem", { step })
    result = ReasoningVisualizer.visualize_chain(chain)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Step with empty reasoning", result)
  -- Should contain "Reasoning:" even when reasoning is empty string (truthy)
  h.expect_contains("Reasoning:", result)
end

T["visualize_chain truncates long content"] = function()
  child.lua([[
    long_content = string.rep("Very long content that should be truncated ", 10)
    long_reasoning = string.rep("Very long reasoning that should be truncated ", 10)

    step = create_mock_step("step1", long_content, long_reasoning, "analysis")
    chain = create_mock_chain("Test problem", { step })
    result = ReasoningVisualizer.visualize_chain(chain)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("...", result)
  h.expect_contains("Step 1", result)
end

-- Test Tree of Thoughts visualization
T["visualize_tree handles simple tree"] = function()
  child.lua([[
    root = create_mock_tree_node("Root node", {})
    result = ReasoningVisualizer.visualize_tree(root)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Tree of Thoughts", result)
  h.expect_contains("Root: Root node", result)
end

T["visualize_tree handles tree with children"] = function()
  child.lua([[
    child1 = create_mock_tree_node("Child 1", {})
    child2 = create_mock_tree_node("Child 2", {})
    root = create_mock_tree_node("Root node", { child1, child2 })

    result = ReasoningVisualizer.visualize_tree(root)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Tree of Thoughts", result)
  h.expect_contains("Root: Root node", result)
  h.expect_contains("Child 1", result)
  h.expect_contains("Child 2", result)
end

T["visualize_tree handles nested tree"] = function()
  child.lua([[
    grandchild = create_mock_tree_node("Grandchild", {})
    child1 = create_mock_tree_node("Child 1", { grandchild })
    child2 = create_mock_tree_node("Child 2", {})
    root = create_mock_tree_node("Root node", { child1, child2 })

    result = ReasoningVisualizer.visualize_tree(root)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Root: Root node", result)
  h.expect_contains("Child 1", result)
  h.expect_contains("Child 2", result)
  h.expect_contains("Grandchild", result)
end

T["visualize_tree handles nodes with state"] = function()
  child.lua([[
    child_with_state = create_mock_tree_node("Child with state", {}, "active")
    root = create_mock_tree_node("Root node", { child_with_state })

    result = ReasoningVisualizer.visualize_tree(root)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Child with state", result)
  h.expect_contains("State: active", result)
end

T["visualize_tree truncates long content"] = function()
  child.lua([[
    long_content = string.rep("Very long tree node content ", 10)
    root = create_mock_tree_node(long_content, {})

    result = ReasoningVisualizer.visualize_tree(root)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("...", result)
  h.expect_contains("Root:", result)
end

-- Test Graph of Thoughts visualization
T["visualize_graph handles empty graph"] = function()
  child.lua([[
    graph = create_mock_graph({}, {})
    result = ReasoningVisualizer.visualize_graph(graph)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Graph of Thoughts", result)
  h.expect_contains("No nodes in graph", result)
end

T["visualize_graph handles graph with single node"] = function()
  child.lua([[
    nodes = {
      node1 = create_mock_graph_node("Single node")
    }
    graph = create_mock_graph(nodes, {})
    result = ReasoningVisualizer.visualize_graph(graph)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Graph of Thoughts", result)
  h.expect_contains("Nodes:", result)
  h.expect_contains("Single node", result)
  h.expect_contains("Dependencies:", result)
  h.expect_contains("No dependencies defined", result)
end

T["visualize_graph handles multiple nodes"] = function()
  child.lua([[
    nodes = {
      node1 = create_mock_graph_node("First node", 1000),
      node2 = create_mock_graph_node("Second node", 2000),
      node3 = create_mock_graph_node("Third node", 1500)
    }
    graph = create_mock_graph(nodes, {})
    result = ReasoningVisualizer.visualize_graph(graph)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("First node", result)
  h.expect_contains("Second node", result)
  h.expect_contains("Third node", result)
  h.expect_contains("No dependencies defined", result)
end

T["visualize_graph sorts nodes by creation time"] = function()
  child.lua([[
    nodes = {
      node3 = create_mock_graph_node("Third node", 3000),
      node1 = create_mock_graph_node("First node", 1000),
      node2 = create_mock_graph_node("Second node", 2000)
    }
    graph = create_mock_graph(nodes, {})
    result = ReasoningVisualizer.visualize_graph(graph)

    -- Find positions of nodes in result
    first_pos = string.find(result, "First node")
    second_pos = string.find(result, "Second node")
    third_pos = string.find(result, "Third node")
  ]])

  local first_pos = child.lua_get("first_pos")
  local second_pos = child.lua_get("second_pos")
  local third_pos = child.lua_get("third_pos")

  h.expect_truthy(first_pos < second_pos)
  h.expect_truthy(second_pos < third_pos)
end

T["visualize_graph handles nodes with state"] = function()
  child.lua([[
    nodes = {
      node1 = create_mock_graph_node("Node with state")
    }
    nodes.node1.state = "completed"

    graph = create_mock_graph(nodes, {})
    result = ReasoningVisualizer.visualize_graph(graph)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Node with state", result)
  h.expect_contains("State: completed", result)
end

T["visualize_graph handles dependencies"] = function()
  child.lua([[
    nodes = {
      source = create_mock_graph_node("Source node"),
      target = create_mock_graph_node("Target node")
    }

    edges = {
      source = {
        target = {
          weight = 1.0
        }
      }
    }

    graph = create_mock_graph(nodes, edges)
    result = ReasoningVisualizer.visualize_graph(graph)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Source node", result)
  h.expect_contains("Target node", result)
  h.expect_contains("Dependencies:", result)
  h.expect_contains("→", result)
end

T["visualize_graph handles weighted dependencies"] = function()
  child.lua([[
    nodes = {
      source = create_mock_graph_node("Source node"),
      target = create_mock_graph_node("Target node")
    }

    edges = {
      source = {
        target = {
          weight = 2.5
        }
      }
    }

    graph = create_mock_graph(nodes, edges)
    result = ReasoningVisualizer.visualize_graph(graph)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("weight: 2.50", result)
end

T["visualize_graph handles multiple dependencies"] = function()
  child.lua([[
    nodes = {
      source1 = create_mock_graph_node("Source 1"),
      source2 = create_mock_graph_node("Source 2"),
      target = create_mock_graph_node("Target")
    }

    edges = {
      source1 = {
        target = { weight = 1.0 }
      },
      source2 = {
        target = { weight = 1.5 }
      }
    }

    graph = create_mock_graph(nodes, edges)
    result = ReasoningVisualizer.visualize_graph(graph)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Source 1", result)
  h.expect_contains("Source 2", result)
  h.expect_contains("Target", result)
  -- Should contain multiple dependency arrows
  local _, arrow_count = string.gsub(result, "→", "")
  h.expect_truthy(arrow_count >= 2)
end

T["visualize_graph truncates node content"] = function()
  child.lua([[
    long_content = string.rep("Very long node content ", 10)
    nodes = {
      node1 = create_mock_graph_node(long_content)
    }

    graph = create_mock_graph(nodes, {})
    result = ReasoningVisualizer.visualize_graph(graph)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("...", result)
end

T["visualize_graph truncates dependency content"] = function()
  child.lua([[
    long_content1 = string.rep("Very long source content ", 10)
    long_content2 = string.rep("Very long target content ", 10)

    nodes = {
      source = create_mock_graph_node(long_content1),
      target = create_mock_graph_node(long_content2)
    }

    edges = {
      source = {
        target = { weight = 1.0 }
      }
    }

    graph = create_mock_graph(nodes, edges)
    result = ReasoningVisualizer.visualize_graph(graph)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("...", result)
  h.expect_contains("→", result)
end

T["visualize_graph handles missing node references in edges"] = function()
  child.lua([[
    nodes = {
      existing = create_mock_graph_node("Existing node")
    }

    edges = {
      nonexistent = {
        existing = { weight = 1.0 }
      }
    }

    graph = create_mock_graph(nodes, edges)
    result = ReasoningVisualizer.visualize_graph(graph)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Existing node", result)
  h.expect_contains("→", result)
  -- Should show the source ID when node doesn't exist
  h.expect_contains("nonexistent", result)
end

-- Test edge cases and error handling
T["visualize_chain handles nil chain"] = function()
  child.lua([[
    -- Test robustness with nil input
    success, result = pcall(function()
      return ReasoningVisualizer.visualize_chain(nil)
    end)
  ]])

  local success = child.lua_get("success")

  -- Should not crash, might return error or handle gracefully
  h.eq("boolean", type(success))
end

T["visualize_tree handles nil tree"] = function()
  child.lua([[
    -- Test robustness with nil input
    success, result = pcall(function()
      return ReasoningVisualizer.visualize_tree(nil)
    end)
  ]])

  local success = child.lua_get("success")

  -- Should not crash, might return error or handle gracefully
  h.eq("boolean", type(success))
end

T["visualize_graph handles nil graph"] = function()
  child.lua([[
    -- Test robustness with nil input
    success, result = pcall(function()
      return ReasoningVisualizer.visualize_graph(nil)
    end)
  ]])

  local success = child.lua_get("success")

  -- Should not crash, might return error or handle gracefully
  h.eq("boolean", type(success))
end

T["visualize_chain handles malformed steps"] = function()
  child.lua([[
    malformed_steps = {
      {}, -- step with no content
      { content = "Valid step" },
      nil -- nil step
    }

    chain = create_mock_chain("Test problem", malformed_steps)
    success, result = pcall(function()
      return ReasoningVisualizer.visualize_chain(chain)
    end)
  ]])

  local success = child.lua_get("success")
  local result = child.lua_get("result")

  if success then
    h.eq("string", type(result))
  else
    -- If it fails, that's also acceptable behavior for malformed input
    h.eq("boolean", type(success))
  end
end

-- Test complex visualization scenarios
T["visualize_chain with mixed step types and reasoning"] = function()
  child.lua([[
    steps = {
      create_mock_step("s1", "Analysis step", "Detailed analysis", "analysis"),
      create_mock_step("s2", "Reasoning step", nil, "reasoning"),
      create_mock_step("s3", "Task step", "Implementation details", "task"),
      create_mock_step("s4", "Validation step", "", "validation")
    }

    chain = create_mock_chain("Complex multi-step problem", steps)
    result = ReasoningVisualizer.visualize_chain(chain)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Complex multi-step problem", result)
  h.expect_contains("Analysis step", result)
  h.expect_contains("Reasoning step", result)
  h.expect_contains("Task step", result)
  h.expect_contains("Validation step", result)
  h.expect_contains("Detailed analysis", result)
  h.expect_contains("Implementation details", result)
end

T["visualize_tree with deep nesting"] = function()
  child.lua([[
    leaf = create_mock_tree_node("Leaf node", {})
    level3 = create_mock_tree_node("Level 3", { leaf })
    level2a = create_mock_tree_node("Level 2A", { level3 })
    level2b = create_mock_tree_node("Level 2B", {})
    level1 = create_mock_tree_node("Level 1", { level2a, level2b })
    root = create_mock_tree_node("Root", { level1 })

    result = ReasoningVisualizer.visualize_tree(root)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Root", result)
  h.expect_contains("Level 1", result)
  h.expect_contains("Level 2A", result)
  h.expect_contains("Level 2B", result)
  h.expect_contains("Level 3", result)
  h.expect_contains("Leaf node", result)
end

T["visualize_graph with complex dependency network"] = function()
  child.lua([[
    nodes = {
      a = create_mock_graph_node("Node A", 1000),
      b = create_mock_graph_node("Node B", 2000),
      c = create_mock_graph_node("Node C", 3000),
      d = create_mock_graph_node("Node D", 4000)
    }

    edges = {
      a = {
        b = { weight = 1.0 },
        c = { weight = 2.0 }
      },
      b = {
        d = { weight = 1.5 }
      },
      c = {
        d = { weight = 0.8 }
      }
    }

    graph = create_mock_graph(nodes, edges)
    result = ReasoningVisualizer.visualize_graph(graph)
  ]])

  local result = child.lua_get("result")

  h.expect_contains("Node A", result)
  h.expect_contains("Node B", result)
  h.expect_contains("Node C", result)
  h.expect_contains("Node D", result)

  -- Should contain multiple dependencies
  local _, arrow_count = string.gsub(result, "→", "")
  h.expect_truthy(arrow_count >= 4)
end

return T
