local config_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(config_path)))
local fixture = vim.fn.tempname()
local source = vim.fs.joinpath(fixture, "sample.lua")
local sidecar = vim.fs.joinpath(fixture, "review.betwixt.md")

vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false
vim.cmd("filetype plugin on")

if vim.fn.exists(":CodeDiff") == 0 then
  error("Betwixt CodeDiff experiment requires the :CodeDiff command")
end

vim.fn.mkdir(fixture, "p")
assert(vim.fn.writefile(vim.fn.readfile(vim.fs.joinpath(root, "experiment", "codediff_before.lua")), source) == 0)
assert(vim.fn.writefile(vim.fn.readfile(vim.fs.joinpath(root, "experiment", "review.betwixt.md")), sidecar) == 0)

local function run(command)
  local result = vim.system(command, { cwd = fixture, text = true }):wait()
  if result.code ~= 0 then
    error(table.concat(command, " ") .. ": " .. (result.stderr or ""))
  end
end

run({ "git", "init", "-q" })
run({ "git", "add", "sample.lua", "review.betwixt.md" })
run({
  "git",
  "-c",
  "user.name=Betwixt",
  "-c",
  "user.email=betwixt@example.invalid",
  "commit",
  "-qm",
  "fixture",
})
assert(vim.fn.writefile(vim.fn.readfile(vim.fs.joinpath(root, "experiment", "codediff_after.lua")), source) == 0)
run({ "git", "add", "sample.lua" })
run({
  "git",
  "-c",
  "user.name=Betwixt",
  "-c",
  "user.email=betwixt@example.invalid",
  "commit",
  "-qm",
  "reviewed change",
})
vim.g.betwixt_codediff_fixture = fixture

vim.cmd.cd(fixture)
vim.cmd.edit(source)
require("betwixt").attach(sidecar)

vim.schedule(function()
  vim.notify("Betwixt CodeDiff fixture: " .. fixture, vim.log.levels.INFO)
  vim.cmd("CodeDiff file HEAD~")
end)
