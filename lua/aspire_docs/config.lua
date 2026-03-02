local M = {}

M.defaults = {
  aspire_cmd = "aspire",
  default_args = { "--non-interactive", "--nologo" },
  preview_title = "Aspire Docs",
  open_mode = "tab",
  show_summary = false,
  wrap = true,
  linebreak = true,
  breakindent = true,
  -- where to fetch docs from: "aspire_cli" | "github_raw" | "local_repo"
  source = "github_raw",
  github_raw_base = "https://raw.githubusercontent.com/microsoft/aspire.dev/main/src/frontend/src/content/docs",
  local_repo_path = nil,
  -- remote index options
  index = {
    enabled = true,
    ttl_seconds = 24 * 60 * 60, -- 1 day
    cache_file = nil, -- defaults to stdpath('cache')/aspire_docs_index.json
  },
  -- preview renderer: "browser" | "none"
  preview_renderer = "browser",
  -- persistent normalized doc cache
  doc_cache = {
    enabled = true,
    -- optional explicit directory; defaults to stdpath('cache')/aspire_docs_docs
    dir = nil,
  },
}

return M
