local aspire_docs = require("aspire_docs")
local util = require("aspire_docs.util")

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
  local cfg = aspire_docs.config

  -- Try configured fetch first (github_raw/local_repo)
  if (cfg.source == "github_raw") or (cfg.local_repo_path and cfg.local_repo_path ~= "") then
    vim.notify("AspireDocs: attempting to fetch '" .. slug .. "' from configured source...", vim.log.levels.INFO)
    local fetched = util.fetch_doc(slug)
    if fetched then
      local cleaned = util.clean_doc_lines(fetched)
      util.open_doc(cleaned, cfg.preview_title or "Aspire Docs", cfg.open_mode)
      return
    else
      vim.notify("AspireDocs: fetch from source failed, falling back to Aspire CLI", vim.log.levels.WARN)
    end
  end

  -- Fallback to Aspire CLI
  vim.notify("AspireDocs: running 'aspire docs get " .. slug .. "'...", vim.log.levels.INFO)
  util.run_cmd({ "docs", "get", slug }, function(lines)
    util.open_doc(lines, cfg.preview_title or "Aspire Docs", cfg.open_mode)
  end, function(err)
    vim.notify("AspireDocs: failed to get doc: " .. tostring(err), vim.log.levels.ERROR)
  end)
end, { nargs = 1 })

-- Build remote index in background on startup when enabled and no fresh cache exists.
vim.schedule(function()
  local cfg = aspire_docs.config
  if cfg and cfg.index and cfg.index.enabled and cfg.source == "github_raw" then
    local ok, cached = pcall(function() return require("aspire_docs.util").get_cached_index() end)
    if not ok or not cached then
      -- start async build
      pcall(function()
        require("aspire_docs.util").build_remote_index_async()
      end)
    end
  end
end)

vim.api.nvim_create_user_command("AspireDocsIndexRefresh", function()
  local ok = pcall(function()
    vim.notify("AspireDocs: refreshing index...", vim.log.levels.INFO)
    require("aspire_docs.util").build_remote_index_async()
  end)
  if not ok then
    vim.notify("AspireDocs: failed to start index refresh", vim.log.levels.ERROR)
  end
end, {})

vim.api.nvim_create_user_command("AspireDocsIndexClear", function()
  local ok, err = pcall(function()
    local success, msg_or_err = require("aspire_docs.util").clear_index_cache()
    if success then
      vim.notify("AspireDocs: cleared index cache", vim.log.levels.INFO)
    else
      vim.notify("AspireDocs: failed to clear index cache: " .. tostring(msg_or_err), vim.log.levels.WARN)
    end
  end)
  if not ok then
    vim.notify("AspireDocs: error while clearing index cache", vim.log.levels.ERROR)
  end
end, {})
