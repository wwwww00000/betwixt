local config_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(config_path)))

vim.opt.runtimepath:prepend(root)

vim.schedule(function()
  require("betwixt").open(vim.fs.joinpath(root, "experiment", "review.betwixt.md"))
end)
