" repo-grepo.nvim - Fast repository-wide grep plugin for Neovim
" Maintainer: Morass

if exists('g:loaded_repo_grepo')
  finish
endif
let g:loaded_repo_grepo = 1

" User configuration - default banned files/folders (glob patterns)
if !exists('g:repo_grepo_banned_files')
  let g:repo_grepo_banned_files = '*venv*,*__pycache__*,*.git*,*node_modules*,*.pyc,*.pyo,*.pyd,*.so,*.dylib,*.dll,*.mypy_cache*,*.pytest_cache*,*.ruff_cache*,.DS_Store,*.egg-info*,*.tox*,*.coverage*'
endif

" User configuration - default include files (empty = all files)
if !exists('g:repo_grepo_include_files')
  let g:repo_grepo_include_files = ''
endif

" Command to start repo-grepo
command! RepoGrepo lua require('repo-grepo').start()
