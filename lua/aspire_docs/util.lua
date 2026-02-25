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
  return M.format_doc_lines(cleaned)
end

function M.format_doc_lines(lines)
  local out = {}
  local in_code = false

  for _, line in ipairs(lines) do
    if line:match("^%s*```") then
      in_code = not in_code
      out[#out + 1] = line
    elseif in_code then
      out[#out + 1] = line
    else
      local current = line
      current = current:gsub("%s%[Section titled.-%]%([^)]+%)", "")
      current = current:gsub("(%S)%s(#+%s)", "%1\n\n%2")
      current = current:gsub("(%S)%s(> )", "%1\n\n%2")
      current = current:gsub("(%S)%s(!%[)", "%1\n\n%2")
      current = current:gsub("(%S)%s(```)", "%1\n\n%2")
      current = current:gsub("%s%*%s", "\n- ")

      for chunk in current:gmatch("[^\n]+") do
        out[#out + 1] = chunk
      end
    end
  end

  return out
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
    vim.api.nvim_buf_set_name(buf, title)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

return M
