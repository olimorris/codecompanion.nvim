local TreeNode = {}
TreeNode.__index = TreeNode

-- Node types matching Chain of Thought
local NODE_TYPES = {
  analysis = "Analysis and exploration of the problem",
  reasoning = "Logical deduction and inference",
  task = "Actionable implementation step",
  validation = "Verification and testing",
}

function TreeNode:new(content, node_type, parent, depth)
  local node = {
    id = string.format("node_%d_%d", os.time(), math.random(1000, 9999)),
    content = content or "",
    type = node_type or "analysis", -- Use 'type' field like Chain of Thought
    parent = parent,
    children = {},
    depth = depth or 0,
    score = 0,
    created_at = os.time(),
  }
  setmetatable(node, TreeNode)
  return node
end

function TreeNode:add_child(content, node_type)
  -- Validate node type
  if node_type and not NODE_TYPES[node_type] then
    return nil,
      "Invalid node type: " .. tostring(node_type) .. ". Valid types: " .. table.concat(vim.tbl_keys(NODE_TYPES), ", ")
  end

  local child = TreeNode:new(content, node_type, self, self.depth + 1)
  table.insert(self.children, child)
  return child
end

-- Generate suggestions based on node type
function TreeNode:generate_suggestions()
  local generators = {
    analysis = function(content)
      return {
        "🔍 **Sub-questions**: What are the key components of: " .. content .. "?",
        "🤔 **Assumptions**: What assumptions are being made about this analysis?",
        "📊 **Data needed**: What information or data would help validate this analysis?",
        "🔗 **Related cases**: Are there similar problems that have been analyzed before?",
      }
    end,

    reasoning = function(content)
      return {
        "➡️ **Implications**: If this reasoning is correct, what are the logical consequences?",
        "🛡️ **Supporting evidence**: What facts or data support this line of reasoning?",
        "⚡ **Counter-arguments**: What are potential weaknesses or alternative viewpoints?",
        "🎯 **Next steps**: How can this reasoning lead to actionable conclusions?",
      }
    end,

    task = function(content)
      return {
        "📋 **Implementation steps**: Break this task into specific, actionable sub-steps",
        "🔄 **Alternative approaches**: Consider different ways to accomplish this task",
        "🛠️ **Resources needed**: What tools, time, or materials are required?",
        "✅ **Success criteria**: How will you know when this task is completed successfully?",
      }
    end,

    validation = function(content)
      return {
        "🎯 **Test cases**: What specific scenarios should be tested?",
        "📏 **Success metrics**: What measurable criteria define success?",
        "⚠️ **Edge cases**: What unusual or boundary conditions might cause issues?",
        "🔧 **Failure recovery**: What should happen if validation fails?",
      }
    end,
  }

  local generator = generators[self.type]
  if generator then
    return generator(self.content)
  end

  return { "💡 **Next steps**: Consider what logical follow-ups make sense for this thought" }
end

function TreeNode:get_path()
  local path = {}
  local current = self
  while current do
    table.insert(path, 1, current)
    current = current.parent
  end
  return path
end

function TreeNode:is_leaf()
  return #self.children == 0
end

function TreeNode:get_siblings()
  if not self.parent then
    return {}
  end
  local siblings = {}
  for _, child in ipairs(self.parent.children) do
    if child.id ~= self.id then
      table.insert(siblings, child)
    end
  end
  return siblings
end

-- TreeOfThoughts: Main reasoning system manager
local TreeOfThoughts = {}
TreeOfThoughts.__index = TreeOfThoughts

function TreeOfThoughts:new(initial_problem)
  local tot = {
    root = TreeNode:new(initial_problem or "Initial Problem", "analysis"),
    evaluation_fn = nil,
  }
  setmetatable(tot, TreeOfThoughts)
  return tot
end

-- Add thought with type and return suggestions
function TreeOfThoughts:add_typed_thought(parent_id, content, node_type)
  local parent_node = self.root

  -- Find parent node if specified
  if parent_id and parent_id ~= "root" then
    parent_node = self:find_node_by_id(parent_id)
    if not parent_node then
      return nil, "Parent node not found: " .. parent_id
    end
  end

  -- Add the new node
  local new_node, error_msg = parent_node:add_child(content, node_type)
  if not new_node then
    return nil, error_msg
  end

  -- Score the new node
  new_node.score = self:evaluate_thought(new_node)

  -- Generate suggestions based on type
  local suggestions = new_node:generate_suggestions()

  return new_node, nil, suggestions
end

-- Find node by ID (helper method)
function TreeOfThoughts:find_node_by_id(id)
  local function search(node)
    if node.id == id then
      return node
    end
    for _, child in ipairs(node.children) do
      local found = search(child)
      if found then
        return found
      end
    end
    return nil
  end
  return search(self.root)
end

-- Evaluation system for thoughts and paths
function TreeOfThoughts:evaluate_thought(node)
  if self.evaluation_fn then
    return self.evaluation_fn(node)
  end

  local score = 3.0 -- Base score

  -- Content quality scoring
  local content_len = #node.content
  if content_len > 100 then
    score = score + 1.0
  elseif content_len > 50 then
    score = score + 0.5
  end

  score = score - (node.depth * 0.1)

  -- Path diversity bonus
  local siblings = node:get_siblings()
  if #siblings > 0 then
    score = score + (#siblings * 0.1)
  end

  -- Type-based scoring bonus
  local type_bonuses = {
    analysis = 0.2,
    reasoning = 0.3,
    task = 0.1,
    validation = 0.4, -- Higher bonus for validation
  }
  score = score + (type_bonuses[node.type] or 0)

  -- Add small random factor for tie-breaking
  score = score + (math.random() * 0.1)

  return math.max(0, score) -- Ensure non-negative
end

return {
  TreeNode = TreeNode,
  TreeOfThoughts = TreeOfThoughts,
}
