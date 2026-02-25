local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

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
  opts = opts or {}
  local config = require("aspire_docs").config

  -- If configured to use the GitHub/raw source, try it first
  if config.source == "github_raw" or (config.local_repo_path and config.local_repo_path ~= "") then
    -- try remote index lookup first
    local index = util.load_remote_index()
  if index and index[slug] then
      -- fetch the exact file path from raw base
      local url = config.github_raw_base
      if url:sub(-1) ~= "/" then url = url .. "/" end
      local fetched = vim.system({ "curl", "-fsSL", url .. index[slug] }, { text = true }):wait()
      if fetched and fetched.code == 0 and fetched.stdout then
        local lines = {}
        for l in tostring(fetched.stdout):gmatch("[^\r\n]+") do lines[#lines+1] = l end
        local cleaned = util.clean_doc_lines(lines)
        util.open_doc(cleaned, opts.preview_title or "Aspire Docs", opts.open_mode)
        -- open preview if requested
        if (opts and opts.preview) or require("aspire_docs").config.preview_renderer ~= "none" then
          pcall(function() require("aspire_docs.util").preview_doc(cleaned) end)
        end
        return
      end
    end

    local fetched = util.fetch_doc(slug)
    if fetched then
      -- If the fetched doc looks like JSON (some raw files may still be wrapped), try to decode
      local raw = table.concat(fetched, "\n")
      local ok, data = pcall(vim.json.decode, raw)
      if ok and type(data) == "table" and data.content then
        local body = data.content
        if tostring(body):match("<[^>]+>") then
          body = util.strip_html(tostring(body))
        end
        local out_lines = {}
        for line in tostring(body):gmatch("[^\r\n]+") do
          out_lines[#out_lines + 1] = line
        end
        out_lines = util.clean_doc_lines(out_lines)
        util.open_doc(out_lines, data.title or opts.preview_title or "Aspire Docs", opts.open_mode)
        return
      end

      -- Otherwise assume it's the raw MDX/markdown content
      local cleaned = util.clean_doc_lines(fetched)
      util.open_doc(cleaned, opts.preview_title or "Aspire Docs", opts.open_mode)
      if (opts and opts.preview) or require("aspire_docs").config.preview_renderer ~= "none" then
        pcall(function() require("aspire_docs.util").preview_doc(cleaned) end)
      end
      return
    end
  end

  -- Fallback to CLI if fetching failed
  util.run_cmd({ "docs", "get", slug, "--format", "Json" }, function(lines)
    local cleaned = util.clean_doc_lines(lines)
    util.open_doc(cleaned, opts.preview_title or "Aspire Docs", opts.open_mode)
  end)
end

local function make_previewer()
  return previewers.new_buffer_previewer({
    title = "Aspire Docs Preview",
    define_preview = function(self, entry, status)
      local bufnr = self.state.bufnr
      vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
      local slug = nil
      if entry and entry.value and entry.value.slug then
        slug = entry.value.slug
      elseif entry and entry.slug then
        slug = entry.slug
      end
      if not slug then
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "No slug" })
        return
      end

      local util = require("aspire_docs.util")

      -- If we have an in-memory cache, show it immediately
      if util._doc_cache and util._doc_cache[slug] then
        local cleaned = util.clean_doc_lines(util._doc_cache[slug])
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, cleaned)
        return
      end

      -- Try cached index (no network) to fetch raw path quickly
      local idx = nil
      pcall(function() idx = util.get_cached_index() end)
      if idx and idx[slug] then
        local cfg = require("aspire_docs").config
        local url = cfg.github_raw_base
        if url:sub(-1) ~= "/" then url = url .. "/" end
        url = url .. idx[slug]

      -- show placeholder
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Loading preview..." })

        -- fetch in background and update preview when ready
        vim.fn.jobstart({ "curl", "-fsSL", url }, {
          stdout_buffered = true,
          on_stdout = function(_, data, _)
            if data and #data > 0 then
              -- store to in-memory cache and render cleaned lines
              -- normalize data into lines
              local lines = {}
              for l in table.concat(data, "\n"):gmatch("[^\r\n]+") do lines[#lines+1] = l end
              util._doc_cache[slug] = lines
              local cleaned = util.clean_doc_lines(lines)
              vim.schedule(function()
                if vim.api.nvim_buf_is_valid(bufnr) then
                  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, cleaned)
                end
              end)
            end
          end,
          on_stderr = function() end,
        })
        return
      end

      -- Fallback: call the CLI asynchronously (will update preview when done)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Loading preview..." })
      util.run_cmd({ "docs", "get", slug, "--format", "Json" }, function(lines_cli)
        util._doc_cache[slug] = lines_cli
        local cleaned = util.clean_doc_lines(lines_cli)
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, cleaned)
          end
        end)
      end)
    end,
  })
end

local function run_list(opts)
  -- Prefer index-based listing when available
  local index = util.load_remote_index()
  if index then
    local results = {}
    for slug, path in pairs(index) do
      results[#results + 1] = { title = util.humanize_slug(slug), slug = slug }
    end

    table.sort(results, function(a, b) return a.title < b.title end)

    pickers.new(opts, {
      prompt_title = "Aspire Docs (index)",
      finder = finders.new_table({ results = results, entry_maker = function(item) return make_entry(item, opts) end }),
      sorter = conf.generic_sorter(opts),
      previewer = make_previewer(),
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
    return
  end

  -- Fallback to CLI listing
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
      previewer = make_previewer(),
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
