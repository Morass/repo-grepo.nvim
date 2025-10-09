local M = {}

local state = {
  main_buf = nil,
  main_win = nil,
  input_bufs = {},
  input_wins = {},
  mode = "input", -- "input", "loading", "file_list", "line_list"

  -- Input state
  pattern = "",
  include_files = "",
  banned_files = "",

  -- Results state
  file_matches = {},
  line_matches = {},
  current_file = "",

  -- Cursor tracking
  active_input = 1, -- 1=pattern, 2=include, 3=banned
}

-- Color definitions using term colors
local function setup_highlights()
  vim.api.nvim_set_hl(0, 'RepoGrepoTitle', { ctermfg = 33 })      -- blue
  vim.api.nvim_set_hl(0, 'RepoGrepoGray', { ctermfg = 245 })      -- gray
  vim.api.nvim_set_hl(0, 'RepoGrepoGreen', { ctermfg = 46 })      -- green
  vim.api.nvim_set_hl(0, 'RepoGrepoYellow', { ctermfg = 226 })    -- yellow
  vim.api.nvim_set_hl(0, 'RepoGrepoRed', { ctermfg = 196 })       -- red
  vim.api.nvim_set_hl(0, 'RepoGrepoCyan', { ctermfg = 51 })       -- cyan
  vim.api.nvim_set_hl(0, 'RepoGrepoMagenta', { ctermfg = 201 })   -- magenta
end

local function create_input_window(row, col, width, height, title)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)

  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = title,
    title_pos = 'center',
    zindex = 51  -- Higher than main window
  }

  local win = vim.api.nvim_open_win(buf, false, opts)

  return buf, win
end

local function create_main_window()
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)

  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    zindex = 50  -- Base layer
  }

  local win = vim.api.nvim_open_win(buf, true, opts)

  return buf, win, width, height, row, col
end

function M.render_input_screen()
  state.mode = "input"

  -- Close existing windows
  for _, win in ipairs(state.input_wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  state.input_wins = {}
  state.input_bufs = {}

  -- Create main overlay
  if not state.main_win or not vim.api.nvim_win_is_valid(state.main_win) then
    state.main_buf, state.main_win = create_main_window()
  end

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local base_row = math.floor((vim.o.lines - height) / 2)
  local base_col = math.floor((vim.o.columns - width) / 2)

  -- Render instructions in main window
  local lines = {
    "",
    "  Repo Grepo - Fast Repository Search",
    "",
    "  Shortcuts: Enter = Search | Esc/q = Close | Up/Down = Switch Input",
    "",
  }

  vim.api.nvim_buf_set_option(state.main_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(state.main_buf, 0, -1, false, lines)
  vim.api.nvim_buf_add_highlight(state.main_buf, -1, 'RepoGrepoTitle', 1, 0, -1)
  vim.api.nvim_buf_add_highlight(state.main_buf, -1, 'RepoGrepoGray', 3, 0, -1)
  vim.api.nvim_buf_set_option(state.main_buf, 'modifiable', false)

  -- Create 3 input sub-windows
  local input_height = 3
  local input_width = width - 10
  local start_row = base_row + 7
  local start_col = base_col + 5

  -- Pattern input
  local buf1, win1 = create_input_window(
    start_row,
    start_col,
    input_width,
    input_height,
    " Search Pattern (Regex) "
  )
  vim.api.nvim_buf_set_lines(buf1, 0, -1, false, {state.pattern})
  table.insert(state.input_bufs, buf1)
  table.insert(state.input_wins, win1)

  -- Include files input
  local buf2, win2 = create_input_window(
    start_row + input_height + 2,
    start_col,
    input_width,
    input_height,
    " Include Files (comma-separated regexes, empty = all) "
  )
  vim.api.nvim_buf_set_lines(buf2, 0, -1, false, {state.include_files})
  table.insert(state.input_bufs, buf2)
  table.insert(state.input_wins, win2)

  -- Banned files input
  local buf3, win3 = create_input_window(
    start_row + (input_height + 2) * 2,
    start_col,
    input_width,
    input_height,
    " Banned Files/Folders (comma-separated regexes) "
  )
  vim.api.nvim_buf_set_lines(buf3, 0, -1, false, {state.banned_files})
  table.insert(state.input_bufs, buf3)
  table.insert(state.input_wins, win3)

  -- Force redraw to show all windows
  vim.cmd('redraw')

  -- Focus on the active input window and enter insert mode
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(state.input_wins[state.active_input]) then
      vim.api.nvim_set_current_win(state.input_wins[state.active_input])
      local lines = vim.api.nvim_buf_get_lines(state.input_bufs[state.active_input], 0, 1, false)
      local line_len = #(lines[1] or "")
      vim.api.nvim_win_set_cursor(state.input_wins[state.active_input], {1, line_len})
      vim.cmd('startinsert!')
    end
  end)
end

function M.render_loading_screen()
  state.mode = "loading"

  -- Close input windows
  for _, win in ipairs(state.input_wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  state.input_wins = {}

  local lines = {
    "",
    "",
    "     ___                   _     _             ",
    "    / __| ___ __ _ _ _ __ | |_  (_)_ _  __ _   ",
    "    \\__ \\/ -_) _` | '_/ _|| ' \\ | | ' \\/ _` |  ",
    "    |___/\\___\\__,_|_| \\__||_||_||_|_||_\\__, |  ",
    "                                       |___/   ",
    "",
    "",
    "           Please wait, searching files...",
    "",
  }

  vim.api.nvim_buf_set_option(state.main_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(state.main_buf, 0, -1, false, lines)

  for i = 2, 7 do
    vim.api.nvim_buf_add_highlight(state.main_buf, -1, 'RepoGrepoCyan', i, 0, -1)
  end
  vim.api.nvim_buf_add_highlight(state.main_buf, -1, 'RepoGrepoGray', 9, 0, -1)

  vim.api.nvim_buf_set_option(state.main_buf, 'modifiable', false)
  vim.cmd('redraw')
end

function M.render_file_list()
  state.mode = "file_list"

  local lines = {
    "",
    "  Files matching pattern: '" .. state.pattern .. "'",
    "",
    "  Enter = View Lines | Esc = Back to Search",
    "",
  }

  if #state.file_matches == 0 then
    table.insert(lines, "")
    table.insert(lines, "  No files found matching your criteria.")
    table.insert(lines, "")
  else
    for i, match in ipairs(state.file_matches) do
      local line = string.format("  [%d] %s", match.count, match.path)
      table.insert(lines, line)
    end
  end

  vim.api.nvim_buf_set_option(state.main_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(state.main_buf, 0, -1, false, lines)

  vim.api.nvim_buf_add_highlight(state.main_buf, -1, 'RepoGrepoTitle', 1, 0, -1)
  vim.api.nvim_buf_add_highlight(state.main_buf, -1, 'RepoGrepoGray', 3, 0, -1)

  for i = 1, #state.file_matches do
    local line_idx = 5 + i - 1
    vim.api.nvim_buf_add_highlight(state.main_buf, -1, 'RepoGrepoYellow', line_idx, 2, 2 + #tostring(state.file_matches[i].count) + 2)
    vim.api.nvim_buf_add_highlight(state.main_buf, -1, 'RepoGrepoGreen', line_idx, 6 + #tostring(state.file_matches[i].count), -1)
  end

  if #state.file_matches == 0 then
    vim.api.nvim_buf_add_highlight(state.main_buf, -1, 'RepoGrepoRed', 6, 0, -1)
  end

  vim.api.nvim_buf_set_option(state.main_buf, 'modifiable', false)

  if #state.file_matches > 0 then
    vim.api.nvim_win_set_cursor(state.main_win, {6, 0})
  end
end

function M.render_line_list()
  state.mode = "line_list"

  local lines = {
    "",
    "  File: " .. state.current_file,
    "",
    "  Enter = Jump to Line | Esc = Back to Files",
    "",
  }

  if #state.line_matches == 0 then
    table.insert(lines, "")
    table.insert(lines, "  No matching lines found.")
    table.insert(lines, "")
  else
    for _, match in ipairs(state.line_matches) do
      local line = string.format("  %d: %s", match.line_number, match.content)
      table.insert(lines, line)
    end
  end

  vim.api.nvim_buf_set_option(state.main_buf, 'modifiable', true)
  vim.api.nvim_buf_set_lines(state.main_buf, 0, -1, false, lines)

  vim.api.nvim_buf_add_highlight(state.main_buf, -1, 'RepoGrepoCyan', 1, 0, -1)
  vim.api.nvim_buf_add_highlight(state.main_buf, -1, 'RepoGrepoGray', 3, 0, -1)

  for i = 1, #state.line_matches do
    local line_idx = 5 + i - 1
    local line_num_str = tostring(state.line_matches[i].line_number) .. ":"
    vim.api.nvim_buf_add_highlight(state.main_buf, -1, 'RepoGrepoMagenta', line_idx, 2, 2 + #line_num_str)
  end

  vim.api.nvim_buf_set_option(state.main_buf, 'modifiable', false)

  if #state.line_matches > 0 then
    vim.api.nvim_win_set_cursor(state.main_win, {6, 0})
  end
end

function M.get_state()
  return state
end

function M.setup()
  setup_highlights()
end

function M.close()
  for _, win in ipairs(state.input_wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  if state.main_win and vim.api.nvim_win_is_valid(state.main_win) then
    vim.api.nvim_win_close(state.main_win, true)
  end

  state.main_buf = nil
  state.main_win = nil
  state.input_bufs = {}
  state.input_wins = {}
end

return M
