# might be cool to use this at some point
function c() {
	echo "${fg[green]}  ~/$(realpath --relative-to=$HOME '.')"
	echo "${fg[magenta]}  $(kuc) "
	echo "  $(git_prompt_info) ${reset_color}"
}

PROMPT='%{$fg[green]%}$ %{$reset_color%}'

ZSH_THEME_GIT_PROMPT_PREFIX="${fg[red]}"
ZSH_THEME_GIT_PROMPT_SUFFIX=""

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"


export PATH=$HOME/bin:$PATH
# just to make brew have higher priority
export PATH=/usr/local/bin:$PATH
export PATH=~/bin/just-v0.8.3-x86_64-apple-darwin:$PATH

# release email stuff
export PATH="$HOME/bin/wp-pro-bin:$PATH"

export SBT_OPTS=-Xmx4G
export AWS_PROFILE=services

# rust stuff
export PATH="$HOME/.cargo/bin:$PATH"

# bat stuff
export BAT_PAGER="less -RF"
alias jq="jq -C"

# sops kms key for argo
export SOPS_KMS_ARN=arn:aws:kms:us-west-2:738720058982:alias/util/helm-secrets/services

# doom stuff
# doom sync, etc.
export PATH="$HOME/.emacs.d/bin:$PATH"

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# solana cli
export PATH="/Users/kkrausse/.local/share/solana/install/active_release/bin:$PATH"
alias sol=solana

# required to compile some emacs stuff
export PATH="/usr/local/opt/texinfo/bin:$PATH"

# emacs no window
alias enw="emacs -nw"

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Users/kevinkrausse/mambaforge/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Users/kevinkrausse/mambaforge/etc/profile.d/conda.sh" ]; then
        . "/Users/kevinkrausse/mambaforge/etc/profile.d/conda.sh"
    else
        export PATH="/Users/kevinkrausse/mambaforge/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

export PATH="/usr/local/opt/ruby/bin:$PATH"
export PATH="/usr/local/lib/ruby/gems/3.0.0/bin:$PATH"
