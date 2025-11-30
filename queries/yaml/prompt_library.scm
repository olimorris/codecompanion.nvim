(document
  (block_node
    (block_mapping
      (block_mapping_pair
        key: (flow_node
          (plain_scalar
            (string_scalar) @cc_top_key))
        value: (flow_node) @cc_top_value))))

(document
  (block_node
    (block_mapping
      (block_mapping_pair
        key: (flow_node
          (plain_scalar
            (string_scalar) @cc_nested_parent_key))
        value: (block_node
          (block_mapping
            (block_mapping_pair
              key: (flow_node
                (plain_scalar
                  (string_scalar) @cc_nested_key))
              value: (_) @cc_nested_value)))))))

