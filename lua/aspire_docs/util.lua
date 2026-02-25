local M = {}

local function normalize_lines(output)
  local lines = {}
  for line in output:gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
  end
  return lines
end

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize_whitespace(value)
  return trim(value:gsub("%s+", " "))
end

local function strip_html(value)
  return value:gsub("<[^>]+>", "")
end

local function strip_ansi(value)
  return value:gsub("\27%[[0-9;?]*[ -/]*[@-~]", "")
end

local function is_spacey_line(line)
  if line:match("^%s*```") then
    return false
  end
  return line:match("  ") ~= nil or line:match("%s%*%s") ~= nil
end

local function ensure_blank_line(out, current)
  local last = out[#out] or ""
  local trimmed = trim(current)
  if trimmed == "" then
    return
  end
  if last ~= "" then
    out[#out + 1] = ""
  end
end

local function normalize_doc_lines(lines)
  local out = {}
  local in_code = false
  local pending = ""

  local function flush_pending(force)
    local value = trim(pending)
    if value ~= "" then
      out[#out + 1] = value
    elseif force and #out > 0 and out[#out] ~= "" then
      out[#out + 1] = ""
    end
    pending = ""
  end

  for _, line in ipairs(lines) do
    local stripped = strip_ansi(line)

    if stripped:match("^%s*```") then
      flush_pending(false)
      if #out > 0 and out[#out] ~= "" then
        out[#out + 1] = ""
      end
      out[#out + 1] = stripped
      in_code = not in_code
    elseif in_code then
      out[#out + 1] = stripped
    else
      local current = stripped
      -- Normalize inline fenced code blocks like: ```bash echo hi ``` ->
      -- ```bash\necho hi\n```
      current = current:gsub("```%s*([^`]-)%s*```", "```\n%1\n```")

      current = current:gsub("%s%[Section titled.-%]%([^)]+%)", "")
      current = current:gsub("%s+$", "")
      current = current:gsub("%s%*%s", "\n- ")
      current = current:gsub("(%S)%s(#+%s)", "%1\n\n%2")
      current = current:gsub("(%S)%s(> )", "%1\n\n%2")
      current = current:gsub("(%S)%s(!%[)", "%1\n\n%2")
      current = current:gsub("(%S)%s(```)", "%1\n\n%2")

      for chunk in current:gmatch("[^\n]+") do
        local trimmed = trim(chunk)
        if trimmed == "" then
          flush_pending(true)
        else
          local list = trimmed:match("^[-*+]%s+")
          local heading = trimmed:match("^#+%s")
          local quote = trimmed:match("^>%s")
          local image = trimmed:match("^!%[")

          if list or heading or quote or image then
            flush_pending(false)
            ensure_blank_line(out, trimmed)
            out[#out + 1] = trimmed
          elseif is_spacey_line(chunk) then
            flush_pending(false)
            ensure_blank_line(out, trimmed)
            out[#out + 1] = trimmed
          else
            if pending == "" then
              pending = trimmed
            else
              pending = pending .. " " .. trimmed
            end
          end
        end
      end
    end
  end

  flush_pending(false)
  -- Post-process: remove any remaining 'Section titled' links and ensure
  -- headings/blocks have surrounding blank lines for readability.
  for i = 1, #out do
    -- remove Section titled(...) occurrences (loose match, handles unicode quotes)
    out[i] = out[i]:gsub('%[Section titled[^" ]-?%]%([^%)]+%)', '')
    out[i] = out[i]:gsub('%[Section titled.-%]%([^%)]+%)', '')
  end

  local final = {}
  for i = 1, #out do
    local line = out[i]
    local trimmed = trim(line)

    -- insert blank line before headings, blockquotes, lists, images, code fences, and tables
    if (trimmed ~= "") and (trimmed:match("^#") or trimmed:match("^>") or trimmed:match("^[-*+]%s+") or trimmed:match("^!%[") or trimmed:match("^```") or trimmed:match("^|")) then
      if #final > 0 and final[#final] ~= "" then
        final[#final + 1] = ""
      end
      final[#final + 1] = line
    else
      final[#final + 1] = line
    end
  end

  -- Split lines where a section link was removed but left trailing text after a heading
  for i = 1, #final do
    -- If a heading line contains a closing paren followed by a space and capital letter,
    -- split it into heading and following paragraph.
    if final[i]:match("^#+.*%)%s+[A-Z]") then
      local a, b = final[i]:match("^(#.-%))%s+(.+)$")
      if a and b then
        final[i] = a
        table.insert(final, i + 1, "")
        table.insert(final, i + 2, b)
      end
    end
  end

  return final
end

local function split_table_row(line)
  local cells = {}
  if line:match("^│") then
    for cell in line:gmatch("│([^│]*)") do
      cells[#cells + 1] = trim(cell)
    end
  elseif line:match("^|") then
    for cell in line:gmatch("|([^|]*)") do
      cells[#cells + 1] = trim(cell)
    end
  end
  return cells
end

local function is_header_row(cells)
  for _, cell in ipairs(cells) do
    if cell == "Title" then
      return true
    end
  end
  return false
end

local function is_separator_row(cells)
  local has_cell = false
  for _, cell in ipairs(cells) do
    if cell ~= "" then
      has_cell = true
      if not cell:match("^%s*[:-]+%s*$") then
        return false
      end
    end
  end
  return has_cell
end

local function parse_table(lines)
  local header = {}
  local header_set = false
  local items = {}
  local current = nil

  for _, line in ipairs(lines) do
    if line:match("^│") or line:match("^|") then
      local cells = split_table_row(line)
      if #cells > 0 and is_header_row(cells) then
        for i, cell in ipairs(cells) do
          if cell == "Title" then
            header.title = i
          elseif cell == "Slug" then
            header.slug = i
          elseif cell == "Section" then
            header.section = i
          elseif cell == "Summary" then
            header.summary = i
          elseif cell == "Score" then
            header.score = i
          end
        end
        header_set = true
      elseif header_set and not is_separator_row(cells) then
        local title = header.title and cells[header.title] or ""
        local slug = header.slug and cells[header.slug] or ""
        local section = header.section and cells[header.section] or ""
        local summary = header.summary and cells[header.summary] or ""
        local score = header.score and cells[header.score] or ""

        local is_continuation = current
          and ((header.score and score == "")
            or (title == "" and slug == "" and section == "" and summary == ""))

        if current and current.slug and current.slug:sub(-1) == "-" then
          if title ~= "" then
            current.title = current.title .. " " .. title
          end
          if slug ~= "" then
            current.slug = current.slug .. slug
          end
          if section ~= "" then
            current.section = (current.section or "") .. " " .. section
          end
          if summary ~= "" then
            current.summary = (current.summary or "") .. " " .. summary
          end
        elseif is_continuation then
          if title ~= "" then
            current.title = current.title .. " " .. title
          end
          if slug ~= "" then
            current.slug = current.slug .. slug
          end
          if section ~= "" then
            current.section = (current.section or "") .. " " .. section
          end
          if summary ~= "" then
            current.summary = (current.summary or "") .. " " .. summary
          end
        elseif title ~= "" or slug ~= "" then
          current = { title = title, slug = slug }
          if section ~= "" then
            current.section = section
          end
          if summary ~= "" then
            current.summary = summary
          end
          items[#items + 1] = current
        elseif current then
          if title ~= "" then
            current.title = current.title .. " " .. title
          end
          if slug ~= "" then
            current.slug = current.slug .. slug
          end
          if section ~= "" then
            current.section = (current.section or "") .. " " .. section
          end
          if summary ~= "" then
            current.summary = (current.summary or "") .. " " .. summary
          end
        end
      end
    end
  end

  for _, item in ipairs(items) do
    if item.title then
      item.title = normalize_whitespace(strip_html(item.title))
    end
    if item.slug then
      item.slug = trim(item.slug):gsub("%s+", "")
    end
    if item.section then
      item.section = normalize_whitespace(strip_html(item.section))
      if item.section == "" then
        item.section = nil
      end
    end
    if item.summary then
      item.summary = normalize_whitespace(strip_html(item.summary))
      if item.summary == "" then
        item.summary = nil
      end
    end
  end

  return items
end

local function parse_item_line(line)
  local slug, title = line:match("^([^%s]+)%s+%-+%s+(.*)$")
  if slug and title then
    return { slug = slug, title = title }
  end
  return nil
end

function M.run_cmd(args, on_success, on_error)
  local config = require("aspire_docs").config
  local cmd = { config.aspire_cmd }
  for _, arg in ipairs(config.default_args or {}) do
    cmd[#cmd + 1] = arg
  end
  for _, arg in ipairs(args or {}) do
    cmd[#cmd + 1] = arg
  end

  local result = vim.system(cmd, { text = true }):wait()
  if result.code == 0 then
    on_success(normalize_lines(result.stdout or ""))
  else
    local err = result.stderr or result.stdout or "Unknown error"
    if on_error then
      on_error(err)
    else
      vim.notify(err, vim.log.levels.ERROR)
    end
  end
end


-- Try to fetch a doc from configured sources (local repo or GitHub raw).
function M.fetch_doc(slug)
  local config = require("aspire_docs").config

  local function try_read_file(path)
    local f = io.open(path, "r")
    if not f then
      return nil
    end
    local content = f:read("*a")
    f:close()
    return normalize_lines(content)
  end

  local candidates = {}

  -- slug may contain slashes already
  table.insert(candidates, slug .. ".mdx")
  table.insert(candidates, slug .. ".md")
  table.insert(candidates, slug .. "/index.mdx")
  table.insert(candidates, slug .. "/index.md")

  -- also try replacing dashes with slashes for nested paths
  local dash_to_slash = slug:gsub("-", "/")
  if dash_to_slash ~= slug then
    table.insert(candidates, dash_to_slash .. ".mdx")
    table.insert(candidates, dash_to_slash .. "/index.mdx")
  end

  -- 1) try local_repo_path if configured
  if config.local_repo_path and config.local_repo_path ~= vim.NIL and config.local_repo_path ~= "" then
    for _, rel in ipairs(candidates) do
      local path = config.local_repo_path
      if path:sub(-1) ~= "/" then
        path = path .. "/"
      end
      local full = path .. rel
      local lines = try_read_file(full)
      if lines then
        return lines
      end
    end
  end

  -- 2) try GitHub raw if configured
  if config.source == "github_raw" and config.github_raw_base and config.github_raw_base ~= "" then
    for _, rel in ipairs(candidates) do
      local url = config.github_raw_base
      if url:sub(-1) ~= "/" then
        url = url .. "/"
      end
      url = url .. rel
      local result = vim.system({ "curl", "-fsSL", url }, { text = true }):wait()
      if result and result.code == 0 and result.stdout and result.stdout ~= "" then
        return normalize_lines(result.stdout)
      end
    end
  end

  return nil
end

-- Turn a slug like "app-host/eventing" or "app-host-eventing" into a readable title
function M.humanize_slug(slug)
  local s = slug:gsub("[-_/]+", " ")
  s = s:gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  -- capitalize first letter of each word
  s = s:gsub("(%a)([%w']*)", function(first, rest)
    return first:upper() .. rest
  end)
  return s
end


-- Build or load an index of remote markdown/mdx files from the GitHub raw base.
-- The index maps slug candidates (filename without extension) to the raw path.
function M.load_remote_index()
  local config = require("aspire_docs").config
  if not config.index or not config.index.enabled then
    return nil
  end

  local cache_file = config.index.cache_file
  if not cache_file or cache_file == vim.NIL then
    cache_file = vim.fn.stdpath("cache") .. "/aspire_docs_index.json"
  end

  -- Use cache if fresh
  local try_read = function(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
  end

  local ok, cached = pcall(try_read, cache_file)
  if ok and cached and cached ~= "" then
  local stat = vim.loop.fs_stat(cache_file)
  if stat then
    local mtime = stat.mtime
    if type(mtime) == "table" then
      mtime = mtime.sec
    end
    if mtime and (os.time() - mtime) < (config.index.ttl_seconds or 86400) then
      local ok2, data = pcall(vim.json.decode, cached)
      if ok2 and type(data) == "table" then
        return data
      end
    end
  end
  end

  -- Fetch the repo tree index via GitHub API (unauthenticated, public repo)
  local api_url = "https://api.github.com/repos/microsoft/aspire.dev/git/trees/main?recursive=1"
  local res = vim.system({ "curl", "-fsSL", api_url }, { text = true }):wait()
  if not res or res.code ~= 0 or not res.stdout then
    return nil
  end

  local ok2, tree = pcall(vim.json.decode, res.stdout)
  if not ok2 or type(tree) ~= "table" or not tree.tree then
    return nil
  end

  local index = {}
  for _, entry in ipairs(tree.tree) do
    if entry.path and entry.type == "blob" then
      if entry.path:match("%.mdx$") or entry.path:match("%.md$") then
        -- derive slug possibilities
        local path = entry.path
        -- only consider docs subtree
        if path:match("^src/frontend/src/content/docs/") then
          local rel = path:gsub("^src/frontend/src/content/docs/", "")
          local base = rel:gsub("%.mdx$", ""):gsub("%.md$", "")
          index[base] = rel
          -- also map dash-joined slug
          local dash = base:gsub("/", "-")
          index[dash] = rel
        end
      end
    end
  end

  -- write cache
  local okw, wf = pcall(function()
    local f = io.open(cache_file, "w")
    if not f then return nil end
    f:write(vim.json.encode(index))
    f:close()
    return true
  end)

  return index
end


-- Return cached index if present and fresh (no network). Nil if not available.
function M.get_cached_index()
  local config = require("aspire_docs").config
  if not config.index or not config.index.enabled then
    return nil
  end
  local cache_file = config.index.cache_file
  if not cache_file or cache_file == vim.NIL then
    cache_file = vim.fn.stdpath("cache") .. "/aspire_docs_index.json"
  end

  local stat = vim.loop.fs_stat(cache_file)
  if not stat then
    return nil
  end
  local mtime = stat.mtime
  if type(mtime) == "table" then
    mtime = mtime.sec
  end
  if not mtime then return nil end
  if (os.time() - mtime) >= (config.index.ttl_seconds or 86400) then
    return nil
  end

  local f = io.open(cache_file, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  if ok and type(data) == "table" then
    return data
  end
  return nil
end


-- Build the remote index asynchronously and cache it. Notifications are shown.
function M.build_remote_index_async()
  local config = require("aspire_docs").config
  if not config.index or not config.index.enabled then
    vim.notify("AspireDocs: index disabled in config", vim.log.levels.INFO)
    return
  end

  local cache_file = config.index.cache_file
  if not cache_file or cache_file == vim.NIL then
    cache_file = vim.fn.stdpath("cache") .. "/aspire_docs_index.json"
  end

  local api_url = "https://api.github.com/repos/microsoft/aspire.dev/git/trees/main?recursive=1"
  vim.notify("AspireDocs: building remote index...", vim.log.levels.INFO)

  local output = {}
  local job = vim.fn.jobstart({ "curl", "-fsSL", api_url }, {
    stdout_buffered = true,
    on_stdout = function(_, data, _)
      if data then output = data end
    end,
    on_stderr = function(_, data, _)
      -- ignore stderr
    end,
    on_exit = function(_, code, _)
      if code ~= 0 then
        vim.schedule(function()
          vim.notify("AspireDocs: failed to fetch remote index (curl exit " .. tostring(code) .. ")", vim.log.levels.ERROR)
        end)
        return
      end
      local raw = table.concat(output, "\n")
      local ok, tree = pcall(vim.json.decode, raw)
      if not ok or type(tree) ~= "table" or not tree.tree then
        vim.schedule(function()
          vim.notify("AspireDocs: failed to parse remote index JSON", vim.log.levels.ERROR)
        end)
        return
      end

      local index = {}
      for _, entry in ipairs(tree.tree) do
        if entry.path and entry.type == "blob" then
          if entry.path:match("%.mdx$") or entry.path:match("%.md$") then
            if entry.path:match("^src/frontend/src/content/docs/") then
              local rel = entry.path:gsub("^src/frontend/src/content/docs/", "")
              local base = rel:gsub("%.mdx$", ""):gsub("%.md$", "")
              index[base] = rel
              index[base:gsub("/", "-")] = rel
            end
          end
        end
      end

      local wrote = false
      local okw, err = pcall(function()
        local f = io.open(cache_file, "w")
        if not f then return end
        f:write(vim.json.encode(index))
        f:close()
        wrote = true
      end)

      vim.schedule(function()
        if wrote then
          local count = 0 for _ in pairs(index) do count = count + 1 end
          vim.notify("AspireDocs: index built (" .. tostring(count) .. " entries)", vim.log.levels.INFO)
        else
          vim.notify("AspireDocs: failed to write index cache", vim.log.levels.WARN)
        end
      end)
    end,
  })
  return job
end

function M.clean_cli_lines(lines, opts)
  local cleaned = {}
  local drop_empty = opts and opts.drop_empty

  for _, line in ipairs(lines) do
    local stripped = strip_ansi(line)
    local trimmed = trim(stripped)
    local skip = trimmed == "Loading documentation..."
      or trimmed:match("^✔")
      or trimmed:match("^Found %d+ documentation pages%.")
      or trimmed:match("^Found %d+ results")

    if not skip then
      if drop_empty and trimmed == "" then
        -- skip empty
      else
        cleaned[#cleaned + 1] = stripped
      end
    end
  end

  return cleaned
end

function M.clean_doc_lines(lines)
  local cleaned = {}
  for _, line in ipairs(lines) do
    local stripped = strip_ansi(line)
    if trim(stripped) ~= "Loading documentation..." then
      cleaned[#cleaned + 1] = stripped
    end
  end
  -- Remove MDX/YAML frontmatter if present
  if #cleaned > 0 and cleaned[1]:match("^%-%-%-") then
    local end_idx = nil
    for i = 2, #cleaned do
      if cleaned[i]:match("^%-%-%-%s*$") then
        end_idx = i
        break
      end
    end
    if end_idx then
      local n = {}
      for i = end_idx + 1, #cleaned do n[#n + 1] = cleaned[i] end
      cleaned = n
    end
  end

  -- Drop MDX import/export lines (they're not useful in plain-text view)
  local filtered = {}
  for _, l in ipairs(cleaned) do
    if not l:match("^%s*import%s+") and not l:match("^%s*export%s+") then
      filtered[#filtered + 1] = l
    end
  end

  -- Work on the full text to replace common MDX JSX components with
  -- markdown-friendly equivalents (Image, Aside, and ::: admonitions).
  local text = table.concat(filtered, "\n")

  -- Remove any <Image ... /> tags entirely (self-closing or paired)
  text = text:gsub("<Image[%s%S]-/>", "")
  text = text:gsub("<Image%s+[^>]->[%s%S]-</Image>", "")

  -- Replace <Aside ...>...</Aside> with a markdown blockquote with a label
  text = text:gsub("<Aside%s+([^>]*)>([%s%S]-)</Aside>", function(attr, body)
    local atype = attr:match('type%s*=%s*"([^"]-)"') or attr:match("type%s*=%s*'([^']-)'") or "note"
    local title = attr:match('title%s*=%s*"([^"]-)"') or attr:match("title%s*=%s*'([^']-)'")
    local label = atype:gsub("^%l", string.upper)
    local header = label
    if title and title ~= "" then
      header = header .. ": " .. title
    end
    -- prefix each body line with '> '
    local out = {}
    for line in tostring(body):gmatch("[^\r\n]+") do
      out[#out + 1] = "> " .. line
    end
    table.insert(out, 1, "> **" .. header .. "**")
    return "\n\n" .. table.concat(out, "\n") .. "\n\n"
  end)

  -- Replace :::tip/admonition blocks with blockquotes
  text = text:gsub(":::(%w+)%s*%[?(.-)%]?(%s*)([%s%S]-):::", function(kind, title, _sp, body)
    local label = kind:gsub("^%l", string.upper)
    local header = label
    if title and title ~= "" then
      header = header .. ": " .. title
    end
    local out = { "> **" .. header .. "**" }
    for line in tostring(body):gmatch("[^\r\n]+") do
      out[#out + 1] = "> " .. line
    end
    return "\n\n" .. table.concat(out, "\n") .. "\n\n"
  end)

  -- Convert <Steps>...</Steps> into a numbered list. Many docs use repeated
  -- "1." markers for each step; capture the chunks between those markers.
  text = text:gsub("<Steps>([%s%S]-)</Steps>", function(body)
    local items = {}
    for part in tostring(body):gmatch("1%%.%s*([^1]*)") do
      local p = trim(part)
      if p ~= "" then
        -- strip any surrounding HTML tags
        p = p:gsub("<[^>]+>", "")
        items[#items + 1] = "1. " .. p
      end
    end
    if #items == 0 then
      -- fallback: just remove the wrapper
      return "\n" .. body .. "\n"
    end
    return "\n" .. table.concat(items, "\n") .. "\n"
  end)

  -- Replace <InstallPackage packageName="..." /> with a simple install hint
  text = text:gsub("<InstallPackage%s+([^/>]-)/>", function(attrs)
    local pkg = attrs:match('packageName%s*=%s*"([^"]-)"') or attrs:match("packageName%s*=%s*'([^']-)'")
    if pkg and pkg ~= "" then
      return "\n\n**Install package:** `" .. pkg .. "`\n\n"
    end
    return ""
  end)

  -- Replace <LearnMore href="..." text="..." /> with a markdown link
  text = text:gsub("<LearnMore%s+([^/>]-)/>", function(attrs)
    local href = attrs:match('href%s*=%s*"([^"]-)"') or attrs:match("href%s*=%s*'([^']-)'")
    local txt = attrs:match('text%s*=%s*"([^"]-)"') or attrs:match("text%s*=%s*'([^']-)'")
    if href and txt then
      return "\n\n[" .. txt .. "](" .. href .. ")\n\n"
    end
    return ""
  end)

  -- Additional component conversions
  -- Convert <TabItem title="...">...</TabItem> into a subheading + content
  text = text:gsub('<TabItem%s+[^>]-title%s*=%s*"([^"]-)"[^>]->([%s%S]-)</TabItem>', function(title, body)
    local out = {}
    out[#out + 1] = "\n\n### " .. trim(title)
    for line in tostring(body):gmatch("[^\r\n]+") do
      out[#out + 1] = line
    end
    return table.concat(out, "\n")
  end)

  -- Remove Tabs/Pivot wrappers but keep inner content
  text = text:gsub('<Tabs[^>]->', '')
  text = text:gsub('</Tabs>', '')
  text = text:gsub('<Pivot[^>]->', '')
  text = text:gsub('</Pivot>', '')

  -- Convert <Project .../> entries into simple list items and strip <Projects>
  text = text:gsub('<Project%s+([^/>]-)/>', function(attrs)
    local title = attrs:match('title%s*=%s*"([^"]-)"') or attrs:match("title%s*=%s*'([^']-)'")
    local href = attrs:match('href%s*=%s*"([^"]-)"') or attrs:match("href%s*=%s*'([^']-)'")
    local line = "- " .. (title or href or "Project")
    if href then line = line .. " (" .. href .. ")" end
    return "\n\n" .. line .. "\n\n"
  end)
  text = text:gsub('<Projects[^>]->', '')
  text = text:gsub('</Projects>', '')

  -- Split back into lines and normalize
  local new_lines = {}
  for l in text:gmatch("[^\r\n]+") do
    new_lines[#new_lines + 1] = l
  end

  return normalize_doc_lines(new_lines)
end

function M.format_doc_lines(lines)
  return normalize_doc_lines(lines)
end

function M.parse_docs_items(lines)
  local cleaned = M.clean_cli_lines(lines, { drop_empty = true })
  local items = parse_table(cleaned)
  if #items > 0 then
    return items
  end

  local fallback = {}
  for _, line in ipairs(cleaned) do
    local item = parse_item_line(line)
    if item then
      fallback[#fallback + 1] = item
    end
  end
  return fallback
end

function M.open_doc(lines, title, open_mode)
  local mode = open_mode or "tab"
  if mode == "tab" then
    vim.cmd("tabnew")
  elseif mode == "split" then
    vim.cmd("split")
  elseif mode == "vsplit" then
    vim.cmd("vsplit")
  else
    vim.cmd("enew")
  end

  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  if title then
    -- Avoid error when a buffer with this name already exists by making the
    -- name unique when necessary. Prefer a human title but append a small
    -- unique suffix (hrtime) if the name is taken.
    local name_to_set = title
    local okbuf = vim.fn.bufnr(name_to_set)
    if okbuf ~= -1 then
      name_to_set = name_to_set .. " - " .. tostring(vim.loop.hrtime())
    end
    pcall(vim.api.nvim_buf_set_name, buf, name_to_set)
  end

  local config = require("aspire_docs").config
  if config.wrap ~= nil then
    vim.api.nvim_buf_set_option(buf, "wrap", config.wrap)
  end
  if config.linebreak ~= nil then
    vim.api.nvim_buf_set_option(buf, "linebreak", config.linebreak)
  end
  if config.breakindent ~= nil then
    vim.api.nvim_buf_set_option(buf, "breakindent", config.breakindent)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

return M
