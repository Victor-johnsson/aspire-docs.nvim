local aspire_docs = require("aspire_docs")

if not aspire_docs.config then
  aspire_docs.setup()
end

vim.api.nvim_create_user_command("AspireDocsList", function()
  require("telescope").extensions.aspire_docs.list()
end, {})

vim.api.nvim_create_user_command("AspireDocsSearch", function(opts)
  require("telescope").extensions.aspire_docs.search({ query = opts.args })
end, { nargs = 1 })

vim.api.nvim_create_user_command("AspireDocsGet", function(opts)
  local slug = opts.args
  require("aspire_docs.util").run_cmd({ "docs", "get", slug }, function(lines)
    require("aspire_docs.util").open_doc(lines, "Aspire Docs", aspire_docs.config.open_mode)
  end)
end, { nargs = 1 })
