package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local util = require("aspire_docs.util")

local function read_file(path)
  local file, err = io.open(path, "r")
  if not file then
    error(err)
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function normalize_lines(output)
  local lines = {}
  for line in output:gmatch("[^\r\n]+") do
    lines[#lines + 1] = line
  end
  return lines
end

local function format_items(label, items)
  local lines = { label, string.rep("-", #label) }
  for index, item in ipairs(items) do
    local parts = {
      string.format("%02d", index),
      item.title or "",
      item.slug or "",
      item.section or "",
      item.summary or "",
    }
    lines[#lines + 1] = table.concat(parts, " | ")
  end
  lines[#lines + 1] = ""
  return lines
end

local function print_items(label, items)
  local lines = format_items(label, items)
  for _, line in ipairs(lines) do
    print(line)
  end
end

local function read_expected(path)
  local ok, content = pcall(read_file, path)
  if not ok then
    return nil
  end
  return content
end

local function parse_args()
  local args = {
    expect = false,
  }
  for _, value in ipairs(arg or {}) do
    if value == "--expect" then
      args.expect = true
    end
  end
  return args
end

local list_output = read_file("scripts/fixtures/docs_list.txt")
local search_output = read_file("scripts/fixtures/docs_search.txt")

local list_lines = normalize_lines(list_output)
local search_lines = normalize_lines(search_output)

local list_items = util.parse_docs_items(list_lines)
local search_items = util.parse_docs_items(search_lines)
local list_output_lines = format_items("List Items", list_items)
local search_output_lines = format_items("Search Items", search_items)

local args = parse_args()
if args.expect then
  local expected = read_expected("scripts/fixtures/expected_output.txt")
  if not expected then
    io.stderr:write("Expected output file not found. Run without --expect first.\n")
    os.exit(1)
  end
  local actual = table.concat(list_output_lines, "\n") .. table.concat(search_output_lines, "\n")
  if expected ~= actual then
    io.stderr:write("Fixture output mismatch. Update scripts/fixtures/expected_output.txt if needed.\n")
    os.exit(1)
  end
else
  for _, line in ipairs(list_output_lines) do
    print(line)
  end
  for _, line in ipairs(search_output_lines) do
    print(line)
  end
end
