local M = {}

local namespace = vim.api.nvim_create_namespace("betwixt")
local virtual_namespace = vim.api.nvim_create_namespace("betwixt-virtual")
local interleaved_namespace = vim.api.nvim_create_namespace("betwixt-interleaved")
local codediff_spacer_namespace = vim.api.nvim_create_namespace("betwixt-codediff-spacer")
local sessions = {}
local attachments = {}
local defaults = {
  author = nil,
  mappings = {
    comment = "<leader>rc",
    edit = "<leader>re",
  },
}
local settings = vim.deepcopy(defaults)

local function fail(message, ...)
  error("Betwixt: " .. string.format(message, ...), 0)
end

local function read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    fail("could not read %s", path)
  end
  return lines
end

local function path_exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

local function absolute(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function set_default_highlights()
  local highlight
  local resolved_highlight
  if vim.o.background == "light" then
    highlight = { bg = "#F3DFB3", fg = "#5B3A00" }
    resolved_highlight = { bg = "#E2E2E2", fg = "#666666" }
  else
    highlight = { bg = "#4A3418", fg = "#F2D49B" }
    resolved_highlight = { bg = "#303030", fg = "#A0A0A0" }
  end
  highlight.default = true
  resolved_highlight.default = true
  vim.api.nvim_set_hl(0, "BetwixtComment", highlight)
  vim.api.nvim_set_hl(0, "BetwixtResolvedComment", resolved_highlight)
end

local function comment_highlight(comment)
  return comment.status == "resolved" and "BetwixtResolvedComment" or "BetwixtComment"
end

local function trim_trailing_blank_lines(lines)
  while lines[#lines] == "" do
    table.remove(lines)
  end
end

local function finish_reply(reply, path)
  if not reply then
    return
  end

  trim_trailing_blank_lines(reply.body)
  if reply.author == nil or reply.author == "" then
    fail("reply is missing author in %s", path)
  end
  if not reply.saw_body then
    fail("reply is missing body in %s", path)
  end
end

local function finish_comment(comment, path)
  if not comment then
    return
  end

  trim_trailing_blank_lines(comment.body)

  for _, field in ipairs({ "first", "last", "author", "status", "type" }) do
    if comment[field] == nil or comment[field] == "" then
      fail("comment is missing %s in %s", field, path)
    end
  end
  if not comment.saw_anchor or not comment.saw_body then
    fail("comment is missing anchor or body in %s", path)
  end
  if comment.first > comment.last then
    fail("comment range %d-%d is reversed in %s", comment.first, comment.last, path)
  end
  if #comment.anchor ~= comment.last - comment.first + 1 then
    fail("comment range %d-%d has %d anchor lines in %s", comment.first, comment.last, #comment.anchor, path)
  end
end

local function parse_sidecar(lines, path)
  local review = { comments = {} }
  local comment
  local reply
  local mode = "preamble"

  for line_number, line in ipairs(lines) do
    if line == "## Comment" then
      finish_reply(reply, path)
      reply = nil
      finish_comment(comment, path)
      comment = { anchor = {}, body = {}, replies = {} }
      table.insert(review.comments, comment)
      mode = "metadata"
    elseif line == "### Reply" then
      if not comment or not comment.saw_body or (mode ~= "body" and mode ~= "reply_body") then
        fail("reply on line %d must follow a comment body in %s", line_number, path)
      end
      finish_reply(reply, path)
      reply = { body = {} }
      table.insert(comment.replies, reply)
      mode = "reply_metadata"
    elseif not comment then
      local file = line:match("^file:%s*(.-)%s*$")
      if file and file ~= "" then
        review.file = file
      end
    elseif mode == "anchor" then
      if line == "context-before:" then
        comment.context_before = {}
        mode = "context_before"
      elseif line == "context-after:" then
        comment.context_after = {}
        mode = "context_after"
      elseif line == "body:" then
        comment.saw_body = true
        mode = "body"
      else
        local anchor_line = line:match("^    (.*)$")
        if anchor_line == nil then
          fail("anchor line %d must be indented by four spaces in %s", line_number, path)
        end
        table.insert(comment.anchor, anchor_line)
      end
    elseif mode == "context_before" then
      if line == "context-after:" then
        comment.context_after = {}
        mode = "context_after"
      elseif line == "body:" then
        comment.saw_body = true
        mode = "body"
      else
        local context_line = line:match("^    (.*)$")
        if context_line == nil then
          fail("context-before line %d must be indented by four spaces in %s", line_number, path)
        end
        table.insert(comment.context_before, context_line)
      end
    elseif mode == "context_after" then
      if line == "body:" then
        comment.saw_body = true
        mode = "body"
      else
        local context_line = line:match("^    (.*)$")
        if context_line == nil then
          fail("context-after line %d must be indented by four spaces in %s", line_number, path)
        end
        table.insert(comment.context_after, context_line)
      end
    elseif mode == "body" then
      table.insert(comment.body, line)
    elseif mode == "reply_body" then
      table.insert(reply.body, line)
    elseif mode == "reply_metadata" then
      if line == "body:" then
        reply.saw_body = true
        mode = "reply_body"
      elseif line ~= "" then
        local author = line:match("^author:%s*(.-)%s*$")
        if not author then
          fail("unrecognized reply metadata on line %d in %s", line_number, path)
        end
        reply.author = author
      end
    elseif line == "anchor:" then
      comment.saw_anchor = true
      mode = "anchor"
    elseif line ~= "" then
      local first, last = line:match("^range:%s*(%d+)%-(%d+)%s*$")
      if first then
        comment.first = tonumber(first)
        comment.last = tonumber(last)
      else
        local key, value = line:match("^(author):%s*(.-)%s*$")
        if not key then
          key, value = line:match("^(status):%s*(.-)%s*$")
        end
        if not key then
          key, value = line:match("^(type):%s*(.-)%s*$")
        end
        if not key then
          fail("unrecognized metadata on line %d in %s", line_number, path)
        end
        comment[key] = value
      end
    end
  end

  finish_reply(reply, path)
  finish_comment(comment, path)

  if not review.file then
    fail("missing file field in %s", path)
  end
  if #review.comments == 0 then
    fail("no comments found in %s", path)
  end

  return review
end

local function serialize_sidecar(review)
  local lines = { "# Betwixt review", "", "file: " .. review.file, "" }

  for _, comment in ipairs(review.comments) do
    vim.list_extend(lines, {
      "## Comment",
      "",
      string.format("range: %d-%d", comment.first, comment.last),
      "author: " .. comment.author,
      "status: " .. comment.status,
      "type: " .. comment.type,
      "anchor:",
    })
    for _, anchor_line in ipairs(comment.anchor) do
      table.insert(lines, "    " .. anchor_line)
    end
    if comment.context_before ~= nil then
      table.insert(lines, "context-before:")
      for _, context_line in ipairs(comment.context_before) do
        table.insert(lines, "    " .. context_line)
      end
    end
    if comment.context_after ~= nil then
      table.insert(lines, "context-after:")
      for _, context_line in ipairs(comment.context_after) do
        table.insert(lines, "    " .. context_line)
      end
    end
    table.insert(lines, "body:")
    vim.list_extend(lines, comment.body)
    for _, comment_reply in ipairs(comment.replies or {}) do
      vim.list_extend(lines, {
        "",
        "### Reply",
        "",
        "author: " .. comment_reply.author,
        "body:",
      })
      vim.list_extend(lines, comment_reply.body)
    end
    table.insert(lines, "")
  end

  return lines
end

local function slice_matches(source, first, anchor)
  if first < 1 or first + #anchor - 1 > #source then
    return false
  end
  for offset, anchor_line in ipairs(anchor) do
    if source[first + offset - 1] ~= anchor_line then
      return false
    end
  end
  return true
end

local function context_matches(source, first, comment)
  if comment.context_before ~= nil then
    if #comment.context_before == 0 then
      if first ~= 1 then
        return false
      end
    elseif not slice_matches(source, first - #comment.context_before, comment.context_before) then
      return false
    end
  end

  if comment.context_after ~= nil then
    local last = first + #comment.anchor - 1
    if #comment.context_after == 0 then
      if last ~= #source then
        return false
      end
    elseif not slice_matches(source, last + 1, comment.context_after) then
      return false
    end
  end

  return true
end

local function resolve_anchor(source, comment)
  local has_context = comment.context_before ~= nil or comment.context_after ~= nil
  if not has_context and slice_matches(source, comment.first, comment.anchor) then
    return { first = comment.first, last = comment.last, state = "current" }
  end

  local matches = {}
  local contextual_matches = {}
  for first = 1, #source - #comment.anchor + 1 do
    if slice_matches(source, first, comment.anchor) then
      table.insert(matches, first)
      if has_context and context_matches(source, first, comment) then
        table.insert(contextual_matches, first)
      end
    end
  end

  local resolved_first
  if #contextual_matches == 1 then
    resolved_first = contextual_matches[1]
  elseif #matches == 1 then
    resolved_first = matches[1]
  end

  if resolved_first then
    return {
      first = resolved_first,
      last = resolved_first + #comment.anchor - 1,
      state = resolved_first == comment.first and "current" or "moved",
    }
  end

  local fallback_first
  local fallback_last
  if #source == 0 then
    fallback_first, fallback_last = 1, 0
  else
    fallback_first = math.max(1, math.min(comment.first, #source))
    fallback_last = math.max(fallback_first, math.min(comment.last, #source))
  end

  return {
    first = fallback_first,
    last = fallback_last,
    state = #matches == 0 and "stale" or "ambiguous",
  }
end

local function metadata_value(name, value)
  value = vim.trim(tostring(value or ""))
  if value == "" then
    fail("%s must not be empty", name)
  end
  if value:find("[\r\n]") then
    fail("%s must fit on one line", name)
  end
  if value:find(" · ", 1, true) then
    fail("%s must not contain the Betwixt field separator", name)
  end
  return value
end

local function comment_header(review, comment, resolved)
  local target = string.format("%s:%d-%d", review.file, comment.first, comment.last)
  local anchor_state = ""
  if resolved.state == "moved" then
    anchor_state = string.format(" · moved to %d-%d", resolved.first, resolved.last)
  elseif resolved.state ~= "current" then
    anchor_state = " · " .. resolved.state
  end

  return string.format(
    "╭─ betwixt · %s · %s · %s · %s%s",
    comment.author,
    comment.status,
    comment.type,
    target,
    anchor_state
  )
end

local function metadata_from_header(review, comment, resolved, header)
  local author, status, comment_type = header:match("^╭─ betwixt · (.-) · (.-) · (.-) · .+$")
  if not author then
    fail("comment header must retain the Betwixt metadata shape")
  end

  local edited = vim.deepcopy(comment)
  edited.author = metadata_value("author", author)
  edited.status = metadata_value("status", status)
  edited.type = metadata_value("type", comment_type)
  if header ~= comment_header(review, edited, resolved) then
    fail("only comment author, status, and type are editable in the header")
  end
  return edited.author, edited.status, edited.type
end

local function reply_header(reply)
  return "├─ reply · " .. reply.author
end

local function author_from_reply_header(reply, header)
  local author = header:match("^├─ reply · (.+)$")
  if not author then
    fail("reply header must retain the Betwixt reply shape")
  end
  author = metadata_value("reply author", author)
  local edited = vim.deepcopy(reply)
  edited.author = author
  if header ~= reply_header(edited) then
    fail("only reply authors are editable in reply headers")
  end
  return author
end

local function line_slice(lines, first, last)
  if first > last then
    return {}
  end
  return vim.list_slice(lines, first, last)
end

local function collect_thread(comment, content)
  local replies = comment.replies or {}
  if #replies == 0 then
    comment.body = content
    trim_trailing_blank_lines(comment.body)
    return
  end

  local reply_rows = {}
  for index, line in ipairs(content) do
    if line:match("^├─ reply · ") then
      table.insert(reply_rows, index)
    end
  end
  if #reply_rows ~= #replies then
    fail("reply separators are not editable; expected %d but found %d", #replies, #reply_rows)
  end

  comment.body = line_slice(content, 1, reply_rows[1] - 1)
  trim_trailing_blank_lines(comment.body)
  for index, comment_reply in ipairs(replies) do
    local start_row = reply_rows[index]
    local end_row = (reply_rows[index + 1] or (#content + 1)) - 1
    comment_reply.author = author_from_reply_header(comment_reply, content[start_row])
    comment_reply.body = line_slice(content, start_row + 1, end_row)
    trim_trailing_blank_lines(comment_reply.body)
  end
end

local function render(review, source, placement)
  local groups = {}

  for index, comment in ipairs(review.comments) do
    local resolved = resolve_anchor(source, comment)
    local boundary
    if placement == "before" then
      boundary = resolved.first - 1
    else
      boundary = resolved.last
    end
    boundary = math.max(0, math.min(boundary, #source))
    groups[boundary] = groups[boundary] or {}
    table.insert(groups[boundary], {
      comment = comment,
      comment_index = index,
      resolved = resolved,
    })
  end

  local output = {}
  local blocks = {}
  for boundary = 0, #source do
    if boundary > 0 then
      table.insert(output, source[boundary])
    end
    for _, item in ipairs(groups[boundary] or {}) do
      local header = comment_header(review, item.comment, item.resolved)
      local footer = "╰─ betwixt"
      local start_row = #output
      table.insert(output, header)
      vim.list_extend(output, item.comment.body)
      local reply_blocks = {}
      for reply_index, comment_reply in ipairs(item.comment.replies or {}) do
        local reply_start_row = #output
        local rendered_reply_header = reply_header(comment_reply)
        table.insert(output, rendered_reply_header)
        vim.list_extend(output, comment_reply.body)
        table.insert(reply_blocks, {
          end_row = #output,
          header = rendered_reply_header,
          reply_index = reply_index,
          start_row = reply_start_row,
        })
      end
      table.insert(output, footer)
      table.insert(blocks, {
        comment_index = item.comment_index,
        header = header,
        highlight_group = comment_highlight(item.comment),
        footer = footer,
        replies = reply_blocks,
        resolved = item.resolved,
        start_row = start_row,
        end_row = #output,
      })
    end
  end

  return output, blocks
end

local function set_buffer_options(buffer, source_path)
  vim.bo[buffer].buftype = "acwrite"
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].swapfile = false
  vim.bo[buffer].modifiable = true
  vim.bo[buffer].filetype = vim.filetype.match({ filename = source_path }) or ""
end

local function render_into_buffer(buffer, session)
  local lines, blocks = render(session.review, session.source_lines, session.placement)

  vim.bo[buffer].modifiable = true
  local undo_levels = vim.bo[buffer].undolevels
  vim.bo[buffer].undolevels = -1
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].undolevels = undo_levels
  vim.api.nvim_buf_clear_namespace(buffer, namespace, 0, -1)

  for _, block in ipairs(blocks) do
    block.mark = vim.api.nvim_buf_set_extmark(buffer, namespace, block.start_row, 0, {
      end_row = block.end_row,
      end_col = 0,
      end_right_gravity = true,
      hl_eol = true,
      hl_group = block.highlight_group,
      priority = 200,
      right_gravity = false,
    })
  end

  session.blocks = blocks
  vim.bo[buffer].modified = false

  if blocks[1] then
    local body_row = math.min(blocks[1].start_row + 2, blocks[1].end_row)
    vim.api.nvim_win_set_cursor(0, { body_row, 0 })
  end
end

local function extmark_regions(buffer, session)
  local regions = {}
  for _, block in ipairs(session.blocks) do
    local position = vim.api.nvim_buf_get_extmark_by_id(buffer, namespace, block.mark, { details = true })
    if #position == 0 or position[3].end_row == nil then
      fail("a projected comment boundary was deleted; reload the view")
    end
    table.insert(regions, {
      block = block,
      start_row = position[1],
      end_row = position[3].end_row,
    })
  end
  table.sort(regions, function(left, right)
    return left.start_row < right.start_row
  end)
  return regions
end

local function collect_edits(buffer, session)
  local lines = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
  local regions = extmark_regions(buffer, session)
  local source = {}
  local cursor = 1

  for _, region in ipairs(regions) do
    if region.start_row < cursor - 1 or region.end_row <= region.start_row then
      fail("projected comment sections overlap; reload the view")
    end

    for index = cursor, region.start_row do
      table.insert(source, lines[index])
    end

    local header = lines[region.start_row + 1]
    local footer = lines[region.end_row]
    if footer ~= region.block.footer then
      fail("comment boundaries are not editable; undo or reload the view")
    end

    local comment = session.review.comments[region.block.comment_index]
    comment.author, comment.status, comment.type =
      metadata_from_header(session.review, comment, region.block.resolved, header)
    local content = {}
    for index = region.start_row + 2, region.end_row - 1 do
      table.insert(content, lines[index])
    end
    collect_thread(comment, content)
    cursor = region.end_row + 1
  end

  for index = cursor, #lines do
    table.insert(source, lines[index])
  end

  return source
end

local function write_projection(buffer)
  local session = sessions[buffer]
  if not session then
    fail("no session for buffer")
  end

  local projected_source = collect_edits(buffer, session)
  if not vim.deep_equal(read_lines(session.source_path), session.source_lines) then
    fail("source changed on disk; use :BetwixtReload before writing")
  end
  if not vim.deep_equal(read_lines(session.sidecar_path), session.sidecar_lines) then
    fail("sidecar changed on disk; use :BetwixtReload before writing")
  end

  local sidecar_lines = serialize_sidecar(session.review)
  local source_changed = not vim.deep_equal(projected_source, session.source_lines)
  local sidecar_changed = not vim.deep_equal(sidecar_lines, session.sidecar_lines)
  local written = {}

  if source_changed then
    if vim.fn.writefile(projected_source, session.source_path) ~= 0 then
      fail("could not write %s", session.source_path)
    end
    table.insert(written, session.source_path)
  end

  if sidecar_changed then
    if vim.fn.writefile(sidecar_lines, session.sidecar_path) ~= 0 then
      if source_changed and vim.fn.writefile(session.source_lines, session.source_path) ~= 0 then
        fail("could not write %s and could not restore %s", session.sidecar_path, session.source_path)
      end
      fail("could not write %s; source was not changed", session.sidecar_path)
    end
    table.insert(written, session.sidecar_path)
  end

  session.source_lines = projected_source
  session.sidecar_lines = sidecar_lines
  vim.bo[buffer].modified = false
  if #written == 0 then
    vim.notify("No changes to write", vim.log.levels.INFO)
  else
    vim.notify("Wrote " .. table.concat(written, " and "), vim.log.levels.INFO)
  end
end

local function reload(buffer, force)
  local session = sessions[buffer]
  if not session then
    fail("no session for buffer")
  end
  if vim.bo[buffer].modified and not force then
    fail("buffer has unsaved comment edits; use :BetwixtReload! to discard them")
  end

  local sidecar_lines = read_lines(session.sidecar_path)
  local review = parse_sidecar(sidecar_lines, session.sidecar_path)
  local source_path = absolute(vim.fs.joinpath(vim.fs.dirname(session.sidecar_path), review.file))

  session.review = review
  session.sidecar_lines = sidecar_lines
  session.source_path = source_path
  session.source_lines = read_lines(source_path)
  set_buffer_options(buffer, source_path)
  render_into_buffer(buffer, session)
end

local function source_buffer_lines(buffer)
  return vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
end

local render_virtual_comments
local clear_codediff_spacers
local schedule_codediff_alignment

local function replace_buffer_lines(buffer, lines)
  local undo_levels = vim.bo[buffer].undolevels
  vim.bo[buffer].undolevels = -1
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].undolevels = undo_levels
end

local function line_comment_leader(buffer)
  local commentstring = vim.bo[buffer].commentstring
  local before, after = commentstring:match("^(.-)%%s(.-)$")
  if not before then
    fail("buffer has no usable 'commentstring'")
  end

  before = before:gsub("%s+$", "")
  after = after:gsub("^%s+", "")
  if before == "" or after ~= "" then
    fail("interleaved editing currently requires a line-comment 'commentstring', got %q", commentstring)
  end
  return before
end

local function encode_comment_line(leader, text)
  if text == "" then
    return leader .. " "
  end
  return leader .. " " .. text
end

local function decode_comment_line(leader, line)
  if line == leader then
    return ""
  end
  local prefix = leader .. " "
  if line:sub(1, #prefix) ~= prefix then
    fail("every interleaved comment line must begin with %q", prefix)
  end
  return line:sub(#prefix + 1)
end

local function mark_interleaved_blocks(attachment, blocks)
  local buffer = attachment.source_buffer
  vim.api.nvim_buf_clear_namespace(buffer, interleaved_namespace, 0, -1)
  for _, block in ipairs(blocks) do
    block.mark = vim.api.nvim_buf_set_extmark(buffer, interleaved_namespace, block.start_row, 0, {
      end_row = block.end_row,
      end_col = 0,
      end_right_gravity = true,
      hl_eol = true,
      hl_group = block.highlight_group,
      priority = 200,
      right_gravity = false,
    })
  end
end

local function render_interleaved(attachment, source, preserve_undo)
  local buffer = attachment.source_buffer
  local state = attachment.interleaved
  local display_review = vim.deepcopy(attachment.review)
  for _, comment in ipairs(display_review.comments) do
    if #comment.body == 0 then
      comment.body = { "" }
    end
    for _, comment_reply in ipairs(comment.replies or {}) do
      if #comment_reply.body == 0 then
        comment_reply.body = { "" }
      end
    end
  end
  local lines, blocks = render(display_review, source, attachment.placement)

  for _, block in ipairs(blocks) do
    for index = block.start_row + 1, block.end_row do
      lines[index] = encode_comment_line(state.leader, lines[index])
    end
    block.header = lines[block.start_row + 1]
    block.footer = lines[block.end_row]
  end

  clear_codediff_spacers(attachment, true)
  if not vim.deep_equal(source_buffer_lines(buffer), lines) then
    if preserve_undo then
      vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    else
      replace_buffer_lines(buffer, lines)
    end
  end
  vim.api.nvim_buf_clear_namespace(buffer, virtual_namespace, 0, -1)
  mark_interleaved_blocks(attachment, blocks)
  state.blocks = blocks
  vim.bo[buffer].modified = false
end

local function interleaved_regions(attachment)
  local regions = {}
  for _, block in ipairs(attachment.interleaved.blocks) do
    local position = vim.api.nvim_buf_get_extmark_by_id(
      attachment.source_buffer,
      interleaved_namespace,
      block.mark,
      { details = true }
    )
    if #position == 0 or position[3].end_row == nil then
      fail("an interleaved comment boundary was deleted; undo the edit or leave with :BetwixtVirtual!")
    end
    table.insert(regions, {
      block = block,
      start_row = position[1],
      end_row = position[3].end_row,
    })
  end
  table.sort(regions, function(left, right)
    return left.start_row < right.start_row
  end)
  return regions
end

local function collect_interleaved(attachment)
  local lines = source_buffer_lines(attachment.source_buffer)
  local regions = interleaved_regions(attachment)
  local review = vim.deepcopy(attachment.review)
  local source = {}
  local cursor = 1

  for _, region in ipairs(regions) do
    if region.start_row < cursor - 1 or region.end_row <= region.start_row then
      fail("interleaved comment sections overlap; leave with :BetwixtVirtual! to discard the edit")
    end

    for index = cursor, region.start_row do
      table.insert(source, lines[index])
    end

    local header = lines[region.start_row + 1]
    local footer = lines[region.end_row]
    if footer ~= region.block.footer then
      fail("interleaved comment boundaries are not editable")
    end

    local comment = review.comments[region.block.comment_index]
    local decoded_header = decode_comment_line(attachment.interleaved.leader, header)
    comment.author, comment.status, comment.type =
      metadata_from_header(review, comment, region.block.resolved, decoded_header)
    local content = {}
    for index = region.start_row + 2, region.end_row - 1 do
      table.insert(content, decode_comment_line(attachment.interleaved.leader, lines[index]))
    end
    collect_thread(comment, content)
    cursor = region.end_row + 1
  end

  for index = cursor, #lines do
    table.insert(source, lines[index])
  end

  return source, review
end

local install_interleaved_write

local function sidecar_is_unchanged(attachment)
  if attachment.sidecar_lines == nil then
    if path_exists(attachment.sidecar_path) then
      fail("sidecar was created externally; leave with :BetwixtVirtual! and attach it explicitly")
    end
    return
  end
  if not vim.deep_equal(read_lines(attachment.sidecar_path), attachment.sidecar_lines) then
    fail("sidecar changed on disk; leave with :BetwixtVirtual! and use :BetwixtRefresh")
  end
end

local function restore_undo_sequence(buffer, sequence, original_lines)
  local ok = pcall(vim.api.nvim_buf_call, buffer, function()
    if vim.fn.undotree().seq_cur ~= sequence then
      vim.cmd("silent undo! " .. sequence)
    end
  end)
  if not ok or not vim.deep_equal(source_buffer_lines(buffer), original_lines) then
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, original_lines)
  end
end

local function write_interleaved(attachment, event)
  local buffer = attachment.source_buffer
  local state = attachment.interleaved
  if not state then
    fail("current buffer is not in interleaved editing mode")
  end

  local source, review = collect_interleaved(attachment)
  if not vim.deep_equal(read_lines(attachment.source_path), state.source_lines) then
    fail("source changed on disk; leave with :BetwixtVirtual! to discard the interleaved edit")
  end
  sidecar_is_unchanged(attachment)
  if event and event.file ~= "" and absolute(event.file) ~= attachment.source_path then
    fail("interleaved editing only supports writing the attached source path")
  end

  local sidecar_lines = serialize_sidecar(review)
  local sidecar_changed = not vim.deep_equal(sidecar_lines, attachment.sidecar_lines)

  local original_lines = source_buffer_lines(buffer)
  local original_modified = vim.bo[buffer].modified
  local undo_sequence = vim.api.nvim_buf_call(buffer, function()
    return vim.fn.undotree().seq_cur
  end)
  local force = vim.v.cmdbang == 1

  if state.write_autocmd then
    pcall(vim.api.nvim_del_autocmd, state.write_autocmd)
    state.write_autocmd = nil
  end
  state.native_write = true
  vim.api.nvim_buf_clear_namespace(buffer, interleaved_namespace, 0, -1)
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, source)

  local native_ok, native_error = pcall(vim.api.nvim_buf_call, buffer, function()
    vim.cmd(force and "write!" or "write")
  end)
  local written_source = source_buffer_lines(buffer)
  restore_undo_sequence(buffer, undo_sequence, original_lines)
  state.native_write = nil
  install_interleaved_write(attachment)

  if not native_ok then
    mark_interleaved_blocks(attachment, state.blocks)
    vim.bo[buffer].modified = original_modified
    error(native_error, 0)
  end

  state.source_lines = written_source
  if sidecar_changed and vim.fn.writefile(sidecar_lines, attachment.sidecar_path) ~= 0 then
    mark_interleaved_blocks(attachment, state.blocks)
    vim.bo[buffer].modified = true
    fail("wrote source but could not write %s; the review edit remains pending", attachment.sidecar_path)
  end

  attachment.review = review
  attachment.sidecar_lines = sidecar_lines
  state.pending_review = nil
  render_interleaved(attachment, written_source, true)
  if sidecar_changed then
    vim.notify("Wrote " .. attachment.source_path .. " and " .. attachment.sidecar_path, vim.log.levels.INFO)
  else
    vim.notify("Wrote " .. attachment.source_path, vim.log.levels.INFO)
  end
end

install_interleaved_write = function(attachment)
  local state = attachment.interleaved
  if not state then
    return
  end
  state.write_autocmd = vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = attachment.source_buffer,
    nested = true,
    callback = function(event)
      write_interleaved(attachment, event)
    end,
  })
end

local function stop_interleaved(attachment, force)
  local state = attachment.interleaved
  if not state then
    return
  end

  local buffer = attachment.source_buffer
  local source
  if force then
    source = read_lines(attachment.source_path)
    if state.pending_review then
      attachment.review = state.pending_review
    end
  else
    if vim.bo[buffer].modified then
      fail("buffer has unsaved interleaved edits; use :w or :BetwixtVirtual! to discard them")
    end
    source = collect_interleaved(attachment)
  end

  if state.write_autocmd then
    pcall(vim.api.nvim_del_autocmd, state.write_autocmd)
  end
  attachment.interleaved = nil
  vim.api.nvim_buf_clear_namespace(buffer, interleaved_namespace, 0, -1)
  replace_buffer_lines(buffer, source)
  vim.bo[buffer].modified = false
  render_virtual_comments(attachment)
end

local function source_window(buffer)
  if vim.api.nvim_get_current_buf() == buffer then
    return vim.api.nvim_get_current_win()
  end
  for _, window in ipairs(vim.fn.win_findbuf(buffer)) do
    if vim.api.nvim_win_is_valid(window) then
      return window
    end
  end
end

local function pad_virtual_line(text, width, highlight_group)
  local padding = math.max(1, width - vim.fn.strdisplaywidth(text))
  return { { text .. string.rep(" ", padding), highlight_group or "BetwixtComment" } }
end

local function refresh_codediff_scroll(tabpage, leader)
  if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then
    return
  end
  local ok, scroll = pcall(require, "codediff.ui.scroll")
  if ok then
    pcall(scroll.refresh, tabpage, leader)
  end
end

clear_codediff_spacers = function(attachment, refresh)
  local alignment = attachment.codediff_alignment
  attachment.codediff_alignment = nil
  if not alignment then
    return
  end

  if vim.api.nvim_buf_is_valid(alignment.buffer) then
    for _, mark in ipairs(alignment.marks) do
      pcall(vim.api.nvim_buf_del_extmark, alignment.buffer, codediff_spacer_namespace, mark)
    end
  end
  if refresh then
    refresh_codediff_scroll(alignment.tabpage, alignment.leader)
  end
end

local function unique_anchor(resolved)
  return resolved.state == "current" or resolved.state == "moved"
end

local function render_codediff_spacers(attachment, tabpage)
  clear_codediff_spacers(attachment, false)

  local lifecycle = package.loaded["codediff.ui.lifecycle"]
  if type(lifecycle) ~= "table" then
    return false
  end

  tabpage = tabpage or lifecycle.find_tabpage_by_buffer(attachment.source_buffer)
  if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then
    return false
  end
  local layout = lifecycle.get_layout(tabpage)
  if not layout then
    return false
  end
  if layout ~= "side-by-side" then
    return true
  end

  local session = lifecycle.get_session(tabpage)
  if not session or not session.stored_diff_result then
    return false
  end

  local original_buffer, modified_buffer = lifecycle.get_buffers(tabpage)
  local original_window, modified_window = lifecycle.get_windows(tabpage)
  if
    modified_buffer ~= attachment.source_buffer
    or not original_buffer
    or not vim.api.nvim_buf_is_valid(original_buffer)
    or not vim.api.nvim_buf_is_loaded(original_buffer)
  then
    return false
  end

  local original_source = source_buffer_lines(original_buffer)
  local width = original_window
      and vim.api.nvim_win_is_valid(original_window)
      and math.max(20, vim.api.nvim_win_get_width(original_window) - 2)
    or 80
  local alignment = {
    buffer = original_buffer,
    leader = modified_window,
    marks = {},
    tabpage = tabpage,
  }
  attachment.codediff_alignment = alignment

  for _, item in ipairs(attachment.items) do
    local comment = attachment.review.comments[item.comment_index]
    local original_anchor = resolve_anchor(original_source, comment)
    if unique_anchor(item.resolved) and unique_anchor(original_anchor) then
      local line = attachment.placement == "before" and original_anchor.first or original_anchor.last
      line = math.max(1, math.min(line, math.max(1, #original_source)))

      local virtual_lines = {}
      for _ = 1, item.virtual_line_count do
        table.insert(virtual_lines, pad_virtual_line("", width, item.highlight_group))
      end
      local mark = vim.api.nvim_buf_set_extmark(original_buffer, codediff_spacer_namespace, line - 1, 0, {
        priority = 200,
        right_gravity = false,
        virt_lines = virtual_lines,
        virt_lines_above = attachment.placement == "before",
        virt_lines_overflow = "scroll",
      })
      table.insert(alignment.marks, mark)
    end
  end

  refresh_codediff_scroll(tabpage, modified_window)
  return true
end

schedule_codediff_alignment = function(attachment, tabpage)
  attachment.codediff_alignment_generation = (attachment.codediff_alignment_generation or 0) + 1
  local generation = attachment.codediff_alignment_generation
  local attempts = 50

  local function attempt()
    if
      attachments[attachment.source_buffer] ~= attachment
      or attachment.interleaved
      or attachment.codediff_alignment_generation ~= generation
    then
      return
    end
    if render_codediff_spacers(attachment, tabpage) then
      return
    end
    attempts = attempts - 1
    if attempts > 0 then
      vim.defer_fn(attempt, 20)
    end
  end

  vim.schedule(attempt)
end

render_virtual_comments = function(attachment)
  local buffer = attachment.source_buffer
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return
  end

  clear_codediff_spacers(attachment, false)
  vim.api.nvim_buf_clear_namespace(buffer, virtual_namespace, 0, -1)
  attachment.items = {}

  local source = source_buffer_lines(buffer)
  local window = source_window(buffer)
  local width = window and math.max(20, vim.api.nvim_win_get_width(window) - 2) or 80

  for index, comment in ipairs(attachment.review.comments) do
    local resolved = resolve_anchor(source, comment)
    local line = attachment.placement == "before" and resolved.first or resolved.last
    line = math.max(1, math.min(line, math.max(1, #source)))
    local highlight_group = comment_highlight(comment)

    local virtual_lines = {
      pad_virtual_line(comment_header(attachment.review, comment, resolved), width, highlight_group),
    }
    for _, body_line in ipairs(comment.body) do
      table.insert(virtual_lines, pad_virtual_line(body_line, width, highlight_group))
    end
    for _, comment_reply in ipairs(comment.replies or {}) do
      table.insert(virtual_lines, pad_virtual_line(reply_header(comment_reply), width, highlight_group))
      for _, body_line in ipairs(comment_reply.body) do
        table.insert(virtual_lines, pad_virtual_line(body_line, width, highlight_group))
      end
    end
    local edit_hint = settings.mappings.edit and settings.mappings.edit .. " edit" or ":BetwixtEdit"
    table.insert(virtual_lines, pad_virtual_line("╰─ betwixt · " .. edit_hint, width, highlight_group))

    local mark = vim.api.nvim_buf_set_extmark(buffer, virtual_namespace, line - 1, 0, {
      priority = 200,
      right_gravity = false,
      virt_lines = virtual_lines,
      virt_lines_above = attachment.placement == "before",
      virt_lines_overflow = "scroll",
    })

    table.insert(attachment.items, {
      comment_index = index,
      highlight_group = highlight_group,
      mark = mark,
      resolved = resolved,
      virtual_line_count = #virtual_lines,
    })
  end

  render_codediff_spacers(attachment)
end

local function nearest_virtual_comment(attachment)
  local buffer = attachment.source_buffer
  local window = source_window(buffer)
  if not window then
    fail("source buffer is not visible")
  end

  local cursor_line = vim.api.nvim_win_get_cursor(window)[1]
  local nearest
  local nearest_distance
  for _, item in ipairs(attachment.items) do
    local position = vim.api.nvim_buf_get_extmark_by_id(buffer, virtual_namespace, item.mark, {})
    if #position > 0 then
      local line = position[1] + 1
      local distance
      if cursor_line >= item.resolved.first and cursor_line <= item.resolved.last then
        distance = 0
      else
        distance = math.abs(cursor_line - line)
      end
      if not nearest_distance or distance < nearest_distance then
        nearest = item
        nearest_distance = distance
      end
    end
  end

  if not nearest then
    fail("no projected comment is available")
  end
  return nearest, window
end

local function refresh_attachment(attachment, reload_sidecar)
  if attachment.interleaved then
    fail("leave interleaved editing mode before refreshing")
  end
  if reload_sidecar then
    local sidecar_lines = read_lines(attachment.sidecar_path)
    attachment.review = parse_sidecar(sidecar_lines, attachment.sidecar_path)
    attachment.sidecar_lines = sidecar_lines
  end
  render_virtual_comments(attachment)
end

function M.interleave(source_buffer, target_comment_index, target_reply_index)
  source_buffer = source_buffer or vim.api.nvim_get_current_buf()
  local attachment = attachments[source_buffer]
  if not attachment then
    fail("current buffer has no Betwixt attachment")
  end
  if attachment.interleaved then
    return source_buffer
  end

  local source_was_modified = vim.bo[source_buffer].modified
  local source = source_buffer_lines(source_buffer)
  local disk_source = read_lines(attachment.source_path)
  if not source_was_modified and not vim.deep_equal(source, disk_source) then
    fail("buffer differs from the source on disk; reload it before entering interleaved mode")
  end

  local source_win
  if target_comment_index then
    source_win = source_window(source_buffer)
    if not source_win then
      fail("source buffer is not visible")
    end
  else
    local item
    item, source_win = nearest_virtual_comment(attachment)
    target_comment_index = item.comment_index
  end
  local state = {
    leader = line_comment_leader(source_buffer),
    source_lines = disk_source,
  }
  attachment.interleaved = state
  render_interleaved(attachment, source)
  if source_was_modified then
    vim.bo[source_buffer].modified = true
  end
  install_interleaved_write(attachment)

  for _, block in ipairs(state.blocks) do
    if block.comment_index == target_comment_index then
      local body_row
      if target_reply_index then
        local reply_block = block.replies[target_reply_index]
        if not reply_block then
          fail("reply %d is not available in comment %d", target_reply_index, target_comment_index)
        end
        body_row = math.min(reply_block.start_row + 2, reply_block.end_row)
      else
        body_row = math.min(block.start_row + 2, block.end_row)
      end
      local body_line = vim.api.nvim_buf_get_lines(source_buffer, body_row - 1, body_row, false)[1] or ""
      vim.api.nvim_win_set_cursor(source_win, { body_row, math.min(#body_line, #state.leader + 1) })
      break
    end
  end
  vim.notify("Betwixt comments are interleaved; :w writes source and sidecar", vim.log.levels.INFO)
  return source_buffer
end

local function default_sidecar_path(source_path)
  return source_path .. ".betwixt.md"
end

function M.comment_or_create(source_buffer, first, last, comment_type)
  source_buffer = source_buffer or vim.api.nvim_get_current_buf()
  if attachments[source_buffer] then
    return M.comment(source_buffer, first, last, comment_type)
  end
  if not vim.api.nvim_buf_is_valid(source_buffer) or vim.bo[source_buffer].buftype ~= "" then
    fail("comments require a normal file buffer")
  end

  local source_path = absolute(vim.api.nvim_buf_get_name(source_buffer))
  if vim.api.nvim_buf_get_name(source_buffer) == "" or not path_exists(source_path) then
    fail("write the source file before creating its first Betwixt comment")
  end

  local sidecar_path = default_sidecar_path(source_path)
  local created_attachment = not path_exists(sidecar_path)
  if created_attachment then
    M.attach(sidecar_path, {
      buffer = source_buffer,
      initial_review = {
        comments = {},
        file = vim.fs.basename(source_path),
      },
    })
  else
    M.attach(sidecar_path, { buffer = source_buffer })
  end

  local ok, result = pcall(M.comment, source_buffer, first, last, comment_type)
  if not ok then
    if created_attachment then
      M.detach(source_buffer, true)
    end
    error(result, 0)
  end
  return result
end

function M.comment(source_buffer, first, last, comment_type)
  source_buffer = source_buffer or vim.api.nvim_get_current_buf()
  local attachment = attachments[source_buffer]
  if not attachment then
    fail("current buffer has no Betwixt attachment")
  end
  if attachment.interleaved then
    fail("finish the current interleaved edit before adding another comment")
  end

  local source_was_modified = vim.bo[source_buffer].modified
  local source = source_buffer_lines(source_buffer)
  local disk_source = read_lines(attachment.source_path)
  if not source_was_modified and not vim.deep_equal(source, disk_source) then
    fail("buffer differs from the source on disk; reload it before adding a comment")
  end

  first = tonumber(first)
  last = tonumber(last)
  if not first or not last then
    fail("comment range is missing")
  end
  first, last = math.min(first, last), math.max(first, last)
  if first < 1 or last > #source then
    fail("comment range %d-%d is outside the source buffer", first, last)
  end

  local author = metadata_value("author", settings.author or vim.g.betwixt_author or "human")
  if comment_type == nil or vim.trim(tostring(comment_type)) == "" then
    comment_type = "comment"
  end
  comment_type = metadata_value("type", comment_type)
  local previous_review = attachment.review
  local review = vim.deepcopy(previous_review)
  table.insert(review.comments, {
    anchor = vim.list_slice(source, first, last),
    author = author,
    body = {},
    context_after = last < #source and { source[last + 1] } or {},
    context_before = first > 1 and { source[first - 1] } or {},
    first = first,
    last = last,
    replies = {},
    status = "open",
    type = comment_type,
  })
  attachment.review = review

  local comment_index = #review.comments
  local ok, result = pcall(M.interleave, source_buffer, comment_index)
  if not ok then
    attachment.review = previous_review
    if attachment.interleaved then
      vim.api.nvim_buf_clear_namespace(source_buffer, interleaved_namespace, 0, -1)
      replace_buffer_lines(source_buffer, source)
      vim.bo[source_buffer].modified = source_was_modified
    end
    attachment.interleaved = nil
    render_virtual_comments(attachment)
    error(result, 0)
  end

  attachment.interleaved.pending_review = previous_review
  vim.bo[source_buffer].modified = true
  vim.schedule(function()
    if
      attachments[source_buffer] == attachment
      and attachment.interleaved
      and vim.api.nvim_get_current_buf() == source_buffer
    then
      vim.cmd("startinsert!")
    end
  end)
  return source_buffer
end

function M.reply(source_buffer)
  source_buffer = source_buffer or vim.api.nvim_get_current_buf()
  local attachment = attachments[source_buffer]
  if not attachment then
    fail("current buffer has no Betwixt attachment")
  end
  if attachment.interleaved then
    fail("finish the current interleaved edit before adding a reply")
  end

  local source_was_modified = vim.bo[source_buffer].modified
  local source = source_buffer_lines(source_buffer)
  local item = nearest_virtual_comment(attachment)
  local author = metadata_value("author", settings.author or vim.g.betwixt_author or "human")
  local previous_review = attachment.review
  local review = vim.deepcopy(previous_review)
  local comment = review.comments[item.comment_index]
  comment.replies = comment.replies or {}
  table.insert(comment.replies, {
    author = author,
    body = {},
  })
  attachment.review = review

  local reply_index = #comment.replies
  local ok, result = pcall(M.interleave, source_buffer, item.comment_index, reply_index)
  if not ok then
    attachment.review = previous_review
    if attachment.interleaved then
      vim.api.nvim_buf_clear_namespace(source_buffer, interleaved_namespace, 0, -1)
      replace_buffer_lines(source_buffer, source)
      vim.bo[source_buffer].modified = source_was_modified
    end
    attachment.interleaved = nil
    render_virtual_comments(attachment)
    error(result, 0)
  end

  attachment.interleaved.pending_review = previous_review
  vim.bo[source_buffer].modified = true
  vim.schedule(function()
    if
      attachments[source_buffer] == attachment
      and attachment.interleaved
      and vim.api.nvim_get_current_buf() == source_buffer
    then
      vim.cmd("startinsert!")
    end
  end)
  return source_buffer
end

function M.virtualize(source_buffer, force)
  source_buffer = source_buffer or vim.api.nvim_get_current_buf()
  local attachment = attachments[source_buffer]
  if not attachment then
    fail("current buffer has no Betwixt attachment")
  end
  stop_interleaved(attachment, force)
  return source_buffer
end

function M.toggle(source_buffer)
  source_buffer = source_buffer or vim.api.nvim_get_current_buf()
  local attachment = attachments[source_buffer]
  if not attachment then
    fail("current buffer has no Betwixt attachment")
  end
  if attachment.interleaved then
    return M.virtualize(source_buffer, false)
  end
  return M.interleave(source_buffer)
end

function M.detach(source_buffer, force)
  source_buffer = source_buffer or vim.api.nvim_get_current_buf()
  local attachment = attachments[source_buffer]
  if not attachment then
    return
  end

  stop_interleaved(attachment, force)
  attachment.codediff_alignment_generation = (attachment.codediff_alignment_generation or 0) + 1
  clear_codediff_spacers(attachment, true)
  if vim.api.nvim_buf_is_valid(source_buffer) then
    vim.api.nvim_buf_clear_namespace(source_buffer, virtual_namespace, 0, -1)
    pcall(vim.api.nvim_buf_del_user_command, source_buffer, "BetwixtEdit")
    pcall(vim.api.nvim_buf_del_user_command, source_buffer, "BetwixtComment")
    pcall(vim.api.nvim_buf_del_user_command, source_buffer, "BetwixtReply")
    pcall(vim.api.nvim_buf_del_user_command, source_buffer, "BetwixtToggle")
    pcall(vim.api.nvim_buf_del_user_command, source_buffer, "BetwixtVirtual")
    pcall(vim.api.nvim_buf_del_user_command, source_buffer, "BetwixtRefresh")
    pcall(vim.api.nvim_buf_del_user_command, source_buffer, "BetwixtDetach")
    for _, mapping in ipairs(attachment.mappings) do
      pcall(vim.keymap.del, mapping.mode, mapping.lhs, { buffer = source_buffer })
    end
  end
  if attachment.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, attachment.augroup)
  end
  attachments[source_buffer] = nil
end

function M.attach(sidecar_path, options)
  options = options or {}
  local source_buffer = options.buffer or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(source_buffer) then
    fail("source buffer is invalid")
  end

  sidecar_path = absolute(sidecar_path)
  local sidecar_lines
  local review
  if options.initial_review then
    review = vim.deepcopy(options.initial_review)
  else
    sidecar_lines = read_lines(sidecar_path)
    review = parse_sidecar(sidecar_lines, sidecar_path)
  end
  local expected_source = absolute(vim.fs.joinpath(vim.fs.dirname(sidecar_path), review.file))
  local actual_source = absolute(vim.api.nvim_buf_get_name(source_buffer))
  if expected_source ~= actual_source then
    fail("sidecar targets %s, not %s", expected_source, actual_source)
  end
  if vim.bo[source_buffer].buftype ~= "" then
    fail("attached source must be a normal file buffer")
  end

  if attachments[source_buffer] then
    M.detach(source_buffer, false)
  end

  local attachment = {
    placement = options.placement or "after",
    review = review,
    mappings = {},
    sidecar_lines = sidecar_lines,
    sidecar_path = sidecar_path,
    source_buffer = source_buffer,
    source_path = actual_source,
  }
  if attachment.placement ~= "after" and attachment.placement ~= "before" then
    fail("placement must be 'before' or 'after'")
  end
  attachments[source_buffer] = attachment

  set_default_highlights()
  render_virtual_comments(attachment)

  vim.api.nvim_buf_create_user_command(source_buffer, "BetwixtEdit", function()
    M.interleave(source_buffer)
  end, { desc = "Materialize Betwixt comments for ordinary buffer editing" })
  vim.api.nvim_buf_create_user_command(source_buffer, "BetwixtComment", function(command)
    M.comment(source_buffer, command.line1, command.line2, command.args)
  end, {
    desc = "Add a Betwixt comment on a source range",
    nargs = "?",
    range = true,
  })
  vim.api.nvim_buf_create_user_command(source_buffer, "BetwixtReply", function()
    M.reply(source_buffer)
  end, { desc = "Reply to the nearest Betwixt comment" })
  vim.api.nvim_buf_create_user_command(source_buffer, "BetwixtToggle", function()
    M.toggle(source_buffer)
  end, { desc = "Toggle virtual and interleaved Betwixt comments" })
  vim.api.nvim_buf_create_user_command(source_buffer, "BetwixtVirtual", function(command)
    M.virtualize(source_buffer, command.bang)
  end, { bang = true, desc = "Return interleaved Betwixt comments to virtual display" })
  vim.api.nvim_buf_create_user_command(source_buffer, "BetwixtRefresh", function()
    refresh_attachment(attachment, true)
  end, { desc = "Reload and project the Betwixt sidecar" })
  vim.api.nvim_buf_create_user_command(source_buffer, "BetwixtDetach", function()
    M.detach(source_buffer, false)
  end, { desc = "Remove the Betwixt projection" })
  if settings.mappings.edit then
    vim.keymap.set("n", settings.mappings.edit, function()
      M.toggle(source_buffer)
    end, { buffer = source_buffer, desc = "Toggle editable Betwixt comments" })
    table.insert(attachment.mappings, { lhs = settings.mappings.edit, mode = "n" })
  end
  if settings.mappings.comment then
    vim.keymap.set("n", settings.mappings.comment, "<Cmd>BetwixtComment<CR>", {
      buffer = source_buffer,
      desc = "Comment on the current line with Betwixt",
    })
    vim.keymap.set("x", settings.mappings.comment, ":BetwixtComment<CR>", {
      buffer = source_buffer,
      desc = "Comment on the selected lines with Betwixt",
    })
    table.insert(attachment.mappings, { lhs = settings.mappings.comment, mode = "n" })
    table.insert(attachment.mappings, { lhs = settings.mappings.comment, mode = "x" })
  end

  attachment.augroup = vim.api.nvim_create_augroup("BetwixtAttached" .. source_buffer, { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = source_buffer,
    group = attachment.augroup,
    callback = function()
      if attachment.interleaved and attachment.interleaved.native_write then
        return
      end
      refresh_attachment(attachment, false)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = source_buffer,
    group = attachment.augroup,
    callback = function()
      attachment.codediff_alignment_generation = (attachment.codediff_alignment_generation or 0) + 1
      clear_codediff_spacers(attachment, false)
      attachments[source_buffer] = nil
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = source_buffer,
    group = attachment.augroup,
    callback = function()
      local lifecycle = package.loaded["codediff.ui.lifecycle"]
      if type(lifecycle) ~= "table" then
        return
      end
      local tabpage = lifecycle.find_tabpage_by_buffer(source_buffer)
      if tabpage then
        schedule_codediff_alignment(attachment, tabpage)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinNew", {
    group = attachment.augroup,
    callback = function()
      local lifecycle = package.loaded["codediff.ui.lifecycle"]
      if type(lifecycle) ~= "table" then
        return
      end
      local tabpage = lifecycle.find_tabpage_by_buffer(source_buffer)
      if tabpage and tabpage == vim.api.nvim_get_current_tabpage() then
        schedule_codediff_alignment(attachment, tabpage)
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = attachment.augroup,
    pattern = "CodeDiffOpen",
    callback = function(event)
      local tabpage = event.data and event.data.tabpage
      if not tabpage or not vim.api.nvim_tabpage_is_valid(tabpage) then
        return
      end
      for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        if vim.api.nvim_win_get_buf(window) == source_buffer then
          schedule_codediff_alignment(attachment, tabpage)
          return
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = attachment.augroup,
    pattern = "CodeDiffClose",
    callback = function(event)
      local tabpage = event.data and event.data.tabpage
      if attachment.codediff_alignment and attachment.codediff_alignment.tabpage == tabpage then
        attachment.codediff_alignment_generation = (attachment.codediff_alignment_generation or 0) + 1
        clear_codediff_spacers(attachment, false)
      end
    end,
  })

  return attachment
end

function M.open(sidecar_path, options)
  options = options or {}
  local placement = options.placement or "after"
  if placement ~= "after" and placement ~= "before" then
    fail("placement must be 'before' or 'after'")
  end

  sidecar_path = absolute(sidecar_path)
  for buffer, session in pairs(sessions) do
    if
      vim.api.nvim_buf_is_valid(buffer)
      and session.sidecar_path == sidecar_path
      and session.placement == placement
    then
      vim.api.nvim_set_current_buf(buffer)
      reload(buffer, false)
      return buffer
    end
  end

  local sidecar_lines = read_lines(sidecar_path)
  local review = parse_sidecar(sidecar_lines, sidecar_path)
  local source_path = absolute(vim.fs.joinpath(vim.fs.dirname(sidecar_path), review.file))
  local buffer = vim.api.nvim_create_buf(false, true)
  local session = {
    placement = placement,
    review = review,
    sidecar_lines = sidecar_lines,
    sidecar_path = sidecar_path,
    source_lines = read_lines(source_path),
    source_path = source_path,
  }

  sessions[buffer] = session
  vim.api.nvim_buf_set_name(buffer, "betwixt://" .. sidecar_path .. "#" .. placement)
  vim.api.nvim_set_current_buf(buffer)
  set_buffer_options(buffer, source_path)

  set_default_highlights()

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buffer,
    callback = function()
      write_projection(buffer)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buffer,
    callback = function()
      sessions[buffer] = nil
    end,
  })
  vim.api.nvim_buf_create_user_command(buffer, "BetwixtReload", function(command)
    reload(buffer, command.bang)
  end, { bang = true, desc = "Reload source and Betwixt sidecar" })

  render_into_buffer(buffer, session)
  return buffer
end

function M.setup(options)
  options = options or {}
  if type(options) ~= "table" then
    fail("setup options must be a table")
  end

  settings = vim.tbl_deep_extend("force", vim.deepcopy(defaults), options)
  if settings.author ~= nil then
    if type(settings.author) ~= "string" then
      fail("author must be a string")
    end
    settings.author = metadata_value("author", settings.author)
  end
  if type(settings.mappings) ~= "table" then
    fail("mappings must be a table")
  end
  for name, mapping in pairs(settings.mappings) do
    if defaults.mappings[name] == nil then
      fail("unknown mapping %q", name)
    end
    if mapping ~= false and (type(mapping) ~= "string" or mapping == "") then
      fail("%s mapping must be a non-empty string or false", name)
    end
  end
  return M
end

return M
