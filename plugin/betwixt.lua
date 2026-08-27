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
