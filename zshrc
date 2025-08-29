
# If you come from bash you might have to change your $PATH.
export PATH="$HOME/bin:/usr/local/bin:$PATH"

# brew path, needed before fzf zsh plugin
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"

# deletes older command if there's a newer duplicate
setopt HIST_IGNORE_ALL_DUPS
# save more history so fzf returns more shit
export SAVEHIST=5000
export HISTSIZE=6000
# immediately add to history, save immediately. help w/ vterm saving hist
setopt INC_APPEND_HISTORY SHARE_HISTORY
# ensures all sessions write to this
HISTFILE=$HOME/.zsh_history

## fzf history plugin
export ZSH_FZF_HISTORY_SEARCH_EVENT_NUMBERS=0
export ZSH_FZF_HISTORY_SEARCH_DATES_IN_SEARCH=1
export ZSH_FZF_HISTORY_SEARCH_REMOVE_DUPLICATES=1
export ZSH_FZF_HISTORY_SEARCH_BIND='^r'
source ~/.zsh/plugins/zsh-fzf-history-search/zsh-fzf-history-search.plugin.zsh

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

export PATH=$HOME/.bin:$PATH

# rust stuff
export PATH="$HOME/.cargo/bin:$PATH"

# bat stuff
export BAT_PAGER="less -RF"

# doom stuff
export PATH="$HOME/.config/emacs/bin:$PATH"

# required to compile some emacs stuff
export PATH="/usr/local/opt/texinfo/bin:$PATH"

export PS1="%F{green}$ %f"

#idk if this needed
# export PATH="/usr/local/opt/ruby/bin:$PATH"
# export PATH="/usr/local/lib/ruby/gems/3.0.0/bin:$PATH"
