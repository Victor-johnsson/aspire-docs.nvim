local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local util = require("aspire_docs.util")

local function make_entry(item, opts)
  local display = item.title
  if item.slug ~= item.title then
    display = item.title .. " (" .. item.slug .. ")"
  end
  if item.section and item.section ~= "" then
    display = display .. " · " .. item.section
  end
  if opts and opts.show_summary and item.summary and item.summary ~= "" then
    display = display .. " — " .. item.summary
  end
  return {
    value = item,
    display = display,
    ordinal = table.concat({ item.title or "", item.slug or "", item.section or "", item.summary or "" }, " "),
  }
end

local function open_doc_by_slug(slug, opts)
  util.run_cmd({ "docs", "get", slug }, function(lines)
    local cleaned = util.clean_doc_lines(lines)
    util.open_doc(cleaned, opts.preview_title or "Aspire Docs", opts.open_mode)
  end)
end

local function run_list(opts)
  util.run_cmd({ "docs", "list" }, function(lines)
    local items = util.parse_docs_items(lines)

    pickers.new(opts, {
      prompt_title = "Aspire Docs",
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          return make_entry(item, opts)
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection and selection.value then
            open_doc_by_slug(selection.value.slug, opts)
          end
        end)
        return true
      end,
    }):find()
  end)
end

local function run_search(opts)
  local query = opts.query
  if not query or query == "" then
    vim.notify("AspireDocsSearch requires a query", vim.log.levels.WARN)
    return
  end

  util.run_cmd({ "docs", "search", query }, function(lines)
    local items = util.parse_docs_items(lines)

    pickers.new(opts, {
      prompt_title = "Aspire Docs Search",
      finder = finders.new_table({
        results = items,
        entry_maker = function(item)
          return make_entry(item, opts)
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection and selection.value then
            open_doc_by_slug(selection.value.slug, opts)
          end
        end)
        return true
      end,
    }):find()
  end)
end

return {
  list = run_list,
  search = run_search,
}
