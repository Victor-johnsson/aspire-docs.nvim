local picker = require("aspire_docs.telescope.picker")

local M = {}

function M.list(opts)
  picker.list(vim.tbl_extend("force", require("aspire_docs").config, opts or {}))
end

function M.search(opts)
  picker.search(vim.tbl_extend("force", require("aspire_docs").config, opts or {}))
end

return M
