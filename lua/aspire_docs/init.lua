local M = {}

local config = require("aspire_docs.config")

M.config = vim.deepcopy(config.defaults)

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(config.defaults), opts or {})
end

return M
