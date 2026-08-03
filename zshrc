
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
export PATH="/opt/homebrew/opt/texinfo/bin:$PATH"

##### machine / fs specific #########

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

function run_if_command_exists {
    local command_to_check="$1"
    shift
    if command -v "$command_to_check" >/dev/null 2>&1; then
        "$@"
    else
        echo "-- ignoring $command_to_check stuff"
    fi
}

# go stuff
run_if_command_exists go \
  export PATH="$(go env GOPATH)/bin:$PATH";

run_if_command_exists python3 \
  export PATH="$(python3 -m site --user-base)/bin:$PATH"

# uh need to fix this grbg to not be checked in
export NVM_DIR="$HOME/.nvm"
# --no-use: the implicit `nvm use default` spawns ~100 subprocesses, which takes
# ~30s under SentinelOne's per-exec scanning; resolve the default version below
# with globs instead (no subprocesses)
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" --no-use
if [ -s "$NVM_DIR/alias/default" ]; then
  read -r _nvm_default < "$NVM_DIR/alias/default"
  _nvm_bins=("$NVM_DIR"/versions/node/v${_nvm_default#v}*/bin(Nn))
  [ ${#_nvm_bins} -gt 0 ] && export PATH="${_nvm_bins[-1]}:$PATH"
  unset _nvm_default _nvm_bins
fi
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
export PATH="/usr/local/opt/libpq/bin:$PATH"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

source $HOME/miniconda/bin/activate
conda activate base2
alias forward-aws-all='bun run $HOME/Documents/taxbit/kevin-scripts/forward-all.ts'
forward-aws-host() {
    local profile=$1 local_port=$2 host=$3 remote_port=$4 bastion=${5:-ssh-bastion}
    ec2-session --profile "$profile" \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "{\"portNumber\":[\"$remote_port\"],\"localPortNumber\":[\"$local_port\"],\"host\":[\"$host\"]}" \
        "$bastion"
}

. "$HOME/.local/bin/env"


# for gemini code
export GOOGLE_CLOUD_PROJECT="1026764388373"

ulimit -n 65536 65536

# Secrets and per-machine overrides live here, outside this repo — the repo is
# public, so nothing sensitive belongs in it.
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
