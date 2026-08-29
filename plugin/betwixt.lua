if vim.g.loaded_betwixt then
  return
end
vim.g.loaded_betwixt = true

vim.api.nvim_create_user_command("BetwixtOpen", function(command)
  require("betwixt").open(command.args, {
    placement = command.bang and "before" or "after",
  })
end, {
  bang = true,
  complete = "file",
  desc = "Open an editable Betwixt review projection (! places comments before ranges)",
  nargs = 1,
})

vim.api.nvim_create_user_command("BetwixtAttach", function(command)
  require("betwixt").attach(command.args, {
    placement = command.bang and "before" or "after",
  })
end, {
  bang = true,
  complete = "file",
  desc = "Project Betwixt comments onto the current source buffer",
  nargs = 1,
})

vim.api.nvim_create_user_command("BetwixtComment", function(command)
  require("betwixt").comment_or_create(vim.api.nvim_get_current_buf(), command.line1, command.line2, command.args)
end, {
  desc = "Add a Betwixt comment, creating and attaching the default sidecar when needed",
  nargs = "?",
  range = true,
})
