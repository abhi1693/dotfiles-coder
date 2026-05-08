# Coder-friendly zsh environment.

export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"

if [ -n "${ZSH_VERSION:-}" ] && [ "${SHELL##*/}" != "zsh" ]; then
  zsh_path=$(command -v zsh 2>/dev/null || true)
  if [ -n "$zsh_path" ]; then
    export SHELL="$zsh_path"
  fi
  unset zsh_path
fi

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH

if [ -f "$HOME/.zshenv.local" ]; then
  . "$HOME/.zshenv.local"
fi
