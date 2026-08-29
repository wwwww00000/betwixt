local betwixt = require("betwixt")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.opt.swapfile = false
vim.cmd("filetype plugin on")

local virtual_namespace = vim.api.nvim_get_namespaces()["betwixt-virtual"]
assert(virtual_namespace ~= nil, "the virtual comment namespace should exist")

local function indented(lines)
  local result = {}
  for _, line in ipairs(lines) do
    table.insert(result, "    " .. line)
  end
  return result
end

local function sidecar_lines(source, first, last)
  local lines = {
    "# Betwixt review",
    "",
    "file: sample.lua",
    "",
    "## Comment",
    "",
    string.format("range: %d-%d", first, last),
    "author: human",
    "status: open",
    "type: question",
    "anchor:",
  }
  vim.list_extend(lines, indented(vim.list_slice(source, first, last)))
  table.insert(lines, "context-before:")
  if first > 1 then
    table.insert(lines, "    " .. source[first - 1])
  end
  table.insert(lines, "context-after:")
  if last < #source then
    table.insert(lines, "    " .. source[last + 1])
  end
  vim.list_extend(lines, { "body:", "Review this code." })
  return lines
end

local function virtual_comment(buffer)
  local marks = vim.api.nvim_buf_get_extmarks(buffer, virtual_namespace, 0, -1, { details = true })
  assert(#marks == 1, "each anchoring case should render exactly one comment")
  local segments = marks[1][4].virt_lines[1]
  local text = {}
  for _, segment in ipairs(segments) do
    table.insert(text, segment[1])
  end
  return {
    header = table.concat(text),
    line = marks[1][2] + 1,
  }
end

local function replace_source(buffer, lines)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
end

local cases = {
  {
    name = "insert_above",
    source = {
      "local function total(value)",
      "  local subtotal = value",
      "  return subtotal",
      "end",
    },
    first = 2,
    last = 3,
    edited = {
      "-- reviewer added setup while the review was open",
      "local function total(value)",
      "  local subtotal = value",
      "  return subtotal",
      "end",
    },
    edit = function(buffer)
      vim.api.nvim_buf_set_lines(buffer, 0, 0, false, { "-- reviewer added setup while the review was open" })
    end,
    live_line = 4,
    expected = "moved to 3%-4",
  },
  {
    name = "delete_above",
    source = {
      "-- temporary module note",
      "local function total(value)",
      "  local subtotal = value",
      "  return subtotal",
      "end",
    },
    first = 3,
    last = 4,
    edited = {
      "local function total(value)",
      "  local subtotal = value",
      "  return subtotal",
      "end",
    },
    edit = function(buffer)
      vim.api.nvim_buf_set_lines(buffer, 0, 1, false, {})
    end,
    live_line = 3,
    expected = "moved to 2%-3",
  },
  {
    name = "reorder_duplicate_code",
    source = {
      "local function alpha()",
      "  return value",
      "end",
      "local function beta()",
      "  return value",
      "end",
    },
    first = 5,
    last = 5,
    edited = {
      "local function beta()",
      "  return value",
      "end",
      "local function alpha()",
      "  return value",
      "end",
    },
    expected = "moved to 2%-2",
  },
  {
    name = "change_context_around_unique_target",
    source = {
      "local function total()",
      "  return value",
      "end",
    },
    first = 2,
    last = 2,
    edited = {
      "-- renamed during review",
      "local function calculate()",
      "  return value",
      "end",
    },
    expected = "moved to 3%-3",
  },
  {
    name = "clone_complete_context",
    source = {
      "if primary then",
      "  return value",
      "end",
    },
    first = 2,
    last = 2,
    edited = {
      "if primary then",
      "  return value",
      "end",
      "if primary then",
      "  return value",
      "end",
    },
    expected = "ambiguous",
  },
  {
    name = "edit_target",
    source = {
      "local function total()",
      "  return value",
      "end",
    },
    first = 2,
    last = 2,
    edited = {
      "local function total()",
      "  return value or 0",
      "end",
    },
    expected = "stale",
  },
  {
    name = "delete_target",
    source = {
      "if ready then",
      "  run()",
      "end",
      "finish()",
    },
    first = 2,
    last = 2,
    edited = {
      "if ready then",
      "end",
      "finish()",
    },
    expected = "stale",
  },
}

for _, case in ipairs(cases) do
  local directory = vim.fs.joinpath(temporary, case.name)
  local source_path = vim.fs.joinpath(directory, "sample.lua")
  local sidecar_path = vim.fs.joinpath(directory, "review.betwixt.md")
  vim.fn.mkdir(directory, "p")
  assert(vim.fn.writefile(case.source, source_path) == 0)
  assert(vim.fn.writefile(sidecar_lines(case.source, case.first, case.last), sidecar_path) == 0)
  local stored_sidecar = vim.fn.readfile(sidecar_path)

  vim.cmd.edit(vim.fn.fnameescape(source_path))
  local source_buffer = vim.api.nvim_get_current_buf()
  betwixt.attach(sidecar_path)
  assert(virtual_comment(source_buffer).line == case.last, case.name .. " should begin at its stored range")

  if case.edit then
    case.edit(source_buffer)
  else
    replace_source(source_buffer, case.edited)
  end
  if case.live_line then
    assert(
      virtual_comment(source_buffer).line == case.live_line,
      case.name .. " should move its extmark immediately while the source is edited"
    )
  end
  vim.cmd("write")

  assert(vim.deep_equal(vim.fn.readfile(source_path), case.edited), case.name .. " should write the source edit")
  assert(
    vim.deep_equal(vim.fn.readfile(sidecar_path), stored_sidecar),
    case.name .. " should not migrate the durable range, anchor, or context"
  )
  local resolved = virtual_comment(source_buffer)
  assert(
    resolved.header:find(case.expected) ~= nil,
    string.format("%s should report %s, got %s", case.name, case.expected, resolved.header)
  )

  betwixt.detach(source_buffer, false)
  vim.api.nvim_buf_delete(source_buffer, { force = true })
end

vim.fn.delete(temporary, "rf")
print("betwixt code-review anchoring: ok")
