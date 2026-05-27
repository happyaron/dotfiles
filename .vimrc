" Description: vim runtime configure file
" vim: ft=vim foldmethod=marker

set nocompatible
let mapleader="\<Space>"
set timeoutlen=1000 ttimeoutlen=0

if filereadable( $HOME . '/.vimrc.plug'  )
    source  $HOME/.vimrc.plug
endif

filetype plugin indent on
syntax on

" {{{ general settings
set mouse=""            " disable mouse
set history=50		" keep 50 lines of command line history
" keep record of editing information for cursor restore and more
set viminfo='10,"100,:20,%,n~/.viminfo

set background=dark
set notitle             " do not set xterm dynamic title

" never use background color erase
let &t_ut=''

" disable bell
set noeb vb t_vb=

" do incremental searching
set incsearch hlsearch wrapscan
set ignorecase smartcase

set showmatch		" show the matching brackets when typing

set showcmd		" display incomplete commands
set ruler		" show the cursor position all the time in statusline
set laststatus=2        " always display a nicer status bar
set statusline=%<%h%m%r\ %f%=[%{&filetype},%{&fileencoding},%{&fileformat}]%k\ %-14.(%l/%L,%c%V%)\ %P
set wildmode=longest:list,full

set matchtime=5
set lazyredraw          " faster for macros
set ttyfast             " better for xterm

" make spell suggest faster
set spellsuggest=best
set spelllang=en_gb,cjk

set guifont=Monaco\ 10
set guifontwide=WenQuanYi\ Micro\ Hei\ 12

set autoindent smartindent expandtab smarttab
set shiftwidth=4
set softtabstop=4 	" replace <tab> with 4 blank space.
set textwidth=80	" wrap text for 78 letters

set hidden              " hide instead of abandon buffer
set autoread            " reload files changed externally
map Q gq
set wrap
set whichwrap=b,s,<,>,[,],h,l
set linebreak           " no breakline in the middle of a word

set formatprg=fmt
set formatoptions+=mM     " default tcq, mM to help wrap chinese

set backup
set backupcopy=yes      " safe for docker bind-mounts and hard links
if !isdirectory($HOME . "/.backup")
    call mkdir($HOME . "/.backup", "p")
endif
set backupdir=$HOME/.backup
set directory=$HOME/.backup     "swp

if !isdirectory($HOME . "/.vim/undo")
    call mkdir($HOME . "/.vim/undo", "p")
endif
set undodir=~/.vim/undo undofile undolevels=1000 undoreload=1000

set commentstring=#%s       " default comment style
set sps=best,10             " only show 10 best spell suggestions
set dictionary+=/usr/share/dict/words

" make fuzzy find with :find possible
set path+=**

set magic

" 输入:set list命令是应该显示些啥？
set listchars=nbsp:¬,eol:¶,tab:>-,extends:»,precedes:«,trail:•

" 光标移动到buffer的顶部和底部时保持3行距离
set scrolloff=3

set foldenable foldnestmax=1 foldlevelstart=1
set foldmethod=marker   " fdm=syntax is very slow and makes trouble for neocomplete

set backspace=2

"tags, use semicolon to seperate so that vim searches parent directories!
set tags=./.tags;

" 高亮当前行
set cursorline

"encoding detection
set encoding=utf-8
set fileencoding&
set fileencodings=ucs-bom,utf-8,enc-cn,cp936,gbk,latin1

"completion settings
set completeopt=longest,menuone
set complete-=i
set complete-=t
" }}}

" {{{ true color and terminal settings
if $TERM =~ '^\(xterm\|screen\|tmux\)' || $TERM =~ '256color$'
    let &t_8f= "\e[38;2;%lu;%lu;%lum"
    let &t_8b= "\e[48;2;%lu;%lu;%lum"
    set t_Co=256 termguicolors
endif

" curly underline support
let &t_Cs = "\e[4:3m"
let &t_Ce = "\e[4:0m"
" }}}

" {{{ bracketed paste
if !exists("g:loaded_bracketed_paste")
    let g:loaded_bracketed_paste = 1

    let &t_ti .= "\<Esc>[?2004h"
    let &t_te = "\e[?2004l" . &t_te

    function! XTermPasteBegin(ret)
        set pastetoggle=<f29>
        set paste
        return a:ret
    endfunction

    execute "set <f28>=\<Esc>[200~"
    execute "set <f29>=\<Esc>[201~"
    map <expr> <f28> XTermPasteBegin("i")
    imap <expr> <f28> XTermPasteBegin("")
    vmap <expr> <f28> XTermPasteBegin("c")
    cmap <f28> <nop>
    cmap <f29> <nop>
endif
" }}}

" {{{ keyboard mappings
set winaltkeys=no

"insert time stamp
imap <F8> <C-R>=strftime("%Y-%m-%d %H:%M")<CR>

"move among windows
nmap <C-h>   <C-W>h
nmap <C-l>  <C-W>l
nmap <C-j>   <C-W>j
nmap <C-k>   <C-W>k

"move in insert mode
inoremap <m-h> <left>
inoremap <m-l> <Right>
inoremap <m-j> <C-o>gj
inoremap <m-k> <C-o>gk

" search for visual-mode selected text
vmap / y/<C-R>"<CR>

" backspace to jump to previous buffer
nnoremap <BS> <C-^>

" use <Tab> to jump to next hit without leaving search mode
cnoremap <expr> <Tab> getcmdtype() =~ '[\/?]' ? "<C-g>" : "<C-z>"

" tab navigation
nmap tp :tabprevious<cr>
nmap tn :tabnext<cr>
nmap to :tabnew<cr>
nmap tc :tabclose<cr>
nmap gf <C-W>gf

" clear search highlight with F5
nmap <F5>   :noh<cr><ESC>

" use <leader>y/p to interact with clipboard
vmap <Leader>y "+y
vmap <Leader>d "+d
nmap <Leader>p "+p
nmap <Leader>P "+P
vmap <Leader>p "+p
vmap <Leader>P "+P
" }}}

" {{{ file type settings
"Python
autocmd FileType python set omnifunc=pythoncomplete#Complete

"C/C++
autocmd FileType cpp setl nofoldenable
            \|nmap ,a :A<CR>
autocmd FileType c setl cindent

"Txt, set syntax file and spell check
autocmd FileType tex,plaintex,context
            \|silent set spell
            \|nmap <buffer> <F8> gwap

"emails
autocmd FileType mail
            \|:silent setlocal fo+=aw
            \|:silent set spell
            \|:silent g/^.*>\sOn.*wrote:\s*$\|^>\s*>.*$/de
            \|:silent 1

"markdown
autocmd BufNewFile,BufRead *mkd,*.md,*.mdown set ft=markdown
autocmd FileType markdown set comments=n:> nu nospell textwidth=0 formatoptions=tcroqn2

"yaml
autocmd FileType yaml set softtabstop=2 shiftwidth=2 noautoindent nosmartindent

"crontab hack for mac
autocmd BufEnter /private/tmp/crontab.* setl backupcopy=yes
" }}}

" {{{ big files?
let g:LargeFile = 0.3	"in megabyte
augroup LargeFile
    au!
    au BufReadPre *
        \let f=expand("<afile>")
        \|if getfsize(f) >= g:LargeFile*1023*1024 || getfsize(f) <= -2
            \|let b:eikeep = &ei
            \|let b:ulkeep = &ul
            \|let b:bhkeep = &bh
            \|let b:fdmkeep= &fdm
            \|let b:swfkeep= &swf
            \|set ei=FileType
            \|setlocal noswf bh=unload fdm=manual
            \|let f=escape(substitute(f,'\','/','g'),' ')
            \|exe "au LargeFile BufEnter ".f." set ul=-1"
            \|exe "au LargeFile BufLeave ".f." let &ul=".b:ulkeep."|set ei=".b:eikeep
            \|exe "au LargeFile BufUnload ".f." au! LargeFile * ". f
            \|echomsg "***note*** handling a large file"
        \|endif
    au BufReadPost *
        \if &ch < 2 && getfsize(expand("<afile>")) >= g:LargeFile*1024*1024
            \|echomsg "***note*** handling a large file"
        \|endif
augroup END
" }}}

" {{{ restore views
set viewoptions=cursor,folds,slash,unix
augroup vimrc
    autocmd BufWritePost *
    \   if expand('%') != '' && &buftype !~ 'nofile'
    \|      mkview!
    \|  endif
    autocmd BufRead *
    \   if expand('%') != '' && &buftype !~ 'nofile'
    \|      silent! loadview
    \|  endif
augroup END
" }}}

" {{{ visual p does not replace paste buffer
function! RestoreRegister()
  let @" = s:restore_reg
  return ''
endfunction
function! s:Repl()
  let s:restore_reg = @"
  return "p@=RestoreRegister()\<cr>"
endfunction
vmap <silent> <expr> p <sid>Repl()
" }}}

" Highlight keywords like TODO BUG HACK INFO and etc {{{
autocmd Syntax * call matchadd('Todo',  '\W\zs\(TODO\|FIXME\|CHANGED\|XXX\|BUG\|HACK\)')
autocmd Syntax * call matchadd('Debug', '\W\zs\(NOTE\|INFO\|IDEA\)')
" }}}

" {{{ quickfix auto-height
au FileType qf call AdjustWindowHeight(3, 10)
function! AdjustWindowHeight(minheight, maxheight)
    let l = 1
    let n_lines = 0
    let w_width = winwidth(0)
    while l <= line('$')
        let l_len = strlen(getline(l)) + 0.0
        let line_width = l_len/w_width
        let n_lines += float2nr(ceil(line_width))
        let l += 1
    endw
    exe max([min([n_lines, a:maxheight]), a:minheight]) . "wincmd _"
endfunction
" }}}
