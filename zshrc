
# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:/usr/local/bin:$PATH

export MCFLY_KEY_SCHEME=vim
export MCFLY_FUZZY=2
export MCFLY_RESULTS=60
export MCFLY_INTERFACE_VIEW=BOTTOM
#eval "$(mcfly init zsh)"

bindkey '^s' mcfly-history-widget

# deletes older command if there's a newer duplicate
export HIST_IGNORE_ALL_DUPS=1
# saves newer version
export SAVEHIST=5000
export HISTSIZE=6000
export ZSH_FZF_HISTORY_SEARCH_EVENT_NUMBERS=0
export ZSH_FZF_HISTORY_SEARCH_DATES_IN_SEARCH=0
export ZSH_FZF_HISTORY_SEARCH_REMOVE_DUPLICATES=1
export ZSH_FZF_HISTORY_SEARCH_BIND='^h'
source ~/.zsh/plugins/zsh-fzf-history-search/zsh-fzf-history-search.plugin.zsh
# source ~/.zsh/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh
# bindkey '^[[A' mcfly-history-widget # doesn't work, or does initially but resets

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

export PATH="/usr/local/opt/ruby/bin:$PATH"
export PATH="/usr/local/lib/ruby/gems/3.0.0/bin:$PATH"
export PATH="/opt/homebrew/opt/texinfo/bin:$PATH"
export PATH="/opt/homebrew/bin:$PATH"

POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=""

##### machine / fs specific #########
# export PATH=$PATH:$(go env GOPATH)/bin

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

export PATH="/opt/homebrew/sbin:$PATH"
# idk why my python shit wasn't on there?
export PATH="$(python3 -m site --user-base)/bin:$PATH"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
