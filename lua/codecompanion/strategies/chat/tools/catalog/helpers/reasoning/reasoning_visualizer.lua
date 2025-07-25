--=============================================================================
-- Reasoning Visualizer - ASCII visualization for reasoning structures
--=============================================================================

local fmt = string.format

---@class CodeCompanion.ReasoningVisualizer
local ReasoningVisualizer = {}

---@class VisualizationConfig
---@field show_scores boolean Show node scores
---@field show_timestamps boolean Show creation/update times
---@field show_metadata boolean Show additional metadata
---@field max_content_length number Maximum content length per node
---@field indent_size number Spaces for indentation
---@field use_unicode boolean Use Unicode box-drawing characters

local CONFIG = {
  max_content_length = 60,
  indent_size = 2,
}

-- Box drawing characters
local BOX_CHARS = {
  unicode = {
    horizontal = "─",
    vertical = "│",
    corner = "┌",
    tee = "├",
    end_tee = "└",
    cross = "┼",
    down_right = "┌",
    down_left = "┐",
    up_right = "└",
    up_left = "┘",
    down_horizontal = "┬",
    up_horizontal = "┴",
    vertical_right = "├",
    vertical_left = "┤",
  },
}

---Truncate content to specified length
---@param content string
---@param max_length number
---@return string
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

---Format node metadata
---@param node table
---@return string
local function format_node_info(node)
  local parts = {}

  if node.state then
    table.insert(parts, fmt("State: %s", node.state))
  end

  return #parts > 0 and fmt(" (%s)", table.concat(parts, ", ")) or ""
end

---Visualize Chain of Thoughts
---@param chain table Chain of Thoughts instance
---@return string
function ReasoningVisualizer.visualize_chain(chain)
  local lines = {}

  table.insert(lines, fmt("# %s", chain.problem or "Unknown"))
  table.insert(lines, "")

  if not chain.steps or #chain.steps == 0 then
    table.insert(lines, "No steps in chain")
    return table.concat(lines, "\n")
  end

  for i, step in ipairs(chain.steps) do
    local is_last = i == #chain.steps
    local connector = is_last and BOX_CHARS.unicode.up_right or BOX_CHARS.unicode.vertical_right
    local line_char = is_last and " " or BOX_CHARS.unicode.vertical

    local content = truncate_content(step.content, CONFIG.max_content_length)
    local step_info = ""

    table.insert(lines, fmt("%s%s Step %d: %s%s", connector, BOX_CHARS.unicode.horizontal, i, content, step_info))

    if step.reasoning then
      local reasoning = truncate_content(step.reasoning, CONFIG.max_content_length - 10)
      table.insert(lines, fmt("%s    Reasoning: %s", line_char, reasoning))
    end

    if i < #chain.steps then
      table.insert(lines, fmt("%s", BOX_CHARS.unicode.vertical))
    end
  end

  return table.concat(lines, "\n")
end

---Visualize Tree of Thoughts
---@param root_node table Tree root node
---@return string
function ReasoningVisualizer.visualize_tree(root_node)
  local lines = {}

  table.insert(lines, "# Tree of Thoughts")
  table.insert(lines, "")

  ---Recursively build tree visualization
  ---@param node table
  ---@param prefix string
  ---@param is_last boolean
  local function build_tree_lines(node, prefix, is_last)
    local content = truncate_content(node.content, CONFIG.max_content_length)
    local node_info = format_node_info(node)

    local connector = is_last and BOX_CHARS.unicode.up_right or BOX_CHARS.unicode.vertical_right
    table.insert(lines, fmt("%s%s%s %s%s", prefix, connector, BOX_CHARS.unicode.horizontal, content, node_info))

    if node.children and #node.children > 0 then
      local new_prefix = prefix .. (is_last and "  " or (BOX_CHARS.unicode.vertical .. " "))

      for i, child in ipairs(node.children) do
        build_tree_lines(child, new_prefix, i == #node.children)
      end
    end
  end

  -- Start with root node
  local content = truncate_content(root_node.content, CONFIG.max_content_length)
  local node_info = format_node_info(root_node)
  table.insert(lines, fmt("Root: %s%s", content, node_info))

  if root_node.children and #root_node.children > 0 then
    for i, child in ipairs(root_node.children) do
      build_tree_lines(child, "", i == #root_node.children)
    end
  end

  return table.concat(lines, "\n")
end

---Visualize Graph of Thoughts
---@param graph table Graph of Thoughts instance
---@return string
function ReasoningVisualizer.visualize_graph(graph)
  local lines = {}

  table.insert(lines, "# Graph of Thoughts")
  table.insert(lines, "")

  if not graph.nodes or vim.tbl_count(graph.nodes) == 0 then
    table.insert(lines, "No nodes in graph")
    return table.concat(lines, "\n")
  end

  -- Build node list sorted by creation time or dependency order
  local sorted_nodes = {}
  for id, node in pairs(graph.nodes) do
    table.insert(sorted_nodes, { id = id, node = node })
  end
  table.sort(sorted_nodes, function(a, b)
    return (a.node.created_at or 0) < (b.node.created_at or 0)
  end)

  table.insert(lines, "## Nodes:")
  for _, entry in ipairs(sorted_nodes) do
    local node = entry.node
    local content = truncate_content(node.content, CONFIG.max_content_length)
    local node_info = format_node_info(node)

    table.insert(lines, fmt("  %s [%s]: %s%s", BOX_CHARS.unicode.corner, entry.id, content, node_info))
  end

  -- Show dependencies
  table.insert(lines, "")
  table.insert(lines, "## Dependencies:")

  local has_dependencies = false
  for source_id, targets in pairs(graph.edges or {}) do
    if vim.tbl_count(targets) > 0 then
      has_dependencies = true
      local source_content = graph.nodes[source_id] and truncate_content(graph.nodes[source_id].content, 20)
        or source_id

      for target_id, edge in pairs(targets) do
        local target_content = graph.nodes[target_id] and truncate_content(graph.nodes[target_id].content, 20)
          or target_id

        local weight_info = edge.weight and edge.weight ~= 1.0 and fmt(" (weight: %.2f)", edge.weight) or ""

        table.insert(lines, fmt("  %s → %s%s", source_content, target_content, weight_info))
      end
    end
  end

  if not has_dependencies then
    table.insert(lines, "  No dependencies defined")
  end

  return table.concat(lines, "\n")
end

return ReasoningVisualizer
