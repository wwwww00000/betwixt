vim.cmd("runtime plugin/betwixt.lua")
local betwixt = require("betwixt")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.opt.swapfile = false
betwixt.setup({ author = "reviewer" })
vim.cmd("filetype plugin on")

local source_path = vim.fs.joinpath(temporary, "notes.md")
local sidecar_path = source_path .. ".betwixt.md"
local source = {
  "# Notes",
  "",
  "This paragraph needs review.",
  "",
  "- One item",
}
assert(vim.fn.writefile(source, source_path) == 0)
vim.cmd.edit(vim.fn.fnameescape(source_path))
local source_buffer = vim.api.nvim_get_current_buf()
assert(vim.bo[source_buffer].filetype == "markdown", "the fixture should load the Markdown filetype")
assert(vim.bo[source_buffer].commentstring == "<!-- %s -->", "the test expects Neovim's paired Markdown comment")

local function buffer_lines()
  return vim.api.nvim_buf_get_lines(source_buffer, 0, -1, false)
end

local function find_line(expected)
  for index, line in ipairs(buffer_lines()) do
    if line == expected then
      return index
    end
  end
  error("missing line: " .. expected)
end

local function sidecar_text()
  return table.concat(vim.fn.readfile(sidecar_path), "\n")
end

vim.cmd("3BetwixtComment question")
local header = find_line("╭─ betwixt · reviewer · open · question · notes.md:3-3")
assert(buffer_lines()[header - 1] == "<!--", "the opening delimiter should have its own protected line")
assert(buffer_lines()[header + 1] == "", "a paired comment should leave its empty body prefix-free")
assert(buffer_lines()[header + 2] == "╰─ betwixt", "paired syntax should not offset the frame footer")
assert(buffer_lines()[header + 3] == "-->", "the closing delimiter should have its own protected line")
assert(vim.api.nvim_win_get_cursor(0)[1] == header + 1, "creation should target the prefix-free body")
assert(vim.api.nvim_win_get_cursor(0)[2] == 0, "paired comment editing should begin in column zero")

vim.api.nvim_buf_set_lines(source_buffer, header, header + 1, false, {
  "Could this be more direct?",
  "",
  "The rendered document should not include this review.",
})
vim.cmd("write")
assert(vim.deep_equal(vim.fn.readfile(source_path), source), "Markdown review text must stay out of the source")
local written = sidecar_text()
assert(
  written:find("body:\nCould this be more direct%?\n\nThe rendered document should not include this review%."),
  "the prefix-free multiline body should persist in the sidecar"
)

betwixt.virtualize(source_buffer, false)
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.cmd("BetwixtReply")
local reply_header = find_line("├─ reply · reviewer")
assert(buffer_lines()[reply_header + 1] == "", "a paired reply should also have a prefix-free body")
vim.api.nvim_buf_set_lines(source_buffer, reply_header, reply_header + 1, false, { "Agreed; I would shorten it." })
vim.cmd("write")
assert(vim.deep_equal(vim.fn.readfile(source_path), source), "a Markdown reply must stay out of the source")
written = sidecar_text()
assert(written:find("author: reviewer\nbody:\nAgreed; I would shorten it%."), "the Markdown reply should persist")

betwixt.virtualize(source_buffer, false)
vim.api.nvim_win_set_cursor(0, { 5, 0 })
vim.cmd("BetwixtComment")
local second_header = find_line("╭─ betwixt · reviewer · open · comment · notes.md:5-5")
assert(buffer_lines()[second_header - 1] == "<!--", "a later thread should retain its opening boundary")
assert(buffer_lines()[second_header + 3] == "-->", "a later thread should retain its closing boundary")
vim.api.nvim_buf_set_lines(source_buffer, second_header, second_header + 1, false, { "Should this item be expanded?" })
vim.cmd("write")
assert(vim.deep_equal(vim.fn.readfile(source_path), source), "multiple Markdown threads must stay out of the source")
assert(sidecar_text():find("Should this item be expanded%?"), "a later paired thread should persist")

local safe_body = find_line("Could this be more direct?")
vim.api.nvim_buf_set_lines(source_buffer, safe_body - 1, safe_body, false, { "Could this include --> literally?" })
local source_before_rejected_write = vim.fn.readfile(source_path)
local sidecar_before_rejected_write = vim.fn.readfile(sidecar_path)
local wrote, write_error = pcall(vim.cmd, "write")
assert(not wrote, "a closing delimiter in review text should reject the write")
assert(
  tostring(write_error):find("paired%-comment review text must not contain its closing delimiter"),
  "the rejected write should explain the delimiter hazard"
)
assert(
  vim.deep_equal(vim.fn.readfile(source_path), source_before_rejected_write),
  "a rejected write must not touch source"
)
assert(
  vim.deep_equal(vim.fn.readfile(sidecar_path), sidecar_before_rejected_write),
  "a rejected write must not touch the sidecar"
)
assert(vim.bo[source_buffer].modified, "the rejected review edit should remain editable")

betwixt.virtualize(source_buffer, true)
assert(vim.deep_equal(buffer_lines(), source), "discarding the rejected edit should restore pure Markdown")
betwixt.detach(source_buffer, false)
vim.fn.delete(temporary, "rf")
print("betwixt Markdown paired comments: ok")
