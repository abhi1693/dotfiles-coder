#!/usr/bin/env sh
set -eu

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif have sudo; then
    sudo "$@"
  else
    return 127
  fi
}

append_root_line() {
  line=$1
  file=$2

  if [ "$(id -u)" -eq 0 ]; then
    printf '%s\n' "$line" >> "$file"
  elif have sudo; then
    printf '%s\n' "$line" | sudo tee -a "$file" >/dev/null
  else
    return 127
  fi
}

resolve_home() {
  user=$1

  if [ -n "${HOME:-}" ]; then
    printf '%s\n' "$HOME"
    return 0
  fi

  if have getent; then
    getent passwd "$user" | awk -F: '{ print $6 }'
  else
    awk -F: -v user="$user" '$1 == user { print $6 }' /etc/passwd
  fi
}

link_file() {
  src=$1
  dst=$2

  if [ ! -f "$src" ]; then
    die "missing dotfile: $src"
  fi

  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    backup="${dst}.bak.$(date +%Y%m%d%H%M%S)"
    mv "$dst" "$backup"
    log "Backed up $dst to $backup"
  fi

  ln -sfn "$src" "$dst"
}

export DEBIAN_FRONTEND=noninteractive

USER_NAME=${USER:-}
if [ -z "$USER_NAME" ]; then
  USER_NAME=$(id -un)
  export USER=$USER_NAME
fi
export LOGNAME=${LOGNAME:-$USER_NAME}

HOME_DIR=$(resolve_home "$USER_NAME")
if [ -z "$HOME_DIR" ]; then
  die "could not determine home directory for $USER_NAME"
fi
export HOME=$HOME_DIR

case "$0" in
  */*) script_dir=${0%/*} ;;
  *) script_dir=. ;;
esac
DOTFILES_DIR=$(CDPATH= cd "$script_dir" && pwd)
unset script_dir

mkdir -p "$HOME/.local/bin" "$HOME/.cache/zsh" "$HOME/work"

link_file "$DOTFILES_DIR/.zshenv" "$HOME/.zshenv"
link_file "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"

if [ ! -f "$HOME/.zshenv.local" ]; then
  {
    printf '%s\n' '# Local-only shell settings and secrets.'
    printf '%s\n' '# This file is intentionally not managed by git.'
  } > "$HOME/.zshenv.local"
  chmod 600 "$HOME/.zshenv.local"
fi

ZSH_PATH=$(command -v zsh || true)
if [ -n "$ZSH_PATH" ]; then
  if [ -f /etc/shells ] && ! grep -qxF "$ZSH_PATH" /etc/shells; then
    append_root_line "$ZSH_PATH" /etc/shells || warn "could not add $ZSH_PATH to /etc/shells"
  fi

  current_shell=""
  if have getent; then
    current_shell=$(getent passwd "$USER_NAME" | awk -F: '{ print $7 }')
  else
    current_shell=$(awk -F: -v user="$USER_NAME" '$1 == user { print $7 }' /etc/passwd)
  fi

  if [ "$current_shell" != "$ZSH_PATH" ]; then
    if have chsh && as_root chsh -s "$ZSH_PATH" "$USER_NAME"; then
      log "Changed login shell for $USER_NAME to $ZSH_PATH"
    elif have usermod && as_root usermod -s "$ZSH_PATH" "$USER_NAME"; then
      log "Changed login shell for $USER_NAME to $ZSH_PATH"
    else
      warn "could not change login shell for $USER_NAME; zsh is installed at $ZSH_PATH"
    fi
  else
    log "Login shell already set to $ZSH_PATH"
  fi
else
  log "zsh is not installed yet; leaving shell selection to the Coder template"
fi

log "Coder dotfiles installed."
