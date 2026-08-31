local root = vim.fn.getcwd()
local codediff_root = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy", "codediff.nvim")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.opt.swapfile = false
vim.cmd("filetype plugin on")

assert(vim.uv.fs_stat(codediff_root), "CodeDiff is not installed at " .. codediff_root)
vim.opt.runtimepath:prepend(codediff_root)
vim.opt.runtimepath:prepend(root)
vim.cmd("runtime plugin/codediff.lua")
require("codediff").setup({
  diff = {
    filler_text = "",
    jump_to_first_change = false,
    layout = "side-by-side",
  },
})

local function run(command)
  local result = vim.system(command, { cwd = temporary, text = true }):wait()
  assert(result.code == 0, table.concat(command, " ") .. ": " .. (result.stderr or ""))
  return result
end

local source_path = vim.fs.joinpath(temporary, "sample.lua")
local sidecar_path = vim.fs.joinpath(temporary, "review.betwixt.md")
local committed_source = {
  "local function total(value)",
  "  local subtotal = value",
  "  return subtotal",
  "end",
}
local working_source = vim.deepcopy(committed_source)
table.insert(working_source, 2, "-- reviewed commit addition above the anchor")
local sidecar = {
  "# Betwixt review",
  "",
  "file: sample.lua",
  "",
  "## Comment",
  "",
  "range: 2-3",
  "author: human",
  "status: open",
  "type: question",
  "anchor:",
  "      local subtotal = value",
  "      return subtotal",
  "body:",
  "Could this be clearer?",
  "",
  "### Reply",
  "",
  "author: agent",
  "body:",
  "The intermediate name could describe the unit.",
}

assert(vim.fn.writefile(committed_source, source_path) == 0)
assert(vim.fn.writefile(sidecar, sidecar_path) == 0)
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
assert(vim.fn.writefile(working_source, source_path) == 0)
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
local status = run({ "git", "status", "--porcelain" })
assert(vim.trim(status.stdout or "") == "", "the committed-review fixture should have a clean working tree")
local reviewed_diff = run({ "git", "diff", "HEAD~", "HEAD", "--", "sample.lua" })
assert(
  (reviewed_diff.stdout or ""):find("reviewed commit addition", 1, true),
  "the CodeDiff fixture should review the committed HEAD change"
)

vim.cmd.cd(temporary)
vim.cmd.edit(source_path)
local working_buffer = vim.api.nvim_get_current_buf()
local betwixt = require("betwixt")
betwixt.attach(sidecar_path, { buffer = working_buffer })
vim.cmd("CodeDiff file HEAD~")

local lifecycle = require("codediff.ui.lifecycle")
local aligned = vim.wait(5000, function()
  local tabpage = lifecycle.find_tabpage_by_buffer(working_buffer)
  if not tabpage then
    return false
  end
  local original_buffer = lifecycle.get_buffers(tabpage)
  local namespace = vim.api.nvim_get_namespaces()["betwixt-codediff-spacer"]
  return namespace
    and original_buffer
    and #vim.api.nvim_buf_get_extmarks(original_buffer, namespace, 0, -1, { details = true }) == 1
end, 20)
if not aligned then
  local debug_buffers = {}
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buffer) then
      table.insert(debug_buffers, {
        buffer = buffer,
        name = vim.api.nvim_buf_get_name(buffer),
        loaded = vim.api.nvim_buf_is_loaded(buffer),
      })
    end
  end
  error("Betwixt did not add a CodeDiff spacer: " .. vim.inspect({
    buffers = debug_buffers,
    session_tab = lifecycle.find_tabpage_by_buffer(working_buffer),
    working_buffer = working_buffer,
  }))
end

local tabpage = lifecycle.find_tabpage_by_buffer(working_buffer)
local original_buffer, modified_buffer = lifecycle.get_buffers(tabpage)
local original_window, modified_window = lifecycle.get_windows(tabpage)
assert(modified_buffer == working_buffer, "CodeDiff should use the ordinary working buffer as its modified side")
assert(vim.bo[modified_buffer].modifiable, "CodeDiff working side should remain editable")

local virtual_namespace = vim.api.nvim_get_namespaces()["betwixt-virtual"]
local spacer_namespace = vim.api.nvim_get_namespaces()["betwixt-codediff-spacer"]
local comments = vim.api.nvim_buf_get_extmarks(modified_buffer, virtual_namespace, 0, -1, { details = true })
local spacers = vim.api.nvim_buf_get_extmarks(original_buffer, spacer_namespace, 0, -1, { details = true })
assert(#comments == 1 and #spacers == 1, "the comment and its opposite spacer should both be present")
assert(comments[1][2] == 3, "the working-side anchor should move down by the inserted line")
assert(spacers[1][2] == 2, "the original-side spacer should use the committed anchor")
assert(#comments[1][4].virt_lines == 5, "the projected thread should occupy five virtual rows")
assert(#spacers[1][4].virt_lines == 5, "the opposite spacer should match the thread height")
for _, virtual_line in ipairs(spacers[1][4].virt_lines) do
  assert(virtual_line[1][2] == "BetwixtComment", "opposite spacer rows should use the comment background")
  assert(virtual_line[1][1]:match("^ +$"), "opposite spacer rows should remain visually blank")
end

local scroll_group = require("codediff.ui.scroll").get(tabpage)
assert(scroll_group, "CodeDiff scroll synchronization should be active")
local original_rows = scroll_group.ft[original_window].line_count + scroll_group.ft[original_window].total_fill
local modified_rows = scroll_group.ft[modified_window].line_count + scroll_group.ft[modified_window].total_fill
assert(original_rows == modified_rows, "CodeDiff virtual-row totals should remain aligned")
local scroll_internal = require("codediff.scrollsync")._internal
assert(
  scroll_internal.vrow_of_line(scroll_group.ft[original_window], 4)
    == scroll_internal.vrow_of_line(scroll_group.ft[modified_window], 5),
  "the first real lines after the projected comment should occupy the same virtual row"
)
vim.cmd("redraw")
assert(
  vim.fn.screenpos(original_window, 2, 1).row == vim.fn.screenpos(modified_window, 3, 1).row,
  "the anchored source lines should occupy the same visible screen row"
)
assert(
  vim.fn.screenpos(original_window, 4, 1).row == vim.fn.screenpos(modified_window, 5, 1).row,
  "the first source lines after the comment should occupy the same visible screen row"
)

local function spacer_count()
  local count = 0
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buffer) then
      count = count + #vim.api.nvim_buf_get_extmarks(buffer, spacer_namespace, 0, -1, { details = true })
    end
  end
  return count
end

local function press_toggle_key()
  local _, window = lifecycle.get_windows(tabpage)
  vim.api.nvim_set_current_win(window)
  vim.api.nvim_feedkeys("t", "mx", false)
end

press_toggle_key()
assert(
  vim.wait(5000, function()
    local session = lifecycle.get_session(tabpage)
    return session and session.layout == "inline" and session.stored_diff_result and spacer_count() == 0
  end, 20),
  "inline CodeDiff should remove the opposite spacer"
)
press_toggle_key()
assert(
  vim.wait(5000, function()
    local session = lifecycle.get_session(tabpage)
    if not session or session.layout ~= "side-by-side" or not session.stored_diff_result then
      return false
    end
    local round_trip_original = lifecycle.get_buffers(tabpage)
    return #vim.api.nvim_buf_get_extmarks(round_trip_original, spacer_namespace, 0, -1, { details = true }) == 1
  end, 20),
  "side-by-side CodeDiff should restore the opposite spacer after a layout round trip"
)
original_buffer, modified_buffer = lifecycle.get_buffers(tabpage)
original_window, modified_window = lifecycle.get_windows(tabpage)

vim.api.nvim_win_set_cursor(modified_window, { 3, 0 })
betwixt.interleave(working_buffer)
assert(
  #vim.api.nvim_buf_get_extmarks(original_buffer, spacer_namespace, 0, -1, { details = true }) == 0,
  "interleaved editing should remove the virtual opposite spacer"
)
local materialized_lines = vim.api.nvim_buf_get_lines(working_buffer, 0, -1, false)
assert(
  vim.tbl_contains(materialized_lines, "-- Could this be clearer?"),
  "CodeDiff's editable working pane should contain the materialized review body"
)
assert(
  vim.tbl_contains(materialized_lines, "-- The intermediate name could describe the unit."),
  "CodeDiff's editable working pane should contain the materialized reply"
)
assert(
  vim.tbl_contains(materialized_lines, "-- ╰─ betwixt"),
  "CodeDiff's editable working pane should contain the complete materialized frame"
)
assert(
  vim.deep_equal(vim.fn.readfile(source_path), working_source),
  "materializing inside CodeDiff must remain an in-buffer view until :write"
)
betwixt.virtualize(working_buffer, false)
assert(
  #vim.api.nvim_buf_get_extmarks(original_buffer, spacer_namespace, 0, -1, { details = true }) == 1,
  "returning to virtual mode should restore CodeDiff alignment"
)

local stale_sidecar = vim.deepcopy(sidecar)
stale_sidecar[12] = "    missing anchor line one"
stale_sidecar[13] = "    missing anchor line two"
assert(vim.fn.writefile(stale_sidecar, sidecar_path) == 0)
vim.api.nvim_buf_call(working_buffer, function()
  vim.cmd("BetwixtRefresh")
end)
assert(
  #vim.api.nvim_buf_get_extmarks(original_buffer, spacer_namespace, 0, -1, { details = true }) == 0,
  "a stale anchor should not acquire a speculative opposite spacer"
)

betwixt.detach(working_buffer, true)
assert(
  #vim.api.nvim_buf_get_extmarks(original_buffer, spacer_namespace, 0, -1, { details = true }) == 0,
  "detaching Betwixt should remove its opposite spacer"
)

vim.cmd("CodeDiff quit")
vim.cmd.cd(root)
vim.fn.delete(temporary, "rf")

print("betwixt CodeDiff alignment: ok")
