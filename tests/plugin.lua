vim.cmd("runtime plugin/betwixt.lua")

assert(vim.g.loaded_betwixt, "the runtime plugin should set its load guard")
assert(vim.fn.exists(":BetwixtAttach") == 2, "the runtime plugin should define :BetwixtAttach")
assert(vim.fn.exists(":BetwixtComment") == 2, "the runtime plugin should define :BetwixtComment")
assert(vim.fn.exists(":BetwixtReply") == 2, "the runtime plugin should define :BetwixtReply")
assert(vim.fn.exists(":BetwixtOpen") == 2, "the runtime plugin should define :BetwixtOpen")

vim.cmd("runtime plugin/betwixt.lua")
assert(vim.fn.exists(":BetwixtAttach") == 2, "loading the runtime plugin twice should be harmless")

local betwixt = require("betwixt")
assert(betwixt.setup({ author = "reviewer" }) == betwixt, "setup should return the plugin module")
assert(not pcall(betwixt.setup, { mappings = "disabled" }), "setup should reject a non-table mappings option")
assert(not pcall(betwixt.setup, { mappings = { comment = "" } }), "setup should reject an empty mapping")
assert(not pcall(betwixt.setup, { mappings = { typo = "<leader>x" } }), "setup should reject an unknown mapping name")
assert(
  betwixt.setup({ mappings = { comment = false, edit = false } }) == betwixt,
  "setup should allow either default mapping to be disabled"
)

print("betwixt plugin runtime: ok")
