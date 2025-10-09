# repo-grepo.nvim

⚡ Blazingly fast repository-wide grep plugin for Neovim with a beautiful multi-window interface.

## Features

- **Lightning Fast**: C++ backend for efficient file traversal and regex matching
- **Multi-Window Interface**: Clean overlay UI with separate input windows
- **Git-Aware**: Automatically finds repository root
- **Smart Filtering**: Include/exclude files with regex patterns
- **Interactive Navigation**: Browse matches by file, then by line
- **Jump to Context**: Open files directly at matching lines

## Requirements

- Neovim 0.5+
- C++17 compatible compiler (g++, clang++)
- Git repository

## Installation

### Using vim-plug

```vim
Plug 'Morass/repo-grepo.nvim', { 'do': 'make' }
```

### Using packer.nvim

```lua
use {
  'Morass/repo-grepo.nvim',
  run = 'make'
}
```

### Manual Installation

```bash
cd ~/.vim/plugged  # or your plugin directory
git clone https://github.com/Morass/repo-grepo.nvim.git
cd repo-grepo.nvim
make
```

## Usage

Run the command:
```vim
:RepoGrepo
```

### Interface

The plugin opens with three input windows:

1. **Search Pattern**: Enter your regex pattern (required)
2. **Include Files**: Comma-separated regexes to filter files (optional, empty = all files)
3. **Banned Files/Folders**: Comma-separated regexes to exclude files/folders (default: `*venv*,__pycache__`)

### Shortcuts

#### Input Screen
- `Enter` - Start search
- `Up`/`Down` arrows - Switch between input windows (circular)
- `Ctrl+n` - Alternative to Down arrow
- `Esc` or `q` - Close plugin

#### File List Screen
- `Enter` - View matching lines in selected file
- `Esc` or `q` - Back to search input

#### Line List Screen
- `Enter` - Open file at selected line
- `Esc` or `q` - Back to file list

## Configuration

Set default values in your `init.vim` or `init.lua`:

```vim
" Default banned files/folders (comma-separated regexes)
let g:repo_grepo_banned_files = '*venv*,__pycache__,*.pyc,node_modules'

" Default include files (comma-separated regexes, empty = all)
let g:repo_grepo_include_files = ''
```

Or in Lua:

```lua
vim.g.repo_grepo_banned_files = '*venv*,__pycache__,*.pyc,node_modules'
vim.g.repo_grepo_include_files = ''
```

## How It Works

1. **Input Phase**: Enter search criteria in multi-window overlay
2. **Search Phase**: C++ binary scans repository recursively
3. **File List**: Results sorted by match count, then alphabetically
4. **Line List**: Shows all matching lines with line numbers
5. **Jump**: Opens file at exact line in your editor

## Performance

The C++ backend uses:
- Optimized regex compilation with `std::regex::optimize`
- Efficient filesystem traversal with `std::filesystem`
- Binary file detection to skip non-text files
- Smart filtering to minimize files scanned

## Troubleshooting

### "Search binary not found" error

The C++ backend wasn't compiled. Run:
```bash
cd ~/.vim/plugged/repo-grepo.nvim  # adjust path as needed
make
```

### "Not in a git repository" error

This plugin requires you to be inside a git repository. Initialize one with:
```bash
git init
```

## License

MIT

## Author

Morass
