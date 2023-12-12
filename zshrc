
# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

DISABLE_AUTO_UPDATE=true
# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME=""

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=""

source $ZSH/oh-my-zsh.sh

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







#################################################################
################## kevin stuff ##################################
#################################################################

# might be cool to use this at some point
function c() {
	echo "${fg[green]}  ~/$(realpath --relative-to=$HOME '.')"
	echo "${fg[magenta]}  $(kuc) "
	echo "$(git_prompt_info) ${reset_color}"
}

PROMPT='%{$fg[green]%}$ %{$reset_color%}'

# ZSH_THEME_GIT_PROMPT_PREFIX="${fg[red]}"
# ZSH_THEME_GIT_PROMPT_SUFFIX=""

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


export PATH=$HOME/.bin:$PATH
# just to make brew have higher priority
export PATH=/usr/local/bin:$PATH
export PATH=~/bin/just-v0.8.3-x86_64-apple-darwin:$PATH

# rust stuff
export PATH="$HOME/.cargo/bin:$PATH"

# bat stuff
export BAT_PAGER="less -RF"
alias jqc="jq -C"

# sops kms key for argo
# export SOPS_KMS_ARN=arn:aws:kms:us-west-2:738720058982:alias/util/helm-secrets/services

# doom stuff
# doom sync, etc.
export PATH="$HOME/.emacs.d/bin:$PATH"
# the new one is here I guess?
export PATH="$HOME/.config/emacs/bin:$PATH"

# solana cli
# export PATH="/Users/kkrausse/.local/share/solana/install/active_release/bin:$PATH"
# alias sol=solana

# required to compile some emacs stuff
export PATH="/usr/local/opt/texinfo/bin:$PATH"

# emacs no window
alias enw="emacs -nw"

oldprompt=$PS1
# >>> conda initialize >>>

# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Users/kevinkrausse/opt/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Users/kevinkrausse/opt/anaconda3/etc/profile.d/conda.sh" ]; then
        . "/Users/kevinkrausse/opt/anaconda3/etc/profile.d/conda.sh"
    else
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

PS1=$oldprompt # fuck conda
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


source /Users/kevinkrausse/Documents/taxbit/tax-engine-tools/bash_scripts/source.sh
export PATH="/opt/homebrew/sbin:$PATH"
export PATH="$HOME/bin:$PATH"
# idk why my python shit wasn't on there?
export PATH="$(python3 -m site --user-base)/bin:$PATH"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
