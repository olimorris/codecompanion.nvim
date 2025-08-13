local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        ToT = require('codecompanion.strategies.chat.tools.catalog.helpers.reasoning.tree_of_thoughts')
        TreeNode = ToT.TreeNode
        TreeOfThoughts = ToT.TreeOfThoughts
      ]])
    end,
    post_once = child.stop,
  },
})

-- Test TreeNode class
T["TreeNode can be created with default values"] = function()
  child.lua([[
    node = TreeNode:new()
  ]])

  local node = child.lua_get("node")

  h.eq("string", type(node.id))
  h.eq("", node.content)
  h.eq("analysis", node.type)
  h.expect_truthy(node.parent == nil or node.parent == vim.NIL)
  h.eq("table", type(node.children))
  h.eq(0, #node.children)
  h.eq(0, node.depth)
  h.eq(0, node.score)
  h.eq("number", type(node.created_at))
end

T["TreeNode can be created with custom values"] = function()
  child.lua([[
    parent_node = TreeNode:new("Parent content")
    child_node = TreeNode:new("Child content", "reasoning", parent_node, 2)
  ]])

  local child_node = child.lua_get("child_node")

  h.eq("Child content", child_node.content)
  h.eq("reasoning", child_node.type)
  h.eq("table", type(child_node.parent))
  h.eq(2, child_node.depth)
end

T["TreeNode generates unique IDs"] = function()
  child.lua([[
    node1 = TreeNode:new("Node 1")
    node2 = TreeNode:new("Node 2")

    ids_different = node1.id ~= node2.id
  ]])

  local ids_different = child.lua_get("ids_different")

  h.eq(true, ids_different)
end

T["TreeNode add_child creates child with correct relationships"] = function()
  child.lua([[
    parent = TreeNode:new("Parent")
    child = parent:add_child("Child content", "task")

    -- Extract data without circular references
    child_info = {
      content = child.content,
      type = child.type,
      depth = child.depth,
      id_type = type(child.id),
      parent_children_count = #parent.children
    }
  ]])

  local child_info = child.lua_get("child_info")

  h.eq(1, child_info.parent_children_count)
  h.eq("Child content", child_info.content)
  h.eq("task", child_info.type)
  h.eq(1, child_info.depth)
  h.eq("string", child_info.id_type)
end

T["TreeNode add_child validates node types"] = function()
  child.lua([[
    parent = TreeNode:new("Parent")
    valid_child, valid_error = parent:add_child("Valid child", "validation")
    invalid_child, invalid_error = parent:add_child("Invalid child", "invalid_type")

    validation_results = {
      valid_child_exists = valid_child ~= nil,
      valid_error_is_nil = valid_error == nil,
      invalid_child_is_nil = invalid_child == nil,
      invalid_error = invalid_error
    }
  ]])

  local results = child.lua_get("validation_results")

  h.eq(true, results.valid_child_exists)
  h.eq(true, results.valid_error_is_nil)
  h.eq(true, results.invalid_child_is_nil)
  h.expect_contains("Invalid node type", results.invalid_error)
  h.expect_contains("Valid types:", results.invalid_error)
end

T["TreeNode add_child uses default type when nil"] = function()
  child.lua([[
    parent = TreeNode:new("Parent")
    child = parent:add_child("Child with default type")

    child_type = child.type
  ]])

  local child_type = child.lua_get("child_type")

  h.eq("analysis", child_type)
end

-- Test TreeNode suggestion generation
T["TreeNode generates analysis suggestions"] = function()
  child.lua([[
    node = TreeNode:new("Complex problem", "analysis")
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

T["TreeNode generates reasoning suggestions"] = function()
  child.lua([[
    node = TreeNode:new("Logical conclusion", "reasoning")
    suggestions = node:generate_suggestions()
  ]])

  local suggestions = child.lua_get("suggestions")

  h.eq(4, #suggestions)
  h.expect_contains("Implications", table.concat(suggestions, " "))
  h.expect_contains("Supporting evidence", table.concat(suggestions, " "))
  h.expect_contains("Counter-arguments", table.concat(suggestions, " "))
  h.expect_contains("Next steps", table.concat(suggestions, " "))
end

T["TreeNode generates task suggestions"] = function()
  child.lua([[
    node = TreeNode:new("Implement solution", "task")
    suggestions = node:generate_suggestions()
  ]])

  local suggestions = child.lua_get("suggestions")

  h.eq(4, #suggestions)
  h.expect_contains("Implementation steps", table.concat(suggestions, " "))
  h.expect_contains("Alternative approaches", table.concat(suggestions, " "))
  h.expect_contains("Resources needed", table.concat(suggestions, " "))
  h.expect_contains("Success criteria", table.concat(suggestions, " "))
end

T["TreeNode generates validation suggestions"] = function()
  child.lua([[
    node = TreeNode:new("Test results", "validation")
    suggestions = node:generate_suggestions()
  ]])

  local suggestions = child.lua_get("suggestions")

  h.eq(4, #suggestions)
  h.expect_contains("Test cases", table.concat(suggestions, " "))
  h.expect_contains("Success metrics", table.concat(suggestions, " "))
  h.expect_contains("Edge cases", table.concat(suggestions, " "))
  h.expect_contains("Failure recovery", table.concat(suggestions, " "))
end

T["TreeNode generates default suggestions for unknown type"] = function()
  child.lua([[
    -- Create node with custom type bypassing validation
    node = TreeNode:new("Unknown content")
    node.type = "unknown_type"
    suggestions = node:generate_suggestions()
  ]])

  local suggestions = child.lua_get("suggestions")

  h.eq(1, #suggestions)
  h.expect_contains("Next steps", suggestions[1])
end

-- Test TreeNode path operations
T["TreeNode get_path returns correct path from root"] = function()
  child.lua([[
    root = TreeNode:new("Root")
    level1 = root:add_child("Level 1")
    level2 = level1:add_child("Level 2")

    path = level2:get_path()

    path_info = {
      length = #path,
      contents = {}
    }

    for i, node in ipairs(path) do
      path_info.contents[i] = node.content
    end
  ]])

  local path_info = child.lua_get("path_info")

  h.eq(3, path_info.length)
  h.eq("Root", path_info.contents[1])
  h.eq("Level 1", path_info.contents[2])
  h.eq("Level 2", path_info.contents[3])
end

T["TreeNode get_path works for root node"] = function()
  child.lua([[
    root = TreeNode:new("Root only")
    path = root:get_path()
  ]])

  local path = child.lua_get("path")

  h.eq(1, #path)
  h.eq("Root only", path[1].content)
end

T["TreeNode is_leaf correctly identifies leaf nodes"] = function()
  child.lua([[
    parent = TreeNode:new("Parent")
    child = parent:add_child("Child")

    parent_is_leaf = parent:is_leaf()
    child_is_leaf = child:is_leaf()
  ]])

  local parent_is_leaf = child.lua_get("parent_is_leaf")
  local child_is_leaf = child.lua_get("child_is_leaf")

  h.eq(false, parent_is_leaf)
  h.eq(true, child_is_leaf)
end

T["TreeNode get_siblings returns correct siblings"] = function()
  child.lua([[
    parent = TreeNode:new("Parent")
    child1 = parent:add_child("Child 1")
    child2 = parent:add_child("Child 2")
    child3 = parent:add_child("Child 3")

    child1_siblings = child1:get_siblings()
    parent_siblings = parent:get_siblings()

    sibling_info = {
      child1_sibling_count = #child1_siblings,
      parent_sibling_count = #parent_siblings,
      sibling_contents = {}
    }

    for i, sibling in ipairs(child1_siblings) do
      sibling_info.sibling_contents[i] = sibling.content
    end
  ]])

  local sibling_info = child.lua_get("sibling_info")

  h.eq(2, sibling_info.child1_sibling_count)
  h.eq(0, sibling_info.parent_sibling_count) -- Root has no siblings
  h.expect_contains("Child 2", table.concat(sibling_info.sibling_contents, " "))
  h.expect_contains("Child 3", table.concat(sibling_info.sibling_contents, " "))
end

-- Test TreeOfThoughts class
T["TreeOfThoughts can be created with default problem"] = function()
  child.lua([[
    tot = TreeOfThoughts:new()
  ]])

  local tot = child.lua_get("tot")

  h.eq("table", type(tot.root))
  h.eq("Initial Problem", tot.root.content)
  h.eq("analysis", tot.root.type)
  h.expect_truthy(tot.evaluation_fn == nil or tot.evaluation_fn == vim.NIL)
end

T["TreeOfThoughts can be created with custom problem"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Custom problem statement")
  ]])

  local tot = child.lua_get("tot")

  h.eq("Custom problem statement", tot.root.content)
  h.eq("analysis", tot.root.type)
end

T["TreeOfThoughts add_typed_thought adds to root by default"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root problem")
    new_node, error_msg, suggestions = tot:add_typed_thought(nil, "First thought", "reasoning")

    result_info = {
      new_node_exists = new_node ~= nil,
      error_msg_is_nil = error_msg == nil,
      suggestions_count = suggestions and #suggestions or 0,
      new_node_content = new_node and new_node.content or nil,
      new_node_type = new_node and new_node.type or nil,
      root_children_count = #tot.root.children
    }
  ]])

  local result_info = child.lua_get("result_info")

  h.eq(true, result_info.new_node_exists)
  h.eq(true, result_info.error_msg_is_nil)
  h.expect_truthy(result_info.suggestions_count > 0)
  h.eq("First thought", result_info.new_node_content)
  h.eq("reasoning", result_info.new_node_type)
  h.eq(1, result_info.root_children_count)
end

T["TreeOfThoughts add_typed_thought adds to specific parent"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root problem")
    first_child, _, _ = tot:add_typed_thought(nil, "First child", "analysis")
    second_child, error_msg, suggestions = tot:add_typed_thought(first_child.id, "Second level", "task")

    result_info = {
      second_child_exists = second_child ~= nil,
      error_msg_is_nil = error_msg == nil,
      second_child_content = second_child and second_child.content or nil,
      second_child_type = second_child and second_child.type or nil,
      first_child_children_count = #first_child.children,
      second_child_depth = second_child and second_child.depth or nil
    }
  ]])

  local result_info = child.lua_get("result_info")

  h.eq(true, result_info.second_child_exists)
  h.eq(true, result_info.error_msg_is_nil)
  h.eq("Second level", result_info.second_child_content)
  h.eq("task", result_info.second_child_type)
  h.eq(1, result_info.first_child_children_count)
  h.eq(2, result_info.second_child_depth)
end

T["TreeOfThoughts add_typed_thought handles root parent_id"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root problem")
    new_node, error_msg, suggestions = tot:add_typed_thought("root", "Root child", "validation")

    result_info = {
      new_node_exists = new_node ~= nil,
      error_msg_is_nil = error_msg == nil,
      new_node_content = new_node and new_node.content or nil,
      root_children_count = #tot.root.children
    }
  ]])

  local result_info = child.lua_get("result_info")

  h.eq(true, result_info.new_node_exists)
  h.eq(true, result_info.error_msg_is_nil)
  h.eq("Root child", result_info.new_node_content)
  h.eq(1, result_info.root_children_count)
end

T["TreeOfThoughts add_typed_thought rejects invalid parent_id"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root problem")
    new_node, error_msg, suggestions = tot:add_typed_thought("nonexistent_id", "Orphan thought", "analysis")
  ]])

  local new_node = child.lua_get("new_node")
  local error_msg = child.lua_get("error_msg")
  local suggestions = child.lua_get("suggestions")

  h.expect_truthy(new_node == nil or new_node == vim.NIL)
  h.expect_contains("Parent node not found", error_msg)
  h.expect_truthy(suggestions == nil or suggestions == vim.NIL)
end

T["TreeOfThoughts add_typed_thought validates node types"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root problem")
    valid_node, valid_error, valid_suggestions = tot:add_typed_thought(nil, "Valid thought", "reasoning")
    invalid_node, invalid_error, invalid_suggestions = tot:add_typed_thought(nil, "Invalid thought", "invalid_type")

    validation_results = {
      valid_node_exists = valid_node ~= nil,
      valid_error_is_nil = valid_error == nil,
      invalid_node_is_nil = invalid_node == nil,
      invalid_error = invalid_error
    }
  ]])

  local validation_results = child.lua_get("validation_results")

  h.eq(true, validation_results.valid_node_exists)
  h.eq(true, validation_results.valid_error_is_nil)
  h.eq(true, validation_results.invalid_node_is_nil)
  h.expect_contains("Invalid node type", validation_results.invalid_error)
end

T["TreeOfThoughts add_typed_thought assigns scores"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root problem")
    new_node, _, _ = tot:add_typed_thought(nil, "Scored thought", "validation")

    score_info = {
      score_type = type(new_node.score),
      score_value = new_node.score
    }
  ]])

  local score_info = child.lua_get("score_info")

  h.eq("number", score_info.score_type)
  h.expect_truthy(score_info.score_value > 0)
end

T["TreeOfThoughts add_typed_thought returns suggestions"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root problem")
    new_node, _, suggestions = tot:add_typed_thought(nil, "Thought with suggestions", "analysis")
  ]])

  local suggestions = child.lua_get("suggestions")

  h.eq("table", type(suggestions))
  h.eq(4, #suggestions)
  h.expect_contains("Sub-questions", table.concat(suggestions, " "))
end

-- Test TreeOfThoughts find_node_by_id
T["TreeOfThoughts find_node_by_id finds root node"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root problem")
    found_node = tot:find_node_by_id(tot.root.id)
  ]])

  local found_node = child.lua_get("found_node")
  local tot = child.lua_get("tot")

  h.eq("table", type(found_node))
  h.eq(tot.root.id, found_node.id)
  h.eq("Root problem", found_node.content)
end

T["TreeOfThoughts find_node_by_id finds nested nodes"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root")
    level1, _, _ = tot:add_typed_thought(nil, "Level 1", "analysis")
    level2, _, _ = tot:add_typed_thought(level1.id, "Level 2", "reasoning")

    found_level1 = tot:find_node_by_id(level1.id)
    found_level2 = tot:find_node_by_id(level2.id)

    -- Extract data without circular references
    level1_info = {
      content = found_level1 and found_level1.content or nil,
      found = found_level1 ~= nil
    }
    level2_info = {
      content = found_level2 and found_level2.content or nil,
      found = found_level2 ~= nil
    }
  ]])

  local level1_info = child.lua_get("level1_info")
  local level2_info = child.lua_get("level2_info")

  h.eq(true, level1_info.found)
  h.eq("Level 1", level1_info.content)
  h.eq(true, level2_info.found)
  h.eq("Level 2", level2_info.content)
end

T["TreeOfThoughts find_node_by_id returns nil for non-existent id"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root")
    found_node = tot:find_node_by_id("nonexistent_id")
  ]])

  local found_node = child.lua_get("found_node")

  h.expect_truthy(found_node == nil or found_node == vim.NIL)
end

-- Test evaluation system
T["TreeOfThoughts evaluate_thought uses custom evaluation function"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root")

    -- Set custom evaluation function
    tot.evaluation_fn = function(node)
      return 42.0
    end

    node, _, _ = tot:add_typed_thought(nil, "Test thought", "analysis")

    -- Extract score without circular references
    node_score = node and node.score or nil
  ]])

  local node_score = child.lua_get("node_score")

  h.eq(42.0, node_score)
end

T["TreeOfThoughts evaluate_thought uses default scoring"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root")

    -- Test different content lengths
    short_node, _, _ = tot:add_typed_thought(nil, "Short", "analysis")
    medium_node, _, _ = tot:add_typed_thought(nil, string.rep("Medium content ", 5), "reasoning")
    long_node, _, _ = tot:add_typed_thought(nil, string.rep("Long content with lots of text ", 10), "validation")

    scores = {
      short = short_node.score,
      medium = medium_node.score,
      long = long_node.score
    }
  ]])

  local scores = child.lua_get("scores")

  h.eq("number", type(scores.short))
  h.eq("number", type(scores.medium))
  h.eq("number", type(scores.long))
  h.expect_truthy(scores.short > 0)
  h.expect_truthy(scores.medium > 0)
  h.expect_truthy(scores.long > 0)
end

T["TreeOfThoughts evaluate_thought considers depth penalty"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root")

    level1, _, _ = tot:add_typed_thought(nil, "Level 1 content", "analysis")
    level2, _, _ = tot:add_typed_thought(level1.id, "Level 2 content", "analysis")
    level3, _, _ = tot:add_typed_thought(level2.id, "Level 3 content", "analysis")

    scores = {
      level1 = level1.score,
      level2 = level2.score,
      level3 = level3.score
    }
  ]])

  local scores = child.lua_get("scores")

  -- Deeper nodes should generally have lower scores due to depth penalty
  h.expect_truthy(scores.level1 > scores.level2)
  h.expect_truthy(scores.level2 > scores.level3)
end

T["TreeOfThoughts evaluate_thought considers sibling diversity bonus"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root")

    -- Add first child (no siblings)
    first_child, _, _ = tot:add_typed_thought(nil, "First child", "analysis")
    first_score = first_child.score

    -- Add second child (first child now has 1 sibling)
    second_child, _, _ = tot:add_typed_thought(nil, "Second child", "analysis")

    -- Re-evaluate first child to see sibling bonus
    updated_first_score = tot:evaluate_thought(first_child)
  ]])

  local first_score = child.lua_get("first_score")
  local updated_first_score = child.lua_get("updated_first_score")

  h.expect_truthy(updated_first_score > first_score)
end

T["TreeOfThoughts evaluate_thought considers type bonuses"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root")

    -- Test different node types with same content
    analysis_node, _, _ = tot:add_typed_thought(nil, "Same content", "analysis")
    reasoning_node, _, _ = tot:add_typed_thought(nil, "Same content", "reasoning")
    task_node, _, _ = tot:add_typed_thought(nil, "Same content", "task")
    validation_node, _, _ = tot:add_typed_thought(nil, "Same content", "validation")

    type_scores = {
      analysis = analysis_node.score,
      reasoning = reasoning_node.score,
      task = task_node.score,
      validation = validation_node.score
    }

    -- Check relative ordering (accounting for randomness)
    score_comparisons = {
      validation_highest = type_scores.validation > type_scores.analysis and type_scores.validation > type_scores.task,
      reasoning_higher_than_analysis = type_scores.reasoning > type_scores.analysis,
      -- Don't enforce strict ordering due to random factors, just check that bonuses exist
      all_positive = type_scores.analysis > 0 and type_scores.reasoning > 0 and type_scores.task > 0 and type_scores.validation > 0
    }
  ]])

  local score_comparisons = child.lua_get("score_comparisons")

  -- Due to randomness in scoring, just check that validation gets bonus and all scores are positive
  h.eq(true, score_comparisons.validation_highest)
  h.eq(true, score_comparisons.all_positive)
end

T["TreeOfThoughts evaluate_thought ensures non-negative scores"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root")

    -- Create a deeply nested node that might have negative score
    current_node = tot.root
    for i = 1, 100 do
      new_node, _, _ = tot:add_typed_thought(current_node.id, "Deep node", "task")
      current_node = new_node
    end

    final_score = current_node.score
  ]])

  local final_score = child.lua_get("final_score")

  h.expect_truthy(final_score >= 0)
end

-- Test complex tree structures
T["TreeOfThoughts handles complex branching structure"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Complex problem")

    -- Create branching structure
    branch1, _, _ = tot:add_typed_thought(nil, "Branch 1", "analysis")
    branch2, _, _ = tot:add_typed_thought(nil, "Branch 2", "analysis")

    -- Add sub-branches
    sub1a, _, _ = tot:add_typed_thought(branch1.id, "Sub 1A", "reasoning")
    sub1b, _, _ = tot:add_typed_thought(branch1.id, "Sub 1B", "reasoning")
    sub2a, _, _ = tot:add_typed_thought(branch2.id, "Sub 2A", "task")

    -- Add deeper levels
    deep1, _, _ = tot:add_typed_thought(sub1a.id, "Deep 1", "validation")

    structure_info = {
      root_children = #tot.root.children,
      branch1_children = #branch1.children,
      branch2_children = #branch2.children,
      sub1a_children = #sub1a.children,
      deep1_depth = deep1.depth
    }
  ]])

  local structure_info = child.lua_get("structure_info")

  h.eq(2, structure_info.root_children)
  h.eq(2, structure_info.branch1_children)
  h.eq(1, structure_info.branch2_children)
  h.eq(1, structure_info.sub1a_children)
  h.eq(3, structure_info.deep1_depth)
end

T["TreeOfThoughts maintains correct parent-child relationships"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root")

    child1, _, _ = tot:add_typed_thought(nil, "Child 1", "analysis")
    grandchild, _, _ = tot:add_typed_thought(child1.id, "Grandchild", "reasoning")

    relationships = {
      child1_parent_is_root = child1.parent.id == tot.root.id,
      grandchild_parent_is_child1 = grandchild.parent.id == child1.id,
      root_has_child1 = false,
      child1_has_grandchild = false
    }

    -- Check if child1 is in root's children
    for _, child in ipairs(tot.root.children) do
      if child.id == child1.id then
        relationships.root_has_child1 = true
        break
      end
    end

    -- Check if grandchild is in child1's children
    for _, child in ipairs(child1.children) do
      if child.id == grandchild.id then
        relationships.child1_has_grandchild = true
        break
      end
    end
  ]])

  local relationships = child.lua_get("relationships")

  h.eq(true, relationships.child1_parent_is_root)
  h.eq(true, relationships.grandchild_parent_is_child1)
  h.eq(true, relationships.root_has_child1)
  h.eq(true, relationships.child1_has_grandchild)
end

-- Test edge cases and error handling
T["TreeOfThoughts handles empty content gracefully"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root")
    empty_node, error_msg, suggestions = tot:add_typed_thought(nil, "", "analysis")

    -- Extract data without circular references
    node_info = {
      exists = empty_node ~= nil,
      content = empty_node and empty_node.content or nil,
      error_is_nil = error_msg == nil
    }
  ]])

  local node_info = child.lua_get("node_info")

  h.eq(true, node_info.exists)
  h.eq("", node_info.content)
  h.eq(true, node_info.error_is_nil)
end

T["TreeOfThoughts handles nil content gracefully"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root")
    nil_node, error_msg, suggestions = tot:add_typed_thought(nil, nil, "analysis")

    -- Extract data without circular references
    node_info = {
      exists = nil_node ~= nil,
      content = nil_node and nil_node.content or nil,
      error_is_nil = error_msg == nil
    }
  ]])

  local node_info = child.lua_get("node_info")

  h.eq(true, node_info.exists)
  h.eq("", node_info.content) -- Should default to empty string
  h.eq(true, node_info.error_is_nil)
end

-- Test scoring consistency
T["TreeOfThoughts scoring includes random factor for tie-breaking"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root")

    -- Create multiple nodes with identical properties
    scores = {}
    for i = 1, 10 do
      node, _, _ = tot:add_typed_thought(nil, "Identical content", "reasoning")
      scores[i] = node.score
    end

    -- Check if scores vary (due to random factor)
    all_same = true
    first_score = scores[1]
    for i = 2, 10 do
      if scores[i] ~= first_score then
        all_same = false
        break
      end
    end

    scores_vary = not all_same
  ]])

  local scores_vary = child.lua_get("scores_vary")

  h.eq(true, scores_vary)
end

-- Test search functionality across tree
T["TreeOfThoughts find_node_by_id searches entire tree"] = function()
  child.lua([[
    tot = TreeOfThoughts:new("Root")

    -- Create complex tree structure
    branch1, _, _ = tot:add_typed_thought(nil, "Branch 1", "analysis")
    branch2, _, _ = tot:add_typed_thought(nil, "Branch 2", "analysis")
    deep_node, _, _ = tot:add_typed_thought(branch1.id, "Deep in branch 1", "task")
    deeper_node, _, _ = tot:add_typed_thought(deep_node.id, "Even deeper", "validation")

    -- Search for nodes at different levels
    found_root = tot:find_node_by_id(tot.root.id)
    found_branch2 = tot:find_node_by_id(branch2.id)
    found_deep = tot:find_node_by_id(deep_node.id)
    found_deeper = tot:find_node_by_id(deeper_node.id)

    search_results = {
      root_found = found_root ~= nil and found_root.content == "Root",
      branch2_found = found_branch2 ~= nil and found_branch2.content == "Branch 2",
      deep_found = found_deep ~= nil and found_deep.content == "Deep in branch 1",
      deeper_found = found_deeper ~= nil and found_deeper.content == "Even deeper"
    }
  ]])

  local search_results = child.lua_get("search_results")

  h.eq(true, search_results.root_found)
  h.eq(true, search_results.branch2_found)
  h.eq(true, search_results.deep_found)
  h.eq(true, search_results.deeper_found)
end

return T
