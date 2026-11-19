local registry = require("controlk.sources")

local M = {}

-- Every style name and what kind of style it is. A layout style sets Telescope's
-- layout_strategy; a theme style applies telescope.themes.get_<name>; "default" sets neither.
M.STYLES = {
  default = "default",
  horizontal = "layout",
  vertical = "layout",
  flex = "layout",
  center = "layout",
  bottom_pane = "layout",
  current_buffer = "layout",
  ivy = "theme",
  dropdown = "theme",
  cursor = "theme",
  cutie = "cutie",
}

-- Styles that work but do not suit a locator: the list is too narrow, it follows the
-- cursor, or it covers the window you work in.
local UNFIT = { cursor = true, current_buffer = true }

local CUTIE_WIDTH, CUTIE_HEIGHT = 40, 15

M.defaults = {
  -- Normal-mode key for the locator, mapped when the extension loads. A key you
  -- have mapped yourself is never taken over. false maps nothing.
  keymap = "<C-k>",
  -- "default" (Telescope's own defaults), a Telescope layout or theme, or "cutie".
  style = "default",
  -- Passed to Telescope as is, for the Telescope styles. Ignored by cutie.
  layout_config = nil,
  -- The Qt Creator style. width: columns of the prompt and the list, or "auto" to match a
  -- sidebar split on the left. height: rows of the list.
  cutie = { width = CUTIE_WIDTH, height = CUTIE_HEIGHT, preview = true },
  -- Prefix per source. A prefix must be followed by a space ("c Widget").
  -- Set a source to false to drop its prefix; it stays reachable through
  -- default_sources if it is listed there, otherwise it is unreachable.
  prefixes = {
    buffers = "o",
    files = "a",
    lines = "l",
    filesystem = "f",
    help = "h",
    -- Lists the prefixes; picking one puts it in the prompt.
    prefixes = "?",
    commands = "t",
    marks = "b",
    eval = "=",
    shell = "!",
    web = "r",
    lsp_symbols = ":",
    lsp_classes = "c",
    lsp_functions = "m",
    lsp_document = ".",
    cmake_targets = "cm",
    cmake_open = "cmo",
    cmake_tests = "ct",
  },
  -- Sources merged together when no prefix is typed.
  default_sources = { "buffers", "files", "lines" },
  -- Source ids removed entirely (no prefix, not in the default list).
  disabled = {},
  lsp = {
    -- workspace/symbol queries need at least this many characters.
    min_query = 1,
  },
  cmake = {
    -- Build directory, absolute or relative to the project root.
    -- nil means: the first build directory with a CMakeCache.txt.
    build_dir = nil,
  },
  web = {
    -- name -> URL with %s where the query goes. Set an engine to false to remove it.
    engines = {
      Google = "https://www.google.com/search?q=%s",
      DuckDuckGo = "https://duckduckgo.com/?q=%s",
      Wikipedia = "https://en.wikipedia.org/w/index.php?search=%s",
      cppreference = "https://en.cppreference.com/mwiki/index.php?search=%s",
    },
  },
}

--- The style to use for a name, and a warning to show, if any.
---@param name any
---@return string style
---@return string|nil message
function M.check_style(name)
  if M.STYLES[name] == nil then
    return "default", ("unknown style '%s'; using 'default'"):format(tostring(name))
  end
  if UNFIT[name] then
    return name, ("style '%s' does not suit a locator; see :h controlk-styles"):format(name)
  end
  return name, nil
end

local function is_positive_integer(value)
  return type(value) == "number" and value >= 1 and value == math.floor(value)
end

local function is_valid_prefix(prefix)
  return type(prefix) == "string" and prefix ~= "" and not prefix:find("%s")
end

--- Merge user options over the defaults and validate the result.
---@param user table|nil
---@return table config resolved configuration (prefix_map and default_sources included)
---@return string[] errors problems found, empty when the configuration is valid
function M.resolve(user)
  user = user or {}
  local cfg = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user)

  -- Lists replace the default list instead of merging into it.
  for _, key in ipairs({ "default_sources", "disabled" }) do
    if user[key] then
      cfg[key] = vim.deepcopy(user[key])
    end
  end
  for name, url in pairs(cfg.web.engines) do
    if not url then
      cfg.web.engines[name] = nil
    end
  end

  local errors = {}
  local style, message = M.check_style(cfg.style)
  cfg.style = style
  if message then
    table.insert(errors, message)
  end
  if type(cfg.cutie) ~= "table" then
    table.insert(errors, ("invalid cutie: %s"):format(vim.inspect(cfg.cutie)))
    cfg.cutie = vim.deepcopy(M.defaults.cutie)
  end
  if cfg.layout_config ~= nil and type(cfg.layout_config) ~= "table" then
    table.insert(errors, ("invalid layout_config: %s"):format(vim.inspect(cfg.layout_config)))
    cfg.layout_config = nil
  end
  if type(cfg.cutie.preview) ~= "boolean" then
    table.insert(errors, ("invalid cutie.preview: %s"):format(vim.inspect(cfg.cutie.preview)))
    cfg.cutie.preview = true
  end
  if cfg.cutie.width ~= "auto" and not is_positive_integer(cfg.cutie.width) then
    table.insert(errors, ("invalid cutie.width: %s"):format(vim.inspect(cfg.cutie.width)))
    cfg.cutie.width = CUTIE_WIDTH
  end
  if not is_positive_integer(cfg.cutie.height) then
    table.insert(errors, ("invalid cutie.height: %s"):format(vim.inspect(cfg.cutie.height)))
    cfg.cutie.height = CUTIE_HEIGHT
  end
  if cfg.keymap ~= false and (type(cfg.keymap) ~= "string" or cfg.keymap == "") then
    table.insert(errors, ("invalid keymap: %s"):format(vim.inspect(cfg.keymap)))
  end
  local known = registry.by_id

  local function is_disabled(id)
    return vim.tbl_contains(cfg.disabled, id)
  end

  for id in pairs(cfg.prefixes) do
    if not known[id] then
      table.insert(errors, ("unknown source '%s' in prefixes"):format(id))
    end
  end
  for _, id in ipairs(cfg.disabled) do
    if not known[id] then
      table.insert(errors, ("unknown source '%s' in disabled"):format(id))
    end
  end

  local ids = vim.tbl_keys(known)
  table.sort(ids)
  local prefix_map = {}
  for _, id in ipairs(ids) do
    local prefix = cfg.prefixes[id]
    if prefix ~= nil and prefix ~= false then
      if not is_valid_prefix(prefix) then
        table.insert(errors, ("invalid prefix for '%s': %s"):format(id, vim.inspect(prefix)))
      elseif not is_disabled(id) then
        if prefix_map[prefix] then
          table.insert(
            errors,
            ("prefix '%s' is used by both '%s' and '%s'; keeping '%s'"):format(
              prefix,
              prefix_map[prefix],
              id,
              prefix_map[prefix]
            )
          )
        else
          prefix_map[prefix] = id
        end
      end
    end
  end

  local defaults = {}
  for _, id in ipairs(cfg.default_sources) do
    if not known[id] then
      table.insert(errors, ("unknown source '%s' in default_sources"):format(id))
    elseif not is_disabled(id) then
      table.insert(defaults, id)
    end
  end

  cfg.default_sources = defaults
  cfg.prefix_map = prefix_map
  return cfg, errors
end

return M
