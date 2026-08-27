local config_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(config_path)))
local source = vim.fs.joinpath(root, "experiment", "sample.lua")
local sidecar = vim.fs.joinpath(root, "experiment", "review.betwixt.md")

vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false
vim.cmd("filetype plugin on")

vim.schedule(function()
  vim.cmd.edit(vim.fn.fnameescape(source))
  require("betwixt").attach(sidecar)
end)
