" Set 'nocompatible' to ward off unexpected things that your distro might
" have made, as well as sanely reset options when re-sourcing .vimrc
set nocompatible

" Enable syntax highlighting
syntax on

"keep the same indent as the line you're currently on. Useful for READMEs, etc.
set smartindent

" Display the cursor position on the last line of the screen or in the status
" line of a window
set ruler

" copying from visual vim to clipboard
set clipboard=unnamed

" tabs size
set tabstop=4
set shiftwidth=4

" exit insert mode with jj
imap jj <ESC>
set timeoutlen=800

" 2 space tabs for these file endings
autocmd BufRead,BufNewFile *.md,*.html,*.lisp,*.txt,*.scala,*.sbt,*.tex,*.ts,*.yaml,Vagrantfile,*.yml,*.json setlocal tabstop=8 softtabstop=0 expandtab shiftwidth=2 smarttab
" for c sharp files 4 spaces are taps
autocmd BufRead,BufNewFile *.cs,*.py setlocal tabstop=8 softtabstop=0 expandtab shiftwidth=4 smarttab

" slime-vim enable the stuff
let g:slime_target = "neovim"
tnoremap <C-w>h <C-\><C-N><C-w>h
tnoremap <C-w>j <C-\><C-N><C-w>j
tnoremap <C-w>k <C-\><C-N><C-w>k
tnoremap <C-w>l <C-\><C-N><C-w>l
tnoremap <C-w>w <C-\><C-N><C-w>w
tnoremap <C-w><C-w> <C-\><C-N><C-w>w

" let g:slime_vimterminal_config = {"vertical": "1", "term_cols": "72", "term_finish": "close"}
" let g:slime_scala_ammonite = "1"



