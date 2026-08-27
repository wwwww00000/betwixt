local config_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(config_path)))
local lazy_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")
local plenary_root = vim.fs.joinpath(lazy_root, "plenary.nvim")
local diffview_root = vim.fs.joinpath(lazy_root, "diffview.nvim")
local fixture = vim.fn.tempname()
local source = vim.fs.joinpath(fixture, "sample.lua")
local sidecar = vim.fs.joinpath(fixture, "review.betwixt.md")

for _, path in ipairs({ plenary_root, diffview_root }) do
  if not vim.uv.fs_stat(path) then
    error("Betwixt Diffview experiment requires " .. path)
  end
  vim.opt.runtimepath:prepend(path)
end
vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false
vim.cmd("filetype plugin on")

vim.fn.mkdir(fixture, "p")
assert(vim.fn.writefile(vim.fn.readfile(vim.fs.joinpath(root, "experiment", "sample.lua")), source) == 0)
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
local working_source = vim.fn.readfile(source)
table.insert(working_source, 1, "-- working-tree addition above Betwixt anchors")
assert(vim.fn.writefile(working_source, source) == 0)
vim.g.betwixt_diffview_fixture = fixture

if vim.fn.exists(":DiffviewOpen") == 0 then
  vim.cmd("runtime plugin/diffview.lua")
end
vim.api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
  callback = function(event)
    if
      vim.fs.normalize(vim.api.nvim_buf_get_name(event.buf)) == vim.fs.normalize(source)
      and not vim.b[event.buf].betwixt_fixture_attached
    then
      require("betwixt").attach(sidecar, { buffer = event.buf })
      vim.b[event.buf].betwixt_fixture_attached = true
    end
  end,
})

vim.schedule(function()
  vim.cmd.cd(fixture)
  vim.notify("Betwixt Diffview fixture: " .. fixture, vim.log.levels.INFO)
  vim.cmd("DiffviewOpen HEAD -- sample.lua")
end)
