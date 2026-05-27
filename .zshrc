#!/bin/zsh
# vim:fdm=marker

# 预配置 {{{
# 如果不是交互shell就直接结束 (unix power tool, 2.11)
#if [[  "$-" != *i* ]]; then return 0; fi

SHELL=`which zsh`
stty -ixon

# 定义颜色 {{{
if [[ ("$TERM" = *256color || "$TERM" = screen*) && -f $HOME/.lscolor256 ]]; then
    #use prefefined colors
    eval $(dircolors -b $HOME/.lscolor256)
    use_256color=1
    export TERMCAP=${TERMCAP/Co\#8/Co\#256}
else
    [[ -f $HOME/.lscolor ]] && eval $(dircolors -b $HOME/.lscolor)
fi
#}}}
#}}}

# 设置参数 {{{
setopt complete_aliases         #do not expand aliases _before_ completion has finished
setopt auto_cd                  # if not a command, try to cd to it.
setopt auto_pushd               # automatically pushd directories on dirstack
setopt auto_continue            #automatically send SIGCON to disowned jobs
setopt extended_glob            # so that patterns like ^() *~() ()# can be used
setopt pushd_ignore_dups        # do not push dups on stack
setopt pushd_silent             # be quiet about pushds and popds
setopt brace_ccl                # expand alphabetic brace expressions
#setopt chase_links             # ~/ln -> /; cd ln; pwd -> /
setopt complete_in_word         # stays where it is and completion is done from both ends
setopt correct                  # spell check for commands only
#setopt equals extended_glob    # use extra globbing operators
setopt no_hist_beep             # don not beep on history expansion errors
setopt no_list_beep             # do not beep on ambigious list completions
setopt hash_list_all            # search all paths before command completion
setopt hist_ignore_all_dups     # when runing a command several times, only store one
setopt hist_reduce_blanks       # reduce whitespace in history
setopt hist_ignore_space        # do not remember commands starting with space
setopt share_history            # share history among sessions
setopt hist_verify              # reload full command when runing from history
setopt hist_expire_dups_first   #remove dups when max size reached
setopt hist_fcntl_lock          #use fcntl to lock history file
setopt hist_no_store            #do not store history commands
setopt interactive_comments     # comments in history
setopt list_types               # show ls -F style marks in file completion
setopt long_list_jobs           # show pid in bg job list
setopt numeric_glob_sort        # when globbing numbered files, use real counting
setopt inc_append_history       # append to history once executed
setopt prompt_subst             # prompt more dynamic, allow function in prompt
setopt nonomatch
setopt no_beep                  # supress all beep sound

#remove / and . from WORDCHARS to allow alt-backspace to delete word
WORDCHARS='*?_-[]~=&;!#$%^(){}<>'

#report to me when people login/logout
watch=(notme)

# 自动加载自定义函数
fpath=($HOME/.zfunctions $fpath)
# 需要设置了extended_glob才能glob到所有的函数，为了补全能用，又需要放在compinit前面
_my_functions=${fpath[1]}/*(N-.x:t)
[[ -n $_my_functions ]] && autoload -U $_my_functions
# }}}

# 命令补全参数{{{
#   zsytle ':completion:*:completer:context or command:argument:tag'
zmodload -i zsh/complist        # for menu-list completion
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}" "ma=${${use_256color+1;7;38;5;143}:-1;7;33}"
#ignore list in completion
zstyle ':completion:*' ignore-parents parent pwd directory
#menu selection in completion
zstyle ':completion:*' menu select=2
zstyle ':completion:*' rehash true
zstyle ':completion:*' completer _oldlist _expand _complete _match
zstyle ':completion:*:match:*' original only
zstyle ':completion:*:approximate:*' max-errors 1 numeric
## case-insensitive (uppercase from lowercase) completion
zstyle ':completion:*' matcher-list 'm:{[:lower:]}={[:upper:]}'
### case-insensitive (all) completion
#zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*:*:kill:*' menu yes select
zstyle ':completion:*:*:*:*:processes' force-list always
zstyle ':completion:*:processes' command 'ps -au$USER'
zstyle ':completion:*:*:kill:*:processes' list-colors "=(#b) #([0-9]#)*=36=1;31"
#use cache to speed up pacman completion
zstyle ':completion::complete:*' use-cache on
#zstyle ':completion::complete:*' cache-path .zcache
#group matches and descriptions
zstyle ':completion:*:matches' group 'yes'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:options' description 'yes'
zstyle ':completion:*:options' auto-description '%d'
zstyle ':completion:*:descriptions' format $'\e[33m == \e[1;7;36m %d \e[m\e[33m ==\e[m'
zstyle ':completion:*:messages' format $'\e[33m == \e[1;7;36m %d \e[m\e[0;33m ==\e[m'
zstyle ':completion:*:warnings' format $'\e[33m == \e[1;7;31m No Matches Found \e[m\e[0;33m ==\e[m'
zstyle ':completion:*:corrections' format $'\e[33m == \e[1;7;37m %d (errors: %e) \e[m\e[0;33m ==\e[m'
# dabbrev for zsh!! M-/ M-,
zstyle ':completion:*:history-words' stop yes
zstyle ':completion:*:history-words' remove-all-dups yes
zstyle ':completion:*:history-words' list false
zstyle ':completion:*:history-words' menu yes select

autoload -Uz compinit
[[ -n $HOME/.zcompdump(#qN.mh+24) ]] && compinit || compinit -C

# }}}

# 自定义函数 {{{

# 普通自定义函数 {{{
#show 256 color tab
256tab() {
    for k in `seq 0 1`;do
        for j in `seq $((16+k*18)) 36 $((196+k*18))`;do
            for i in `seq $j $((j+17))`; do
                printf "\e[01;$1;38;5;%sm%4s" $i $i;
            done;echo;
        done;
    done
}

#calculator
calc()  { awk "BEGIN{ print $* }" ; }

#check if a binary exists in path
bin-exist() {[[ -n ${commands[$1]} ]]}

#help command for builtins
help() { man zshbuiltins | sed -ne "/^       $1 /,/^\$/{s/       //; p}"}

# }}}

#{{{ functions to set prompt pwd color
__PROMPT_PWD="%F{magenta}%~%f"
#change PWD color
pwd_color_chpwd() { [ $PWD = $OLDPWD ] || __PROMPT_PWD="%U%F{cyan}%~%f%u" }
#change back before next command
pwd_color_preexec() { __PROMPT_PWD="%F{magenta}%~%f" }

#}}}

#{{{vcs_info for git branch in prompt
autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:*:*' formats           " %F{black}%K{white}%B %m %f%k%%b"
zstyle ':vcs_info:*:*' actionformats     " %F{black}%K{white}%B %m(%a) %f%k%%b"
zstyle ':vcs_info:*:*' check-for-changes true
zstyle ':vcs_info:git*+set-message:*'    hooks git-prompt-status
function +vi-git-prompt-status() {
    local s=${hook_com[branch]}
    local ahead behind
    ahead=$(git rev-list ${hook_com[branch]}@{upstream}..HEAD 2>/dev/null | wc -l)
    behind=$(git rev-list HEAD..${hook_com[branch]}@{upstream} 2>/dev/null | wc -l)
    if (( $ahead )) && (( $behind )); then
        s+="%F{red}="
    elif (( $ahead )); then
        s+="%F{green}+"
    elif (( $behind )); then
        s+="%F{magenta}-"
    fi
    [[ -n ${hook_com[staged]} || -n ${hook_com[unstaged]} ]] && s+="%F{blue}*"
    hook_com[misc]=$s
}

vcs_info_precmd() { vcs_info }
vcs_info_chpwd() { vcs_info }
#}}}

#{{{ functions to set gnu screen title
# active command as title in terminals
if [[ -n $SSH_CONNECTION ]]; then
    function title() {}
else
    case $TERM in
        xterm*|rxvt*)
            function title() { print -nP "\e]0;$1\a" }
            ;;
        screen*)
            if [[ -n $STY ]] && (screen -ls |grep $STY &>/dev/null); then
                function title()
                {
                    #modify screen title
                    print -nP "\ek$1\e\\"
                }
            elif [[ -n $TMUX ]]; then       # actually in tmux !
                function title()
                {
                    print -nP "\e]2;$1\a"
                }
            fi
            ;;
        *)
            function title() {}
            ;;
    esac
fi

#set screen title if not connected remotely
screen_precmd() {
    title "`print -Pn "%~" |sed "s:\([~/][^/]*\)/.*/:\1...:;s:\([^-]*-[^-]*\)-.*:\1:"`" "$TERM $PWD"
    echo -ne '\033[?17;0;127c'
}

screen_preexec() {
    local -a cmd; cmd=(${(z)1})
    case $cmd[1]:t in
        'ssh')          title "@""`echo $cmd[2]|sed 's:.*@::'`" "$TERM $cmd";;
        'sudo')         title "#"$cmd[2]:t "$TERM $cmd[3,-1]";;
        'for')          title "()"$cmd[7] "$TERM $cmd";;
        'svn'|'git'|'hg')    title "$cmd[1,2]" "$TERM $cmd";;
        'ls'|'ll')      ;;
        *)              title $cmd[1]:t "$TERM $cmd[2,-1]";;
    esac
}

#}}}

#{{{register hook functions
autoload -Uz add-zsh-hook
add-zsh-hook precmd  screen_precmd
add-zsh-hook precmd  vcs_info_precmd
add-zsh-hook preexec screen_preexec
add-zsh-hook preexec pwd_color_preexec
add-zsh-hook chpwd   pwd_color_chpwd
add-zsh-hook chpwd   vcs_info_chpwd
#}}}

# }}}

# 提示符 {{{
if [ "$SSH_TTY" = "" ]; then
    local host="%B%F{magenta}%m%b%f"
else
    local host="%B%F{red}%m%b%f"
fi
local user="%B%(!:%F{red}:%F{green})%n%b%f"       #different color for privileged sessions
local symbol="%B%(!:%F{red}# :%F{yellow}> )%b%f"
local job="%1(j,%F{red}:%F{blue}%j,)%f"
PROMPT='$user%F{yellow}@%f$host${vcs_info_msg_0_}$job$symbol'
PROMPT2="$PROMPT%F{cyan}%_%f %B%F{black}>%b%f%F{green}>%B%F{green}>%b%f "
#NOTE  **DO NOT** use double quote , it does not work
typeset -A altchar
set -A altchar ${(s..)terminfo[acsc]}
PR_SET_CHARSET="%{$terminfo[enacs]%}"
PR_SHIFT_IN="%{$terminfo[smacs]%}"
PR_SHIFT_OUT="%{$terminfo[rmacs]%}"
local prompt_time="%(?:%F{green}:%F{red})%*%f"
RPROMPT='$__PROMPT_PWD'

# SPROMPT - the spelling prompt
SPROMPT="%F{yellow}zsh%f: correct '%F{red}%B%R%b%f' to '%F{green}%B%r%b%f' ? ([%F{cyan}Y%f]es/[%F{cyan}N%f]o/[%F{cyan}E%f]dit/[%F{cyan}A%f]bort) "

#行编辑高亮模式 {{{
zle_highlight=(region:bg=magenta
               special:bold,fg=magenta
               default:bold
               isearch:underline
               )
#}}}

# }}}

# 键盘定义及键绑定 {{{
#bindkey "\M-v" "\`xclip -o\`\M-\C-e\""
# 设置键盘 {{{
# create a zkbd compatible hash;
# to add other keys to this hash, see: man 5 terminfo
autoload -U zkbd
bindkey -e      #use emacs style keybindings :(
typeset -A key  #define an array

#if zkbd definition exists, use defined keys instead
if [[ -f ~/.zkbd/${TERM}-${DISPLAY:-$VENDOR-$OSTYPE} ]]; then
    source ~/.zkbd/$TERM-${DISPLAY:-$VENDOR-$OSTYPE}
else
    key[Home]=${terminfo[khome]}
    key[End]=${terminfo[kend]}
    key[Insert]=${terminfo[kich1]}
    key[Delete]=${terminfo[kdch1]}
    key[Up]=${terminfo[kcuu1]}
    key[Down]=${terminfo[kcud1]}
    key[Left]=${terminfo[kcub1]}
    key[Right]=${terminfo[kcuf1]}
    key[PageUp]=${terminfo[kpp]}
    key[PageDown]=${terminfo[knp]}
    for k in ${(k)key} ; do
        # $terminfo[] entries are weird in ncurses application mode...
        [[ ${key[$k]} == $'\eO'* ]] && key[$k]=${key[$k]/O/[}
    done
fi

# setup key accordingly
[[ -n "${key[Home]}"    ]]  && bindkey  "${key[Home]}"    beginning-of-line
[[ -n "${key[End]}"     ]]  && bindkey  "${key[End]}"     end-of-line
[[ -n "${key[Insert]}"  ]]  && bindkey  "${key[Insert]}"  overwrite-mode
[[ -n "${key[Delete]}"  ]]  && bindkey  "${key[Delete]}"  delete-char
[[ -n "${key[Up]}"      ]]  && bindkey  "${key[Up]}"      up-line-or-history
[[ -n "${key[Down]}"    ]]  && bindkey  "${key[Down]}"    down-line-or-history
[[ -n "${key[Left]}"    ]]  && bindkey  "${key[Left]}"    backward-char
[[ -n "${key[Right]}"   ]]  && bindkey  "${key[Right]}"   forward-char

# }}}

# 键绑定  {{{
autoload history-search-end
zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end
bindkey "^P" history-beginning-search-backward-end
bindkey "^N" history-beginning-search-forward-end
bindkey -M viins "^P" history-beginning-search-backward-end
bindkey -M viins "^N" history-beginning-search-forward-end
bindkey '^[[1;5D' backward-word     # C-left
bindkey '^[[1;5C' forward-word      # C-right

autoload -U edit-command-line
zle -N      edit-command-line
bindkey '\ee' edit-command-line
# }}}

# }}}

# ZLE 自定义widget {{{
#

# {{{ pressing TAB in an empty command makes a cd command with completion list
# from linuxtoy.org
dumb-cd(){
    if [[ -n $BUFFER ]] ; then # 如果该行有内容
        zle expand-or-complete # 执行 TAB 原来的功能
    else # 如果没有
        BUFFER="cd " # 填入 cd（空格）
        zle end-of-line # 这时光标在行首，移动到行末
        zle expand-or-complete # 执行 TAB 原来的功能
    fi
}
zle -N dumb-cd
bindkey "\t" dumb-cd #将上面的功能绑定到 TAB 键
# }}}


# {{{ double ESC to prepend "sudo"
sudo-command-line() {
    [[ -z $BUFFER ]] && zle up-history
    [[ $BUFFER != sudo\ * ]] && BUFFER="sudo $BUFFER"
    zle end-of-line                 #光标移动到行末
}
zle -N sudo-command-line
#定义快捷键为： [Esc] [Esc]
bindkey "\e\e" sudo-command-line
# }}}

# {{{ c-z to continue
fancy-ctrl-z () {
    if [[ $#BUFFER -eq 0 ]]; then
        BUFFER="fg"
        zle accept-line
    else
        zle push-input
        zle clear-screen
    fi
}
zle -N fancy-ctrl-z
bindkey '^Z' fancy-ctrl-z
# }}}

# }}}

# 环境变量及其他参数 {{{
# number of lines kept in history
export HISTSIZE=20000
# number of lines saved in the history after logout
export SAVEHIST=40000
# location of history
export HISTFILE=$HOME/.zsh_history
# ignore some commands
HISTORY_IGNORE="(ll *|less *|cd *|pwd|rm *|exit|[bf]g|jobs)"

export PATH=$HOME/bin:$PATH
export EDITOR=vim
export VISUAL=vim
export SUDO_PROMPT=$'[\e[31;5msudo\e[m] password for \e[33;1m%p\e[m: '
export INPUTRC=$HOME/.inputrc

#MOST like colored man pages
export PAGER=less
export LESS_TERMCAP_md=$'\E[1;31m'      #bold1
export LESS_TERMCAP_mb=$'\E[1;31m'
export LESS_TERMCAP_me=$'\E[m'
export LESS_TERMCAP_so=$'\E[01;7;34m'  #search highlight
export LESS_TERMCAP_se=$'\E[m'
export LESS_TERMCAP_us=$'\E[1;2;32m'    #bold2
export LESS_TERMCAP_ue=$'\E[m'
export LESS="-M -i -R --shift 5"
export LESSCHARSET=utf-8
export READNULLCMD=less
# In archlinux the pipe script is in PATH, how ever in debian it is not
(bin-exist src-hilite-lesspipe.sh) && export LESSOPEN="| src-hilite-lesspipe.sh %s"
[ -x /usr/share/source-highlight/src-hilite-lesspipe.sh ] && export LESSOPEN="| /usr/share/source-highlight/src-hilite-lesspipe.sh %s"

#for gnuplot, avoid locate!!!
[[ -n $DISPLAY ]] && export GDFONTPATH=/usr/share/fonts/TTF

# }}}

# 读入其他配置 {{{

# 主机特定的配置，前置的主要原因是有可能需要提前设置PATH等环境变量
#   例如在aix主机，需要把 /usr/linux/bin
#   置于PATH最前以便下面的配置所调用的命令是linux的版本
[[ -f $HOME/.zshrc.$HOST ]] && source $HOME/.zshrc.$HOST
[[ -f $HOME/.zshrc.local ]] && source $HOME/.zshrc.local
# }}}

# 命令别名 {{{
# alias and listing colors
alias -g A="|awk"
alias -g B='|sed -r "s:\x1B\[[0-9;]*[mK]::g"'       # remove color, make things boring
alias -g C="|wc"
alias -g E="|sed"
alias -g G='|GREP_COLOR=$(echo 3$[$(date +%N)%6+1]'\'';1;7'\'') egrep -i --color=always'
alias -g H="|head -n $(($LINES-2))"
alias -g L="|less"
alias -g P="|column -t"
alias -g R="|tac"
alias -g S="|sort"
alias -g T="|tail -n $(($LINES-2))"
alias -g X="|xargs"
alias -g N="> /dev/null"
alias -g NF="./*(oc[1])"      # last modified(inode time) file or directory

#file types
(bin-exist 7z) && for i in rar zip 7z lzma;   alias -s $i="7z x"

#no correct for mkdir mv and cp
for i in mkdir mv cp;       alias $i="nocorrect $i"
alias find='noglob find'        # noglob for find
alias grep='grep -I --color=auto'
alias egrep='egrep -I --color=auto'
(bin-exist task) && alias cal='task cal' || alias cal='cal -3'
alias freeze='kill -STOP'
alias ls=$'ls -h --color=auto -X --group-directories-first -ctr --time-style="+\e[33m[\e[32m%Y-%m-%d \e[35m%k:%M\e[33m]\e[m"'
alias vi='vim'
alias ll='ls -l'
alias df='df -Th'
alias du='du -h'
alias dmesg='dmesg -H'
#show directories size
alias dud='du -s *(/)'
#date for US and CN
alias adate='for i in Etc/UTC Asia/{Tokyo,Shanghai,Urumqi} Europe/{Moscow,Paris,London} America/{New_York,Los_Angeles}; do printf %-22s "$i:";TZ=$i date +"%m-%d %a %H:%M";done'
alias info='info --vi-keys'
alias rsync='rsync --progress --partial'
alias history='history 1'       #zsh specific
alias port='netstat -ntlp'      #opening ports
alias top10='print -l  ${(o)history%% *} | uniq -c | sort -nr | head -n 10'
[ -d /usr/share/man/zh_CN ] && alias cman="MANPATH=/usr/share/man/zh_CN man"

alias forget='unset HISTFILE'

#}}}

if [ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
    source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
    ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=magenta,bold'
    ZSH_HIGHLIGHT_STYLES[alias]='fg=cyan,bold'
    ZSH_HIGHLIGHT_STYLES[builtin]='fg=yellow,bold'
    ZSH_HIGHLIGHT_STYLES[function]='fg=green,bold'
    ZSH_HIGHLIGHT_STYLES[command]='fg=blue,bold'
    ZSH_HIGHLIGHT_STYLES[precommand]='fg=red,bold'
    ZSH_HIGHLIGHT_STYLES[unknown-token]='none,bold'
fi

typeset -U PATH
