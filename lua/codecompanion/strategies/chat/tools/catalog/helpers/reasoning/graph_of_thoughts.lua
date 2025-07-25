-- Graph of Thoughts Reasoning System in Lua

-- Node types for categorizing thoughts
local NODE_TYPES = {
  analysis = "Analysis and exploration of the problem",
  reasoning = "Logical deduction and inference",
  task = "Actionable implementation step",
  validation = "Verification and testing",
  synthesis = "Combining multiple thoughts or ideas",
}

local function generate_id()
  return tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
end

-- ThoughtNode Class
local Node = {}
Node.__index = Node

function Node.new(content, id, node_type)
  local self = setmetatable({}, Node)
  self.id = id or generate_id()
  self.content = content or ""
  self.type = node_type or "analysis"
  self.score = 0.0
  self.confidence = 0.0
  self.created_at = os.time()
  self.updated_at = os.time()
  return self
end

function Node:set_score(score, confidence)
  self.score = score or self.score
  self.confidence = confidence or self.confidence
  self.updated_at = os.time()
end

function Node:generate_suggestions()
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

    synthesis = function(content)
      return {
        "🧩 **Integration**: How do the component ideas fit together in this synthesis?",
        "⚖️ **Trade-offs**: What are the pros and cons of combining these concepts?",
        "🔄 **Refinement**: How can this synthesis be improved or optimized?",
        "🎯 **Applications**: Where and how can this synthesized idea be applied?",
      }
    end,
  }

  local generator = generators[self.type]
  if generator then
    return generator(self.content)
  end

  return { "💡 **Next steps**: Consider what logical follow-ups make sense for this thought" }
end

-- Edge Class
local Edge = {}
Edge.__index = Edge

function Edge.new(source_id, target_id, weight, relationship_type)
  local self = setmetatable({}, Edge)
  self.source = source_id
  self.target = target_id
  self.weight = weight or 1.0
  self.type = relationship_type or "depends_on"
  self.created_at = os.time()
  return self
end

-- GraphOfThoughts Class
local GraphOfThoughts = {}
GraphOfThoughts.__index = GraphOfThoughts

function GraphOfThoughts.new()
  local self = setmetatable({}, GraphOfThoughts)
  self.nodes = {} -- id -> ThoughtNode
  self.edges = {} -- source_id -> {target_id -> Edge}
  self.reverse_edges = {} -- target_id -> {source_id -> Edge}
  return self
end

-- Node Management
function GraphOfThoughts:add_node(content, id, node_type)
  -- Validate node type
  if node_type and not NODE_TYPES[node_type] then
    local valid_types = {}
    for type_name, _ in pairs(NODE_TYPES) do
      table.insert(valid_types, type_name)
    end
    return nil, "Invalid node type: " .. tostring(node_type) .. ". Valid types: " .. table.concat(valid_types, ", ")
  end

  local node = Node.new(content, id, node_type)
  self.nodes[node.id] = node
  self.edges[node.id] = {}
  self.reverse_edges[node.id] = {}
  return node.id
end

function GraphOfThoughts:get_node(node_id)
  return self.nodes[node_id]
end

-- Edge Management
function GraphOfThoughts:add_edge(source_id, target_id, weight, relationship_type)
  if not self.nodes[source_id] or not self.nodes[target_id] then
    return false, "Source or target node does not exist"
  end

  -- Prevent self-loops
  if source_id == target_id then
    return false, "Self-loops are not allowed"
  end

  local edge = Edge.new(source_id, target_id, weight, relationship_type)

  -- Add to adjacency lists
  self.edges[source_id][target_id] = edge
  self.reverse_edges[target_id][source_id] = edge

  return true
end

-- Cycle Detection
function GraphOfThoughts:has_cycle()
  local visited = {}
  local rec_stack = {}

  for node_id, _ in pairs(self.nodes) do
    visited[node_id] = false
    rec_stack[node_id] = false
  end

  local function dfs_cycle_check(node_id)
    visited[node_id] = true
    rec_stack[node_id] = true

    for target_id, _ in pairs(self.edges[node_id]) do
      if not visited[target_id] then
        if dfs_cycle_check(target_id) then
          return true
        end
      elseif rec_stack[target_id] then
        return true
      end
    end

    rec_stack[node_id] = false
    return false
  end

  for node_id, _ in pairs(self.nodes) do
    if not visited[node_id] then
      if dfs_cycle_check(node_id) then
        return true
      end
    end
  end

  return false
end

-- Topological Sort
function GraphOfThoughts:topological_sort()
  local in_degree = {}
  local queue = {}
  local result = {}

  -- Initialize in-degrees to 0
  for node_id, _ in pairs(self.nodes) do
    in_degree[node_id] = 0
  end

  -- Calculate in-degrees from reverse edges
  for node_id, sources in pairs(self.reverse_edges) do
    in_degree[node_id] = 0
    for _, _ in pairs(sources) do
      in_degree[node_id] = in_degree[node_id] + 1
    end
  end

  -- Find nodes with no dependencies
  for node_id, degree in pairs(in_degree) do
    if degree == 0 then
      table.insert(queue, node_id)
    end
  end

  -- Process queue
  while #queue > 0 do
    local current = table.remove(queue, 1)
    table.insert(result, current)

    -- Update dependents
    for target_id, _ in pairs(self.edges[current]) do
      in_degree[target_id] = in_degree[target_id] - 1
      if in_degree[target_id] == 0 then
        table.insert(queue, target_id)
      end
    end
  end

  -- Check if all nodes are included (no cycles)
  if #result ~= self:get_node_count() then
    return nil, "Graph contains cycles"
  end

  return result
end

-- Evaluation System

function GraphOfThoughts:propagate_scores(node_id)
  local node = self.nodes[node_id]
  if not node then
    return
  end

  -- Simple score propagation: weighted average of dependency scores
  for dependent_id, _ in pairs(self.edges[node_id] or {}) do
    local dependent = self.nodes[dependent_id]
    if dependent then
      -- Update dependent's score based on this node's completion
      local influence = 0.3 -- configurable influence factor
      dependent.score = dependent.score + (node.score * influence)
    end
  end
end

-- Utility Functions
function GraphOfThoughts:get_node_count()
  local count = 0
  for _ in pairs(self.nodes) do
    count = count + 1
  end
  return count
end

function GraphOfThoughts:get_stats()
  local stats = {
    total_nodes = self:get_node_count(),
    total_edges = 0,
  }

  for _, edges in pairs(self.edges) do
    for _ in pairs(edges) do
      stats.total_edges = stats.total_edges + 1
    end
  end

  return stats
end

-- Serialization
function GraphOfThoughts:serialize()
  local data = {
    nodes = {},
    edges = {},
  }

  for node_id, node in pairs(self.nodes) do
    data.nodes[node_id] = {
      id = node.id,
      content = node.content,
      score = node.score,
      confidence = node.confidence,
      created_at = node.created_at,
      updated_at = node.updated_at,
    }
  end

  for _, targets in pairs(self.edges) do
    for _, edge in pairs(targets) do
      table.insert(data.edges, {
        source = edge.source,
        target = edge.target,
        weight = edge.weight,
        type = edge.type,
        created_at = edge.created_at,
      })
    end
  end

  return data
end

function GraphOfThoughts:deserialize(data)
  self.nodes = {}
  self.edges = {}
  self.reverse_edges = {}

  -- Recreate nodes
  for node_id, node_data in pairs(data.nodes) do
    local node = Node.new(node_data.content, node_data.id)
    node.score = node_data.score
    node.confidence = node_data.confidence
    node.created_at = node_data.created_at
    node.updated_at = node_data.updated_at

    self.nodes[node_id] = node
    self.edges[node_id] = {}
    self.reverse_edges[node_id] = {}
  end

  -- Recreate edges
  for _, edge_data in ipairs(data.edges) do
    self:add_edge(edge_data.source, edge_data.target, edge_data.weight, edge_data.type)
  end
end

-- Node Merging System
function GraphOfThoughts:merge_nodes(source_node_ids, merged_content, merged_id)
  -- Validate all source nodes exist
  for _, node_id in ipairs(source_node_ids) do
    if not self.nodes[node_id] then
      return false, string.format("Source node '%s' does not exist", node_id)
    end
  end

  -- Create the merged node
  local merged_node = Node.new(merged_content, merged_id)

  -- Calculate merged score based on source nodes
  local total_score = 0
  local total_confidence = 0
  for _, node_id in ipairs(source_node_ids) do
    local source_node = self.nodes[node_id]
    total_score = total_score + source_node.score
    total_confidence = total_confidence + source_node.confidence
  end

  merged_node:set_score(total_score / #source_node_ids, total_confidence / #source_node_ids)

  -- Add merged node to graph
  self.nodes[merged_node.id] = merged_node
  self.edges[merged_node.id] = {}
  self.reverse_edges[merged_node.id] = {}

  -- Create edges from all source nodes to the merged node
  for _, source_id in ipairs(source_node_ids) do
    self:add_edge(source_id, merged_node.id, 1.0, "contributes_to")
  end

  return true, merged_node.id
end

return {
  ThoughtNode = Node,
  Edge = Edge,
  GraphOfThoughts = GraphOfThoughts,
}
