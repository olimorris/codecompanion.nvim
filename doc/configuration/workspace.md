# Configuring the Workspace File

Workspaces act as a context management system for your project. This context sits in a `codecompanion-workspace.json` file in the root of the current working directory. For the purposes of this guide, the file will be referred to as the _workspace file_.

You can customize the name and location of the workspace file by setting the `workspace_file` configuration option. For example:

```lua
require('codecompanion').setup({
  workspace_file = '.ai/workspace.json' -- relative to cwd
})
```

To learn more about the workspace file, please see the [Creating Workspaces](/extending/workspace) guide.
