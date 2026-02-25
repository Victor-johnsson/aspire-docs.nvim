# aspire-docs.nvim

Use Aspire documentation from inside Neovim. The plugin provides a Telescope-powered picker, quick open commands, and optional previews.

Supported features
- Index-backed listing (GitHub raw tree) and fallback to the Aspire CLI
- MDX → readable Markdown normalization (frontmatter, imports, Image removal, common components)
- In-memory and optional disk caching of normalized docs
- Integrated preview using `glow` (terminal) or browser via `marked`

Requirements
- Neovim 0.10+ (uses `vim.system` and job APIs)
- Telescope (recommended) for pickers
- Aspire CLI on PATH is required only if you use `source = "aspire_cli"` or to fallback when raw fetching fails
- (Optional) `glow` in PATH for terminal previews when `preview_renderer = "glow"`
- (Optional) `marked` (npm) when using `preview_renderer = "browser"`

Installation examples

- lazy.nvim / LazyVim

```lua
-- plugins/aspire_docs.lua (LazyVim style)
return {
  {
    "victor/aspire-docs.nvim",
    dependencies = { "nvim-telescope/telescope.nvim" },
    config = function()
      require("aspire_docs").setup()
      require("telescope").load_extension("aspire_docs")
    end,
  }
}
```

- packer.nvim

```lua
use {
  "victor/aspire-docs.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("aspire_docs").setup()
    require("telescope").load_extension("aspire_docs")
  end
}
```

- vim-plug

```vim
Plug 'victor/aspire-docs.nvim'
lua << EOF
  require('aspire_docs').setup()
  require('telescope').load_extension('aspire_docs')
EOF
```

Basic usage

- Commands
  - `:AspireDocsList` — open Telescope picker with index-backed list and preview
  - `:AspireDocsSearch <query>` — search docs (uses Aspire CLI fallback)
  - `:AspireDocsGet <slug>` — open a specific doc by slug (`app-host/eventing` or `app-host-eventing`)
  - `:AspireDocsIndexRefresh` — rebuild the remote index in background

- Telescope extension
  - `:Telescope aspire_docs list`
  - `:Telescope aspire_docs search query=networking`

Example keymaps

```lua
vim.keymap.set("n", "<leader>al", function()
  require("telescope").extensions.aspire_docs.list()
end)

vim.keymap.set("n", "<leader>as", function()
  require("telescope").extensions.aspire_docs.search({ query = vim.fn.input("Aspire search: ") })
end)
```

Configuration

You can call `require('aspire_docs').setup({ ... })` to override defaults. Example:

```lua
require('aspire_docs').setup({
  aspire_cmd = "aspire",
  default_args = { "--non-interactive", "--nologo" },
  preview_renderer = "glow", -- "glow" | "browser" | "none"
  open_mode = "tab",         -- "tab" | "split" | "vsplit" | "current"
  source = "github_raw",     -- "github_raw" | "aspire_cli" | "local_repo"
  github_raw_base = "https://raw.githubusercontent.com/microsoft/aspire.dev/main/src/frontend/src/content/docs",
  local_repo_path = nil,      -- set when using a local clone
  index = { enabled = true, ttl_seconds = 86400 },
  doc_cache = { enabled = true },
})
```

Notes about dependencies and preview
- If `preview_renderer = "glow"` the plugin will try to run the `glow` binary in a terminal split. If `glow` is not installed the plugin will notify you with: `AspireDocs: 'glow' not found in PATH`.
- If `preview_renderer = "browser"` the plugin uses `marked` (npm) to convert markdown to HTML and opens it with your `$BROWSER` or `open` on macOS.
- The plugin is usable without `glow` — previews are optional. If you prefer no preview set `preview_renderer = "none"`.

CheckHealth behavior
- Currently the plugin does not register a CheckHealth provider. That means `:checkhealth` will not report missing `glow` or `marked` automatically.
- If you would like, I can add a `vim.health` module so `:checkhealth` warns when required binaries are missing and when the Aspire CLI is not found. Would you like me to add that? (yes/no)

Development & tests

There is a small fixture-based parser test to verify CLI output parsing. Run locally:

```bash
lua scripts/parse_fixture.lua         # prints parsed fixture output
lua scripts/parse_fixture.lua --expect # exits non-zero if parsing differs from expected
```

Troubleshooting
- If a doc preview is blank, try `:AspireDocsIndexRefresh` to rebuild the index.
- Disk cache location: `stdpath('cache') .. '/aspire_docs_docs'` by default (configurable via `doc_cache.dir`).
- Clear in-memory cache with: `lua require('aspire_docs.util').clear_doc_cache()`

License

MIT
