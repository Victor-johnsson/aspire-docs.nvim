# aspire-docs.nvim

Browse and search Aspire documentation from inside Neovim using the `aspire docs` CLI.

## Requirements

- Neovim 0.10+ (for `vim.system`)
- [Telescope](https://github.com/nvim-telescope/telescope.nvim)
- [Aspire CLI](https://learn.microsoft.com/dotnet/aspire/get-started/aspire-cli) on your PATH

## Installation

### lazy.nvim

```lua
{
  "aspire-docs.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("aspire_docs").setup()
    require("telescope").load_extension("aspire_docs")
  end,
}
```

## Usage

```lua
-- Commands
:AspireDocsList
:AspireDocsSearch <query>
:AspireDocsGet <slug>

-- Telescope extension
:Telescope aspire_docs list
:Telescope aspire_docs search query=networking
```

## Configuration

```lua
require("aspire_docs").setup({
  aspire_cmd = "aspire",
  default_args = { "--non-interactive", "--nologo" },
  preview_title = "Aspire Docs",
  open_mode = "tab",
  show_summary = false,
})
```

### Options

- `aspire_cmd` (string): CLI executable name.
- `default_args` (string[]): Arguments added to all commands.
- `preview_title` (string): Title shown in preview window.
- `open_mode` ("tab"|"split"|"vsplit"|"current"): How to open docs from Telescope.
- `show_summary` (boolean): Include summary text in Telescope results.

## Keymaps

You can map the Telescope pickers however you like:

```lua
vim.keymap.set("n", "<leader>al", function()
  require("telescope").extensions.aspire_docs.list()
end)

vim.keymap.set("n", "<leader>as", function()
  require("telescope").extensions.aspire_docs.search({ query = vim.fn.input("Aspire search: ") })
end)
```

## License

MIT

## Development

To sanity-check CLI parsing against fixture output:

```bash
lua scripts/parse_fixture.lua
```

To enforce fixture output matching (for CI or quick checks):

```bash
lua scripts/parse_fixture.lua --expect
```
