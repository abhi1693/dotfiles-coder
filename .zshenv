# Coder-friendly zsh environment.

export EDITOR="${EDITOR:-nano}"
export VISUAL="${VISUAL:-$EDITOR}"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) PATH="$HOME/.local/bin:$PATH" ;;
esac
export PATH

if [ -f "$HOME/.zshenv.local" ]; then
  . "$HOME/.zshenv.local"
fi
