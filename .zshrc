# Coder-friendly interactive zsh config.

HISTFILE="${HOME}/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000

setopt autocd
setopt extended_history
setopt hist_ignore_all_dups
setopt hist_reduce_blanks
setopt inc_append_history
setopt share_history
setopt prompt_subst

mkdir -p "${HOME}/.cache/zsh"
autoload -Uz compinit
compinit -i -d "${HOME}/.cache/zsh/zcompdump-${ZSH_VERSION}" 2>/dev/null || true

if [ -s "${HOME}/.nvm/nvm.sh" ]; then
  export NVM_DIR="${HOME}/.nvm"
  . "${NVM_DIR}/nvm.sh"
fi

if [ -f "${HOME}/.fzf.zsh" ]; then
  . "${HOME}/.fzf.zsh"
fi

if [ -f /usr/share/doc/fzf/examples/completion.zsh ]; then
  . /usr/share/doc/fzf/examples/completion.zsh
fi

if [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
  . /usr/share/doc/fzf/examples/key-bindings.zsh
fi

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi

autoload -Uz colors
colors

PROMPT='%F{green}%n@%m%f:%F{blue}%~%f %# '
RPROMPT='%(?.%F{green}.%F{red})%?%f'

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

if command -v kubectl >/dev/null 2>&1; then
  alias k='kubectl'
fi

if command -v coder >/dev/null 2>&1; then
  alias cws='coder list'
fi
