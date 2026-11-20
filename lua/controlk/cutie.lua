-- Geometry of the cutie style, after Qt Creator's locator: the prompt in the bottom-left corner,
-- right above the status line, the list above it and the preview to its right. Pure Lua: the
-- picker passes the screen size and the window list in, so this works without a UI.
--
-- A box is { row, col, width, height }: 0-based screen position and size, borders included.

local M = {}

local DEFAULT_WIDTH = 60
local PROMPT_HEIGHT = 3 -- one line plus its border
local MIN_PREVIEW = 20

--- Where the prompt, list and preview go.
---@param screen { columns: integer, lines: integer, cmdheight: integer, laststatus: integer }
---@param opts { width: integer, height: integer, preview: boolean }
---@return { prompt: table, results: table, preview: table|nil }
function M.geometry(screen, opts)
  -- The last row above the status line (or above the command line, without a status line).
  local bottom = screen.lines - screen.cmdheight - (screen.laststatus > 0 and 1 or 0) - 1
  local width = math.min(opts.width, screen.columns)

  local prompt =
    { row = bottom - PROMPT_HEIGHT + 1, col = 0, width = width, height = PROMPT_HEIGHT }
  -- The list fills the room above the prompt, up to its height, and keeps at least one row.
  local height = math.max(3, math.min(opts.height + 2, prompt.row))
  local results =
    { row = math.max(0, prompt.row - height), col = 0, width = width, height = height }

  local preview
  local preview_width = screen.columns - width
  if opts.preview and preview_width >= MIN_PREVIEW then
    preview = {
      row = results.row,
      col = width,
      width = preview_width,
      height = results.height + prompt.height,
    }
  end
  return { prompt = prompt, results = results, preview = preview }
end

--- The width of a sidebar split on the left: the leftmost window that is not floating, starts
--- at column 0 and is narrower than half the screen. Any file tree plugin, or a plain split.
---@param wins { col: integer, width: integer, floating: boolean }[]
---@param columns integer
---@return integer|nil
function M.sidebar_width(wins, columns)
  for _, win in ipairs(wins) do
    if not win.floating and win.col == 0 and win.width < columns / 2 then
      return win.width
    end
  end
  return nil
end

--- cutie.width as a number of columns: "auto" measures a sidebar, else 60. Never wider than
--- the screen.
---@param width integer|"auto"
---@param wins { col: integer, width: integer, floating: boolean }[]
---@param columns integer
---@return integer
function M.resolve_width(width, wins, columns)
  if width == "auto" then
    width = M.sidebar_width(wins, columns) or DEFAULT_WIDTH
  end
  return math.min(width, columns)
end

return M
