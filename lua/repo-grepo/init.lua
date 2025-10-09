local M = {}
local ui = require('repo-grepo.ui')

local function get_git_root()
  local current_file = vim.fn.expand('%:p')
  local current_dir = vim.fn.fnamemodify(current_file, ':h')

  -- Try to find .git directory
  local dir = current_dir
  for _ = 1, 50 do -- limit depth to avoid infinite loop
    local git_dir = dir .. '/.git'
    if vim.fn.isdirectory(git_dir) == 1 then
      return dir
    end
    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then
      break
    end
    dir = parent
  end

  return nil
end

local function get_plugin_path()
  local str = debug.getinfo(1, "S").source:sub(2)
  local plugin_path = vim.fn.fnamemodify(str, ':h:h:h')
  return plugin_path
end

local function run_search(root_path, pattern, include_files, banned_files)
  local plugin_path = get_plugin_path()
  local search_bin = plugin_path .. '/bin/repo-grepo-search'

  -- Check if binary exists
  if vim.fn.filereadable(search_bin) ~= 1 then
    vim.api.nvim_err_writeln("Error: Search binary not found. Please run 'make' in the plugin directory: " .. plugin_path)
    return nil
  end

  -- Escape arguments for shell
  local cmd = string.format(
    '%s files %s %s %s %s',
    vim.fn.shellescape(search_bin),
    vim.fn.shellescape(root_path),
    vim.fn.shellescape(pattern),
    vim.fn.shellescape(include_files),
    vim.fn.shellescape(banned_files)
  )

  local output = vim.fn.system(cmd)
  local matches = {}

  for line in output:gmatch("[^\r\n]+") do
    if line:match("^ERROR:") then
      vim.api.nvim_err_writeln(line)
      return nil
    end
    local path, count = line:match("^(.+)|(%d+)$")
    if path and count then
      table.insert(matches, {
        path = path,
        count = tonumber(count)
      })
    end
  end

  return matches
end

local function run_line_search(file_path, pattern, callback)
  local plugin_path = get_plugin_path()
  local search_bin = plugin_path .. '/bin/repo-grepo-search'

  local cmd = {
    search_bin,
    'lines',
    file_path,
    pattern
  }

  local output_lines = {}

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(output_lines, line)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" and line:match("^ERROR:") then
            vim.api.nvim_err_writeln(line)
          end
        end
      end
    end,
    on_exit = function(_, exit_code, _)
      if exit_code ~= 0 then
        vim.schedule(function()
          vim.api.nvim_err_writeln("Error: Search command failed with exit code " .. exit_code)
          callback(nil)
        end)
        return
      end

      local matches = {}
      for _, line in ipairs(output_lines) do
        local line_num, content = line:match("^(%d+)|(.*)$")
        if line_num and content then
          table.insert(matches, {
            line_number = tonumber(line_num),
            content = content
          })
        end
      end

      vim.schedule(function()
        callback(matches)
      end)
    end
  })
end

local function setup_keymaps()
  local state = ui.get_state()

  -- Input mode keymaps
  if state.mode == "input" then
    local function switch_window_down()
      -- Save current input
      local current_buf = state.input_bufs[state.active_input]
      local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
      if state.active_input == 1 then
        state.pattern = lines[1] or ""
      elseif state.active_input == 2 then
        state.include_files = lines[1] or ""
      elseif state.active_input == 3 then
        state.banned_files = lines[1] or ""
      end

      -- Switch to next input (circular)
      state.active_input = state.active_input + 1
      if state.active_input > 3 then
        state.active_input = 1
      end

      if vim.api.nvim_win_is_valid(state.input_wins[state.active_input]) then
        vim.api.nvim_set_current_win(state.input_wins[state.active_input])
        local buf_lines = vim.api.nvim_buf_get_lines(state.input_bufs[state.active_input], 0, 1, false)
        vim.api.nvim_win_set_cursor(state.input_wins[state.active_input], {1, #(buf_lines[1] or "")})
        -- Use vim.schedule to ensure insert mode is re-entered after window switch
        vim.schedule(function()
          vim.cmd('startinsert!')
        end)
      end
    end

    local function switch_window_up()
      -- Save current input
      local current_buf = state.input_bufs[state.active_input]
      local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
      if state.active_input == 1 then
        state.pattern = lines[1] or ""
      elseif state.active_input == 2 then
        state.include_files = lines[1] or ""
      elseif state.active_input == 3 then
        state.banned_files = lines[1] or ""
      end

      -- Switch to previous input (circular)
      state.active_input = state.active_input - 1
      if state.active_input < 1 then
        state.active_input = 3
      end

      if vim.api.nvim_win_is_valid(state.input_wins[state.active_input]) then
        vim.api.nvim_set_current_win(state.input_wins[state.active_input])
        local buf_lines = vim.api.nvim_buf_get_lines(state.input_bufs[state.active_input], 0, 1, false)
        vim.api.nvim_win_set_cursor(state.input_wins[state.active_input], {1, #(buf_lines[1] or "")})
        -- Use vim.schedule to ensure insert mode is re-entered after window switch
        vim.schedule(function()
          vim.cmd('startinsert!')
        end)
      end
    end

    for idx, buf in ipairs(state.input_bufs) do
      -- Down arrow to switch to next window (circular) - insert mode
      vim.keymap.set('i', '<Down>', switch_window_down, {
        buffer = buf,
        noremap = true,
        silent = true
      })

      -- Up arrow to switch to previous window (circular) - insert mode
      vim.keymap.set('i', '<Up>', switch_window_up, {
        buffer = buf,
        noremap = true,
        silent = true
      })

      -- Down arrow - normal mode
      vim.keymap.set('n', '<Down>', switch_window_down, {
        buffer = buf,
        noremap = true,
        silent = true
      })

      -- Up arrow - normal mode
      vim.keymap.set('n', '<Up>', switch_window_up, {
        buffer = buf,
        noremap = true,
        silent = true
      })

      -- Ctrl+n as alternative to Down (both modes)
      vim.keymap.set('i', '<C-n>', switch_window_down, {
        buffer = buf,
        noremap = true,
        silent = true
      })

      vim.keymap.set('n', '<C-n>', switch_window_down, {
        buffer = buf,
        noremap = true,
        silent = true
      })

      -- Enter to search
      vim.keymap.set('i', '<CR>', function()
        -- Save all inputs
        for i = 1, 3 do
          local lines = vim.api.nvim_buf_get_lines(state.input_bufs[i], 0, -1, false)
          local text = lines[1] or ""
          if i == 1 then
            state.pattern = text
          elseif i == 2 then
            state.include_files = text
          elseif i == 3 then
            state.banned_files = text
          end
        end

        -- Validate pattern
        if state.pattern == "" then
          vim.api.nvim_err_writeln("Error: Search pattern cannot be empty")
          return
        end

        vim.cmd('stopinsert')

        -- Get git root
        local root = get_git_root()
        if not root then
          vim.api.nvim_err_writeln("Error: Not in a git repository")
          return
        end

        -- Show loading screen
        ui.render_loading_screen()

        -- Run search
        vim.defer_fn(function()
          local matches = run_search(root, state.pattern, state.include_files, state.banned_files)
          if matches then
            state.file_matches = matches
            ui.render_file_list()
            setup_keymaps()
          else
            ui.close()
          end
        end, 100)
      end, {
        buffer = buf,
        noremap = true,
        silent = true
      })

      -- Escape to close (insert mode)
      vim.keymap.set('i', '<Esc>', function()
        vim.cmd('stopinsert')
        ui.close()
      end, {
        buffer = buf,
        noremap = true,
        silent = true
      })

      -- Escape and q to close (normal mode)
      vim.keymap.set('n', '<Esc>', function()
        ui.close()
      end, {
        buffer = buf,
        noremap = true,
        silent = true
      })

      vim.keymap.set('n', 'q', function()
        ui.close()
      end, {
        buffer = buf,
        noremap = true,
        silent = true
      })
    end
  end

  -- File list mode keymaps
  if state.mode == "file_list" then
    vim.api.nvim_buf_set_keymap(state.main_buf, 'n', '<Esc>', '', {
      noremap = true,
      silent = true,
      callback = function()
        ui.render_input_screen()
        setup_keymaps()
      end
    })

    vim.api.nvim_buf_set_keymap(state.main_buf, 'n', 'q', '', {
      noremap = true,
      silent = true,
      callback = function()
        ui.render_input_screen()
        setup_keymaps()
      end
    })

    vim.api.nvim_buf_set_keymap(state.main_buf, 'n', '<CR>', '', {
      noremap = true,
      silent = true,
      callback = function()
        if #state.file_matches == 0 then
          return
        end

        local cursor = vim.api.nvim_win_get_cursor(state.main_win)
        local row = cursor[1]
        local file_index = row - 5

        if file_index >= 1 and file_index <= #state.file_matches then
          local match = state.file_matches[file_index]
          state.current_file = match.path

          -- Get git root
          local root = get_git_root()
          if not root then
            vim.api.nvim_err_writeln("Error: Not in a git repository")
            return
          end

          local full_path = root .. '/' .. match.path

          -- Show loading briefly
          ui.render_loading_screen()

          -- Run async line search
          run_line_search(full_path, state.pattern, function(line_matches)
            if line_matches then
              state.line_matches = line_matches
              ui.render_line_list()
              setup_keymaps()
            else
              ui.close()
            end
          end)
        end
      end
    })
  end

  -- Line list mode keymaps
  if state.mode == "line_list" then
    vim.api.nvim_buf_set_keymap(state.main_buf, 'n', '<Esc>', '', {
      noremap = true,
      silent = true,
      callback = function()
        ui.render_file_list()
        setup_keymaps()
      end
    })

    vim.api.nvim_buf_set_keymap(state.main_buf, 'n', 'q', '', {
      noremap = true,
      silent = true,
      callback = function()
        ui.render_file_list()
        setup_keymaps()
      end
    })

    vim.api.nvim_buf_set_keymap(state.main_buf, 'n', '<CR>', '', {
      noremap = true,
      silent = true,
      callback = function()
        if #state.line_matches == 0 then
          return
        end

        local cursor = vim.api.nvim_win_get_cursor(state.main_win)
        local row = cursor[1]
        local line_index = row - 5

        if line_index >= 1 and line_index <= #state.line_matches then
          local match = state.line_matches[line_index]

          -- Get git root and full path
          local root = get_git_root()
          if not root then
            vim.api.nvim_err_writeln("Error: Not in a git repository")
            return
          end

          local full_path = root .. '/' .. state.current_file

          -- Close UI
          ui.close()

          -- Open file at line
          vim.cmd('edit ' .. vim.fn.fnameescape(full_path))
          vim.api.nvim_win_set_cursor(0, {match.line_number, 0})
          vim.cmd('normal! zz') -- Center the line
        end
      end
    })
  end
end

function M.start()
  -- Check if in git repo
  local root = get_git_root()
  if not root then
    vim.api.nvim_err_writeln("Error: Not in a git repository")
    return
  end

  ui.setup()

  -- Initialize with default banned files
  local state = ui.get_state()
  if state.banned_files == "" then
    state.banned_files = vim.g.repo_grepo_banned_files or "*venv*,*__pycache__*,*.git*,*node_modules*,*.pyc"
  end
  if state.include_files == "" then
    state.include_files = vim.g.repo_grepo_include_files or ""
  end

  ui.render_input_screen()
  setup_keymaps()
end

return M
