
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

# sdkman's init script costs ~1.6s, almost all of it spent re-deriving PATH and
# JAVA_HOME that the `current' symlinks already encode. Point at the symlinks
# directly (no subprocesses) and load the real script only when `sdk' is run.
export SDKMAN_DIR="$HOME/.sdkman"
# (N-/) not (N/): `current' is a symlink, and plain `/' skips symlinked dirs.
for _sdk_candidate in "$SDKMAN_DIR"/candidates/*/current(N-/); do
  export PATH="$_sdk_candidate/bin:$PATH"
done
unset _sdk_candidate
[ -d "$SDKMAN_DIR/candidates/java/current" ] && \
  export JAVA_HOME="$SDKMAN_DIR/candidates/java/current"

# Lazy shim: the first `sdk' call replaces this function with the real one.
sdk() {
  unfunction sdk
  source "$SDKMAN_DIR/bin/sdkman-init.sh"
  sdk "$@"
}

# go stuff -- `go env GOPATH' is a 300ms subprocess for a value that is just the
# default; override GOPATH before this file if it ever stops being $HOME/go.
export PATH="${GOPATH:-$HOME/go}/bin:$PATH"

# Same idea for `python3 -m site --user-base' (~570ms): glob the versioned dir
# and take the highest, rather than asking Python to tell us where it lives.
_py_user_bins=("$HOME"/Library/Python/*/bin(Nn))
[ ${#_py_user_bins} -gt 0 ] && export PATH="${_py_user_bins[-1]}:$PATH"
unset _py_user_bins

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

# conda removed: activating base2 cost ~1.5s of every shell start (and so ~1.5s
# of every Emacs start, via exec-path-from-shell) and nothing here needs it. To
# use it again, run `source ~/miniconda/bin/activate' by hand in that shell.

. "$HOME/.local/bin/env"

ulimit -n 65536 65536

# This file is the shared, checked-in half of the config. ~/.zshrc is a real
# file per machine that sources this one and then adds whatever is local to that
# machine -- work paths, credentials, host-specific overrides. Nothing secret
# belongs in here, since this repo is public. See readme.org.
