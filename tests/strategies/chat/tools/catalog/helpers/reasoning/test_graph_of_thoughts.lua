local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        GoT = require('codecompanion.strategies.chat.tools.catalog.helpers.reasoning.graph_of_thoughts')
        ThoughtNode = GoT.ThoughtNode
        Edge = GoT.Edge
        GraphOfThoughts = GoT.GraphOfThoughts
      ]])
    end,
    post_once = child.stop,
  },
})

-- Test ThoughtNode class
T["ThoughtNode can be created with default values"] = function()
  child.lua([[
    node = ThoughtNode.new()
  ]])

  local node = child.lua_get("node")

  h.eq("string", type(node.id))
  h.eq("", node.content)
  h.eq("analysis", node.type)
  h.eq(0.0, node.score)
  h.eq(0.0, node.confidence)
  h.eq("number", type(node.created_at))
  h.eq("number", type(node.updated_at))
end

T["ThoughtNode can be created with custom values"] = function()
  child.lua([[
    node = ThoughtNode.new("Test content", "custom_id", "reasoning")
  ]])

  local node = child.lua_get("node")

  h.eq("custom_id", node.id)
  h.eq("Test content", node.content)
  h.eq("reasoning", node.type)
  h.eq(0.0, node.score)
  h.eq(0.0, node.confidence)
end

T["ThoughtNode set_score updates score and confidence"] = function()
  child.lua([[
    node = ThoughtNode.new()
    initial_updated_at = node.updated_at

    -- Wait a moment to ensure timestamp changes
    os.execute("sleep 0.1")

    node:set_score(5.5, 0.8)
  ]])

  local node = child.lua_get("node")
  local initial_updated_at = child.lua_get("initial_updated_at")

  h.eq(5.5, node.score)
  h.eq(0.8, node.confidence)
  h.expect_truthy(node.updated_at >= initial_updated_at)
end

T["ThoughtNode set_score works with partial parameters"] = function()
  child.lua([[
    node = ThoughtNode.new()
    node.score = 2.0
    node.confidence = 0.5

    -- Only update score
    node:set_score(3.0)

    score_only_result = {score = node.score, confidence = node.confidence}

    -- Only update confidence
    node:set_score(nil, 0.9)

    confidence_only_result = {score = node.score, confidence = node.confidence}
  ]])

  local score_only_result = child.lua_get("score_only_result")
  local confidence_only_result = child.lua_get("confidence_only_result")

  h.eq(3.0, score_only_result.score)
  h.eq(0.5, score_only_result.confidence)

  h.eq(3.0, confidence_only_result.score)
  h.eq(0.9, confidence_only_result.confidence)
end

-- Test ThoughtNode suggestion generation
T["ThoughtNode generates analysis suggestions"] = function()
  child.lua([[
    node = ThoughtNode.new("Complex problem analysis", "test_id", "analysis")
    suggestions = node:generate_suggestions()
  ]])

  local suggestions = child.lua_get("suggestions")

  h.eq("table", type(suggestions))
  h.eq(4, #suggestions)
  h.expect_contains("Sub-questions", table.concat(suggestions, " "))
  h.expect_contains("Assumptions", table.concat(suggestions, " "))
  h.expect_contains("Data needed", table.concat(suggestions, " "))
  h.expect_contains("Related cases", table.concat(suggestions, " "))
end

T["ThoughtNode generates reasoning suggestions"] = function()
  child.lua([[
    node = ThoughtNode.new("Logical deduction", "test_id", "reasoning")
    suggestions = node:generate_suggestions()
  ]])

  local suggestions = child.lua_get("suggestions")

  h.eq(4, #suggestions)
  h.expect_contains("Implications", table.concat(suggestions, " "))
  h.expect_contains("Supporting evidence", table.concat(suggestions, " "))
  h.expect_contains("Counter-arguments", table.concat(suggestions, " "))
  h.expect_contains("Next steps", table.concat(suggestions, " "))
end

T["ThoughtNode generates task suggestions"] = function()
  child.lua([[
    node = ThoughtNode.new("Implement feature", "test_id", "task")
    suggestions = node:generate_suggestions()
  ]])

  local suggestions = child.lua_get("suggestions")

  h.eq(4, #suggestions)
  h.expect_contains("Implementation steps", table.concat(suggestions, " "))
  h.expect_contains("Alternative approaches", table.concat(suggestions, " "))
  h.expect_contains("Resources needed", table.concat(suggestions, " "))
  h.expect_contains("Success criteria", table.concat(suggestions, " "))
end

T["ThoughtNode generates validation suggestions"] = function()
  child.lua([[
    node = ThoughtNode.new("Test solution", "test_id", "validation")
    suggestions = node:generate_suggestions()
  ]])

  local suggestions = child.lua_get("suggestions")

  h.eq(4, #suggestions)
  h.expect_contains("Test cases", table.concat(suggestions, " "))
  h.expect_contains("Success metrics", table.concat(suggestions, " "))
  h.expect_contains("Edge cases", table.concat(suggestions, " "))
  h.expect_contains("Failure recovery", table.concat(suggestions, " "))
end

T["ThoughtNode generates synthesis suggestions"] = function()
  child.lua([[
    node = ThoughtNode.new("Combined ideas", "test_id", "synthesis")
    suggestions = node:generate_suggestions()
  ]])

  local suggestions = child.lua_get("suggestions")

  h.eq(4, #suggestions)
  h.expect_contains("Integration", table.concat(suggestions, " "))
  h.expect_contains("Trade-offs", table.concat(suggestions, " "))
  h.expect_contains("Refinement", table.concat(suggestions, " "))
  h.expect_contains("Applications", table.concat(suggestions, " "))
end

T["ThoughtNode generates default suggestions for unknown type"] = function()
  child.lua([[
    node = ThoughtNode.new("Unknown type", "test_id", "unknown")
    suggestions = node:generate_suggestions()
  ]])

  local suggestions = child.lua_get("suggestions")

  h.eq(1, #suggestions)
  h.expect_contains("Next steps", suggestions[1])
end

-- Test Edge class
T["Edge can be created with default values"] = function()
  child.lua([[
    edge = Edge.new("source1", "target1")
  ]])

  local edge = child.lua_get("edge")

  h.eq("source1", edge.source)
  h.eq("target1", edge.target)
  h.eq(1.0, edge.weight)
  h.eq("depends_on", edge.type)
  h.eq("number", type(edge.created_at))
end

T["Edge can be created with custom values"] = function()
  child.lua([[
    edge = Edge.new("source2", "target2", 2.5, "contributes_to")
  ]])

  local edge = child.lua_get("edge")

  h.eq("source2", edge.source)
  h.eq("target2", edge.target)
  h.eq(2.5, edge.weight)
  h.eq("contributes_to", edge.type)
end

-- Test GraphOfThoughts class initialization
T["GraphOfThoughts can be created"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
  ]])

  local graph = child.lua_get("graph")

  h.eq("table", type(graph.nodes))
  h.eq("table", type(graph.edges))
  h.eq("table", type(graph.reverse_edges))
  h.eq(0, vim.tbl_count(graph.nodes))
end

-- Test node management
T["GraphOfThoughts can add nodes with default type"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    node_id = graph:add_node("Test content")
  ]])

  local node_id = child.lua_get("node_id")

  h.eq("string", type(node_id))

  child.lua([[
    node = graph:get_node(node_id)
    node_info = {
      content = node.content,
      type = node.type,
      score = node.score
    }
  ]])

  local node_info = child.lua_get("node_info")

  h.eq("Test content", node_info.content)
  h.eq("analysis", node_info.type)
  h.eq(0.0, node_info.score)
end

T["GraphOfThoughts can add nodes with custom id and type"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    node_id = graph:add_node("Custom content", "custom_id", "reasoning")
  ]])

  local node_id = child.lua_get("node_id")

  h.eq("custom_id", node_id)

  child.lua([[
    node = graph:get_node("custom_id")
    node_info = {
      content = node.content,
      type = node.type
    }
  ]])

  local node_info = child.lua_get("node_info")

  h.eq("Custom content", node_info.content)
  h.eq("reasoning", node_info.type)
end

T["GraphOfThoughts rejects invalid node types"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    node_id, error_msg = graph:add_node("Test content", "test_id", "invalid_type")
  ]])

  local node_id = child.lua_get("node_id")
  local error_msg = child.lua_get("error_msg")

  h.expect_truthy(node_id == nil or node_id == vim.NIL)
  h.expect_contains("Invalid node type", error_msg)
  h.expect_contains("Valid types:", error_msg)
end

T["GraphOfThoughts get_node returns nil for non-existent nodes"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    node = graph:get_node("nonexistent")
  ]])

  local node = child.lua_get("node")

  h.expect_truthy(node == nil or node == vim.NIL)
end

-- Test edge management
T["GraphOfThoughts can add edges between existing nodes"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    node1_id = graph:add_node("Node 1", "node1")
    node2_id = graph:add_node("Node 2", "node2")

    success, error_msg = graph:add_edge("node1", "node2", 1.5, "leads_to")
  ]])

  local success = child.lua_get("success")
  local error_msg = child.lua_get("error_msg")

  h.eq(true, success)
  h.expect_truthy(error_msg == nil or error_msg == vim.NIL)
end

T["GraphOfThoughts rejects edges to non-existent nodes"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    graph:add_node("Node 1", "node1")

    success, error_msg = graph:add_edge("node1", "nonexistent")
  ]])

  local success = child.lua_get("success")
  local error_msg = child.lua_get("error_msg")

  h.eq(false, success)
  h.expect_contains("does not exist", error_msg)
end

T["GraphOfThoughts rejects self-loops"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    graph:add_node("Node 1", "node1")

    success, error_msg = graph:add_edge("node1", "node1")
  ]])

  local success = child.lua_get("success")
  local error_msg = child.lua_get("error_msg")

  h.eq(false, success)
  h.eq("Self-loops are not allowed", error_msg)
end

-- Test cycle detection
T["GraphOfThoughts detects no cycles in acyclic graph"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    graph:add_node("Node 1", "node1")
    graph:add_node("Node 2", "node2")
    graph:add_node("Node 3", "node3")

    graph:add_edge("node1", "node2")
    graph:add_edge("node2", "node3")

    has_cycle = graph:has_cycle()
  ]])

  local has_cycle = child.lua_get("has_cycle")

  h.eq(false, has_cycle)
end

T["GraphOfThoughts detects cycles in cyclic graph"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    graph:add_node("Node 1", "node1")
    graph:add_node("Node 2", "node2")
    graph:add_node("Node 3", "node3")

    graph:add_edge("node1", "node2")
    graph:add_edge("node2", "node3")
    graph:add_edge("node3", "node1")  -- Creates cycle

    has_cycle = graph:has_cycle()
  ]])

  local has_cycle = child.lua_get("has_cycle")

  h.eq(true, has_cycle)
end

T["GraphOfThoughts detects self-referencing cycle"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    graph:add_node("Node 1", "node1")
    graph:add_node("Node 2", "node2")

    -- This should not create a self-loop due to validation, but test anyway
    graph:add_edge("node1", "node2")
    graph:add_edge("node2", "node1")  -- Creates 2-node cycle

    has_cycle = graph:has_cycle()
  ]])

  local has_cycle = child.lua_get("has_cycle")

  h.eq(true, has_cycle)
end

-- Test topological sort
T["GraphOfThoughts performs topological sort on acyclic graph"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    graph:add_node("Task A", "a")
    graph:add_node("Task B", "b")
    graph:add_node("Task C", "c")
    graph:add_node("Task D", "d")

    -- A -> B -> D, A -> C -> D
    graph:add_edge("a", "b")
    graph:add_edge("a", "c")
    graph:add_edge("b", "d")
    graph:add_edge("c", "d")

    sorted_nodes, error_msg = graph:topological_sort()
  ]])

  local sorted_nodes = child.lua_get("sorted_nodes")
  local error_msg = child.lua_get("error_msg")

  h.expect_truthy(error_msg == nil or error_msg == vim.NIL)
  h.eq(4, #sorted_nodes)

  -- 'a' should come before 'b' and 'c'
  local a_pos, b_pos, c_pos, d_pos
  for i, node_id in ipairs(sorted_nodes) do
    if node_id == "a" then
      a_pos = i
    elseif node_id == "b" then
      b_pos = i
    elseif node_id == "c" then
      c_pos = i
    elseif node_id == "d" then
      d_pos = i
    end
  end

  h.expect_truthy(a_pos < b_pos)
  h.expect_truthy(a_pos < c_pos)
  h.expect_truthy(b_pos < d_pos)
  h.expect_truthy(c_pos < d_pos)
end

T["GraphOfThoughts rejects topological sort on cyclic graph"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    graph:add_node("Node 1", "node1")
    graph:add_node("Node 2", "node2")
    graph:add_node("Node 3", "node3")

    graph:add_edge("node1", "node2")
    graph:add_edge("node2", "node3")
    graph:add_edge("node3", "node1")  -- Creates cycle

    sorted_nodes, error_msg = graph:topological_sort()
  ]])

  local sorted_nodes = child.lua_get("sorted_nodes")
  local error_msg = child.lua_get("error_msg")

  h.expect_truthy(sorted_nodes == nil or sorted_nodes == vim.NIL)
  h.expect_contains("cycles", error_msg)
end

T["GraphOfThoughts handles topological sort of single node"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    graph:add_node("Single node", "single")

    sorted_nodes, error_msg = graph:topological_sort()
  ]])

  local sorted_nodes = child.lua_get("sorted_nodes")
  local error_msg = child.lua_get("error_msg")

  h.expect_truthy(error_msg == nil or error_msg == vim.NIL)
  h.eq(1, #sorted_nodes)
  h.eq("single", sorted_nodes[1])
end

T["GraphOfThoughts handles topological sort of empty graph"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    sorted_nodes, error_msg = graph:topological_sort()
  ]])

  local sorted_nodes = child.lua_get("sorted_nodes")
  local error_msg = child.lua_get("error_msg")

  h.expect_truthy(error_msg == nil or error_msg == vim.NIL)
  h.eq(0, #sorted_nodes)
end

-- Test score propagation
T["GraphOfThoughts propagates scores to dependent nodes"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    graph:add_node("Source", "source")
    graph:add_node("Target", "target")

    graph:add_edge("source", "target")

    -- Set score on source node
    source_node = graph:get_node("source")
    source_node.score = 10.0

    -- Get initial target score
    target_node = graph:get_node("target")
    initial_target_score = target_node.score

    -- Propagate scores
    graph:propagate_scores("source")

    -- Get updated target score
    final_target_score = target_node.score
  ]])

  local initial_target_score = child.lua_get("initial_target_score")
  local final_target_score = child.lua_get("final_target_score")

  h.eq(0.0, initial_target_score)
  h.expect_truthy(final_target_score > initial_target_score)
end

T["GraphOfThoughts handles score propagation for non-existent node"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    -- This should not crash
    graph:propagate_scores("nonexistent")
    result = "success"
  ]])

  local result = child.lua_get("result")
  h.eq("success", result)
end

-- Test utility functions
T["GraphOfThoughts get_node_count returns correct count"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    initial_count = graph:get_node_count()

    graph:add_node("Node 1")
    graph:add_node("Node 2")
    graph:add_node("Node 3")

    final_count = graph:get_node_count()
  ]])

  local initial_count = child.lua_get("initial_count")
  local final_count = child.lua_get("final_count")

  h.eq(0, initial_count)
  h.eq(3, final_count)
end

T["GraphOfThoughts get_stats returns correct statistics"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()

    graph:add_node("Node 1", "node1")
    graph:add_node("Node 2", "node2")
    graph:add_node("Node 3", "node3")

    graph:add_edge("node1", "node2")
    graph:add_edge("node2", "node3")

    stats = graph:get_stats()
  ]])

  local stats = child.lua_get("stats")

  h.eq(3, stats.total_nodes)
  h.eq(2, stats.total_edges)
end

-- Test serialization
T["GraphOfThoughts can serialize and deserialize"] = function()
  child.lua([[
    -- Create original graph
    original = GraphOfThoughts.new()
    original:add_node("Node 1", "node1", "analysis")
    original:add_node("Node 2", "node2", "reasoning")
    original:add_edge("node1", "node2", 1.5, "leads_to")

    -- Set some scores
    original:get_node("node1"):set_score(5.0, 0.8)
    original:get_node("node2"):set_score(3.0, 0.6)

    -- Serialize
    serialized_data = original:serialize()

    -- Create new graph and deserialize
    restored = GraphOfThoughts.new()
    restored:deserialize(serialized_data)

    -- Compare key attributes
    comparison = {
      original_node_count = original:get_node_count(),
      restored_node_count = restored:get_node_count(),
      original_stats = original:get_stats(),
      restored_stats = restored:get_stats(),
      original_node1_content = original:get_node("node1").content,
      restored_node1_content = restored:get_node("node1").content,
      original_node1_score = original:get_node("node1").score,
      restored_node1_score = restored:get_node("node1").score
    }
  ]])

  local comparison = child.lua_get("comparison")

  h.eq(comparison.original_node_count, comparison.restored_node_count)
  h.eq(comparison.original_stats.total_nodes, comparison.restored_stats.total_nodes)
  h.eq(comparison.original_stats.total_edges, comparison.restored_stats.total_edges)
  h.eq(comparison.original_node1_content, comparison.restored_node1_content)
  h.eq(comparison.original_node1_score, comparison.restored_node1_score)
end

T["GraphOfThoughts serialization handles empty graph"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    serialized_data = graph:serialize()

    restored = GraphOfThoughts.new()
    restored:deserialize(serialized_data)

    comparison = {
      original_count = graph:get_node_count(),
      restored_count = restored:get_node_count()
    }
  ]])

  local comparison = child.lua_get("comparison")

  h.eq(0, comparison.original_count)
  h.eq(0, comparison.restored_count)
end

-- Test node merging
T["GraphOfThoughts can merge multiple nodes"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()

    -- Add source nodes
    graph:add_node("Idea 1", "idea1", "analysis")
    graph:add_node("Idea 2", "idea2", "reasoning")
    graph:add_node("Idea 3", "idea3", "task")

    -- Set different scores
    graph:get_node("idea1"):set_score(2.0, 0.5)
    graph:get_node("idea2"):set_score(4.0, 0.7)
    graph:get_node("idea3"):set_score(6.0, 0.9)

    initial_node_count = graph:get_node_count()

    -- Merge nodes
    success, merged_id = graph:merge_nodes({"idea1", "idea2", "idea3"}, "Combined ideas", "merged")

    final_node_count = graph:get_node_count()
    merged_node = graph:get_node(merged_id)

    merge_result = {
      success = success,
      merged_id = merged_id,
      initial_count = initial_node_count,
      final_count = final_node_count,
      merged_content = merged_node.content,
      merged_score = merged_node.score,
      merged_confidence = merged_node.confidence
    }
  ]])

  local merge_result = child.lua_get("merge_result")

  h.eq(true, merge_result.success)
  h.eq("merged", merge_result.merged_id)
  h.eq(3, merge_result.initial_count)
  h.eq(4, merge_result.final_count) -- 3 original + 1 merged
  h.eq("Combined ideas", merge_result.merged_content)
  h.expect_truthy(math.abs(merge_result.merged_score - 4.0) < 0.001) -- Average of 2, 4, 6
  h.expect_truthy(math.abs(merge_result.merged_confidence - 0.7) < 0.001) -- Average of 0.5, 0.7, 0.9
end

T["GraphOfThoughts merge_nodes works with auto-generated id"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()

    graph:add_node("Node 1", "node1")
    graph:add_node("Node 2", "node2")

    success, merged_id = graph:merge_nodes({"node1", "node2"}, "Merged content")
  ]])

  local success = child.lua_get("success")
  local merged_id = child.lua_get("merged_id")

  h.eq(true, success)
  h.eq("string", type(merged_id))
  h.expect_truthy(#merged_id > 0)
end

T["GraphOfThoughts merge_nodes rejects non-existent source nodes"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()

    graph:add_node("Node 1", "node1")

    success, error_msg = graph:merge_nodes({"node1", "nonexistent"}, "Merged content")
  ]])

  local success = child.lua_get("success")
  local error_msg = child.lua_get("error_msg")

  h.eq(false, success)
  h.expect_contains("does not exist", error_msg)
end

T["GraphOfThoughts merge_nodes creates edges to merged node"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()

    graph:add_node("Source 1", "src1")
    graph:add_node("Source 2", "src2")

    success, merged_id = graph:merge_nodes({"src1", "src2"}, "Merged", "merged")

    -- Check if edges were created
    merged_node = graph:get_node(merged_id)
    edges_exist = graph.reverse_edges[merged_id] ~= nil and
                  graph.reverse_edges[merged_id]["src1"] ~= nil and
                  graph.reverse_edges[merged_id]["src2"] ~= nil
  ]])

  local success = child.lua_get("success")
  local edges_exist = child.lua_get("edges_exist")

  h.eq(true, success)
  h.eq(true, edges_exist)
end

-- Test edge cases and error conditions
T["GraphOfThoughts handles empty node content gracefully"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    node_id = graph:add_node("", "empty_content")
    node = graph:get_node(node_id)
  ]])

  local node = child.lua_get("node")

  h.eq("", node.content)
  h.eq("empty_content", node.id)
end

T["GraphOfThoughts handles nil content gracefully"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()
    node_id = graph:add_node(nil, "nil_content")
    node = graph:get_node(node_id)
  ]])

  local node = child.lua_get("node")

  h.eq("", node.content) -- Should default to empty string
  h.eq("nil_content", node.id)
end

-- Test complex graph scenarios
T["GraphOfThoughts handles complex multi-path dependencies"] = function()
  child.lua([[
    graph = GraphOfThoughts.new()

    -- Create a diamond dependency pattern
    graph:add_node("Start", "start")
    graph:add_node("Path A", "a")
    graph:add_node("Path B", "b")
    graph:add_node("End", "end")

    graph:add_edge("start", "a")
    graph:add_edge("start", "b")
    graph:add_edge("a", "end")
    graph:add_edge("b", "end")

    has_cycle = graph:has_cycle()
    sorted_nodes, sort_error = graph:topological_sort()
    stats = graph:get_stats()
  ]])

  local has_cycle = child.lua_get("has_cycle")
  local sorted_nodes = child.lua_get("sorted_nodes")
  local sort_error = child.lua_get("sort_error")
  local stats = child.lua_get("stats")

  h.eq(false, has_cycle)
  h.expect_truthy(sort_error == nil or sort_error == vim.NIL)
  h.eq(4, #sorted_nodes)
  h.eq(4, stats.total_nodes)
  h.eq(4, stats.total_edges)
end

return T
