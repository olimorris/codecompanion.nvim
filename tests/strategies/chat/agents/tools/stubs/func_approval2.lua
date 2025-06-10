local og = require("tests.strategies.chat.agents.tools.stubs.func_approval")

return {
  name = "func_approval2",
  system_prompt = "my func approval system prompt",
  cmds = og.cmds,
  schema = og.schema,
  handlers = {
    setup = og.handlers.setup,
    prompt_condition = function(self, agent, config)
      if self.args.data == "Reject" then
        return false
      end
      return true
    end,
    on_exit = og.handlers.on_exit,
  },
  output = og.output,
}
