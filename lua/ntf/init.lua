-- Public test API. Specs pull what they need explicitly:
--   local ntf = require("ntf")
--   local describe, it = ntf.describe, ntf.it
local tree = require("ntf.core.tree")

local M = {}

M.describe = tree.describe
M.it = tree.it
M.pending = tree.pending
M.before_each = tree.before_each
M.after_each = tree.after_each
M.setup = tree.setup
M.teardown = tree.teardown
M.finally = tree.finally
M.assert = tree.assert

return M
