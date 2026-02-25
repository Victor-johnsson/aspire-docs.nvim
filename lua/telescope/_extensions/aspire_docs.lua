return require("telescope").register_extension({
  exports = {
    list = require("aspire_docs.telescope").list,
    search = require("aspire_docs.telescope").search,
  },
})
