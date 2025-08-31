---@class ACP.promptCapabilities
---@field audio boolean
---@field embeddedContext boolean
---@field image boolean

---@class ACP.agentCapabilities
---@field loadSession boolean
---@field promptCapabilities ACP.promptCapabilities

---@class ACP.AuthMethod
---@field id string
---@field name string
---@field description? string|nil

---@alias ACP.authMethods ACP.AuthMethod[]
