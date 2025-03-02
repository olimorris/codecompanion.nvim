local queue = { {
    cmds = { <function 1>, <function 2> },
    handlers = {
      on_exit = <function 3>,
      setup = <function 4>
    },
    name = "func_queue",
    output = {
      success = <function 5>
    },
    request = {
      _attr = {
        name = "func_queue"
      },
      action = {
        _attr = {
          type = "type1"
        },
        data = "Data 1"
      }
    },
    system_prompt = <function 6>
  }, {
    cmds = { { "sleep", "0.5" } },
    handlers = {
      on_exit = <function 7>,
      setup = <function 8>
    },
    name = "cmd_queue",
    output = {
      success = <function 9>
    },
    request = {
      _attr = {
        name = "cmd_queue"
      }
    },
    system_prompt = <function 10>
  }, {
    cmds = { <function 11> },
    handlers = {
      on_exit = <function 12>,
      setup = <function 13>
    },
    name = "func_queue_2",
    output = {
      success = <function 14>
    },
    request = {
      _attr = {
        name = "func_queue_2"
      },
      action = {
        _attr = {
          type = "type1"
        },
        data = "Data 2"
      }
    },
    system_prompt = <function 15>
  },
  head = 0,
  tail = 3,
  <metatable> = {
    __index = {
      contents = <function 16>,
      count = <function 17>,
      is_empty = <function 18>,
      pop = <function 19>,
      push = <function 20>
    }
  }
}
