local betwixt = require("betwixt")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.opt.swapfile = false
vim.cmd("filetype plugin on")

local cases = {
  {
    body = "Should this accept missing values?",
    extension = "js",
    filetype = "javascript",
    leader = "//",
    source = {
      "function total(value) {",
      "  return value;",
      "}",
    },
  },
  {
    body = "Should this accept negative values?",
    extension = "py",
    filetype = "python",
    leader = "#",
    source = {
      "def total(value):",
      "    return value",
    },
  },
}

for _, case in ipairs(cases) do
  local source_name = "sample." .. case.extension
  local source_path = vim.fs.joinpath(temporary, source_name)
  local sidecar_path = vim.fs.joinpath(temporary, source_name .. ".review.betwixt.md")
  local sidecar = {
    "# Betwixt review",
    "",
    "file: " .. source_name,
    "",
    "## Comment",
    "",
    "range: 1-1",
    "author: human",
    "status: open",
    "type: question",
    "anchor:",
    "    " .. case.source[1],
    "body:",
    case.body,
  }

  assert(vim.fn.writefile(case.source, source_path) == 0)
  assert(vim.fn.writefile(sidecar, sidecar_path) == 0)
  vim.cmd.edit(vim.fn.fnameescape(source_path))
  local source_buffer = vim.api.nvim_get_current_buf()
  assert(vim.bo[source_buffer].filetype == case.filetype, source_name .. " should load its runtime filetype")

  betwixt.attach(sidecar_path)
  betwixt.interleave(source_buffer)
  local lines = vim.api.nvim_buf_get_lines(source_buffer, 0, -1, false)
  local header_row
  local body_row
  for index, line in ipairs(lines) do
    if line:find(case.leader .. " ╭─ betwixt", 1, true) == 1 then
      header_row = index
    elseif line == case.leader .. " " .. case.body then
      body_row = index
    end
  end
  assert(header_row ~= nil, source_name .. " should materialize its frame with " .. case.leader)
  assert(body_row ~= nil, source_name .. " should materialize its body with " .. case.leader)
  assert(lines[body_row + 1] == case.leader .. " ╰─ betwixt", source_name .. " should prefix the complete frame")

  local edited_body = "Edited " .. case.filetype .. " review."
  vim.api.nvim_buf_set_lines(source_buffer, body_row - 1, body_row, false, { case.leader .. " " .. edited_body })
  vim.cmd("write")
  assert(
    vim.deep_equal(vim.fn.readfile(source_path), case.source),
    source_name .. " must keep review lines out of source"
  )
  assert(
    table.concat(vim.fn.readfile(sidecar_path), "\n"):find(edited_body, 1, true) ~= nil,
    source_name .. " should persist its decoded review body"
  )

  betwixt.virtualize(source_buffer, false)
  betwixt.detach(source_buffer, false)
  vim.api.nvim_buf_delete(source_buffer, { force = true })
end

vim.fn.delete(temporary, "rf")
print("betwixt JavaScript and Python comment syntax: ok")
