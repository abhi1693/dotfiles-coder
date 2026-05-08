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
    sudo -n "$@"
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

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

apt_update_once() {
  if [ "${APT_UPDATED:-0}" = "1" ]; then
    return 0
  fi

  as_root apt-get update -yq
  APT_UPDATED=1
}

install_apt_packages() {
  if is_truthy "${SKIP_APT_TOOLING_INSTALL:-}"; then
    log "Skipping apt tooling install because SKIP_APT_TOOLING_INSTALL=${SKIP_APT_TOOLING_INSTALL}"
    return 0
  fi

  if ! have apt-get || ! have apt-cache; then
    warn "apt tooling is unavailable; skipping apt package install"
    return 0
  fi

  if ! as_root true >/dev/null 2>&1; then
    warn "sudo/root access unavailable; skipping apt package install"
    return 0
  fi

  apt_update_once || {
    warn "apt update failed; skipping apt package install"
    return 0
  }

  available_packages=""
  for package in "$@"; do
    if dpkg -s "$package" >/dev/null 2>&1; then
      continue
    fi

    if apt-cache show "$package" >/dev/null 2>&1; then
      available_packages="${available_packages} ${package}"
    else
      warn "apt package is unavailable: $package"
    fi
  done

  if [ -z "$available_packages" ]; then
    return 0
  fi

  # shellcheck disable=SC2086
  as_root apt-get install -yq $available_packages || warn "apt package install failed: $available_packages"
}

install_base_tooling() {
  install_apt_packages \
    apt-transport-https \
    bash \
    bat \
    build-essential \
    ca-certificates \
    curl \
    direnv \
    fd-find \
    fzf \
    git \
    gnupg \
    jq \
    less \
    make \
    nano \
    openssl \
    pipx \
    python3 \
    python3-pip \
    ripgrep \
    shellcheck \
    tar \
    unzip \
    vim \
    xz-utils \
    zip

  if have fdfind && ! have fd; then
    ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi

  if have batcat && ! have bat; then
    ln -sfn "$(command -v batcat)" "$HOME/.local/bin/bat"
  fi
}

tool_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf '%s\n' amd64 ;;
    aarch64|arm64) printf '%s\n' arm64 ;;
    armv7l|armhf) printf '%s\n' arm ;;
    *)
      warn "unsupported CPU architecture: $(uname -m)"
      return 1
      ;;
  esac
}

download_local_bin() {
  name=$1
  url=$2
  mode=${3:-0755}
  tmp_file="${TMPDIR:-/tmp}/${name}.$$"

  if ! have curl; then
    warn "curl is unavailable; skipping $name install"
    return 1
  fi

  if ! curl -fsSL -o "$tmp_file" "$url"; then
    rm -f "$tmp_file"
    warn "download failed for $name"
    return 1
  fi

  chmod "$mode" "$tmp_file"
  mv "$tmp_file" "$HOME/.local/bin/$name"
}

skip_docker_install() {
  is_truthy "${SKIP_DOCKER_INSTALL:-}"
}

install_docker_cli() {
  if skip_docker_install; then
    log "Skipping Docker client install because SKIP_DOCKER_INSTALL=${SKIP_DOCKER_INSTALL}"
    return 0
  fi

  if [ -z "${DOCKER_HOST:-}" ]; then
    log "Docker sidecar not configured; skipping Docker client install"
    return 0
  fi

  if have docker && docker buildx version >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker client tooling already installed"
    wait_for_docker
    return 0
  fi

  if ! have apt-get; then
    warn "apt-get is unavailable; skipping Docker client install"
    return 0
  fi

  if ! as_root true >/dev/null 2>&1; then
    warn "sudo/root access unavailable; skipping Docker client install"
    return 0
  fi

  docker_codename=$(awk -F= '/^VERSION_CODENAME=/{ gsub(/"/, "", $2); print $2 }' /etc/os-release)
  if [ -z "$docker_codename" ]; then
    warn "could not determine Ubuntu codename; skipping Docker client install"
    return 0
  fi

  log "Installing Docker client tooling for $DOCKER_HOST"
  apt_update_once
  as_root apt-get install -yq ca-certificates curl gnupg
  as_root install -m 0755 -d /etc/apt/keyrings
  docker_gpg="${TMPDIR:-/tmp}/docker.asc.$$"
  curl -fsSL -o "$docker_gpg" https://download.docker.com/linux/ubuntu/gpg
  as_root install -m 0644 "$docker_gpg" /etc/apt/keyrings/docker.asc
  rm -f "$docker_gpg"
  as_root chmod a+r /etc/apt/keyrings/docker.asc
  docker_arch=$(dpkg --print-architecture)
  printf '%s\n' "deb [arch=$docker_arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $docker_codename stable" | as_root tee /etc/apt/sources.list.d/docker.list >/dev/null
  APT_UPDATED=0
  apt_update_once
  as_root apt-get install -yq docker-ce-cli docker-buildx-plugin docker-compose-plugin

  wait_for_docker
}

wait_for_docker() {
  if [ -z "${DOCKER_HOST:-}" ] || ! have docker; then
    return 0
  fi

  attempts=0
  while [ "$attempts" -lt 60 ]; do
    if docker info >/tmp/docker-info.log 2>&1; then
      log "Docker daemon is ready at $DOCKER_HOST"
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 1
  done

  cat /tmp/docker-info.log >&2
  die "Docker daemon did not become ready at $DOCKER_HOST"
}

install_helm() {
  if is_truthy "${SKIP_HELM_INSTALL:-}" || is_truthy "${SKIP_K8S_TOOLING_INSTALL:-}"; then
    log "Skipping Helm install"
    return 0
  fi

  if have helm; then
    log "Helm already installed"
    return 0
  fi

  if ! have curl || ! have bash; then
    warn "curl or bash is unavailable; skipping Helm install"
    return 0
  fi

  log "Installing Helm"
  helm_installer="${TMPDIR:-/tmp}/get-helm-3.$$"
  if ! curl -fsSL -o "$helm_installer" https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3; then
    rm -f "$helm_installer"
    warn "Helm installer download failed"
    return 0
  fi
  chmod 0755 "$helm_installer"
  HELM_INSTALL_DIR="$HOME/.local/bin" USE_SUDO=false "$helm_installer" --no-sudo || warn "Helm install failed"
  rm -f "$helm_installer"
}

install_kubectl() {
  if is_truthy "${SKIP_KUBECTL_INSTALL:-}" || is_truthy "${SKIP_K8S_TOOLING_INSTALL:-}"; then
    log "Skipping kubectl install"
    return 0
  fi

  if have kubectl; then
    log "kubectl already installed"
    return 0
  fi

  arch=$(tool_arch) || return 0
  case "$arch" in
    amd64|arm64) ;;
    *)
      warn "kubectl install does not support mapped architecture: $arch"
    return 0
      ;;
  esac

  if ! have curl || ! have sha256sum; then
    warn "curl or sha256sum is unavailable; skipping kubectl install"
    return 0
  fi

  if ! kubectl_version=$(curl -fsSL https://dl.k8s.io/release/stable.txt); then
    warn "could not resolve latest kubectl version"
    return 0
  fi
  kubectl_tmp="${TMPDIR:-/tmp}/kubectl.$$"
  checksum_tmp="${TMPDIR:-/tmp}/kubectl.sha256.$$"
  log "Installing kubectl $kubectl_version"
  if ! curl -fsSL -o "$kubectl_tmp" "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${arch}/kubectl"; then
    rm -f "$kubectl_tmp" "$checksum_tmp"
    warn "kubectl download failed"
    return 0
  fi
  if ! curl -fsSL -o "$checksum_tmp" "https://dl.k8s.io/release/${kubectl_version}/bin/linux/${arch}/kubectl.sha256"; then
    rm -f "$kubectl_tmp" "$checksum_tmp"
    warn "kubectl checksum download failed"
    return 0
  fi
  if ! printf '%s  %s\n' "$(cat "$checksum_tmp")" "$kubectl_tmp" | sha256sum -c -; then
    rm -f "$kubectl_tmp" "$checksum_tmp"
    warn "kubectl checksum verification failed"
    return 0
  fi
  chmod 0755 "$kubectl_tmp"
  mv "$kubectl_tmp" "$HOME/.local/bin/kubectl"
  rm -f "$checksum_tmp"
}

install_github_cli() {
  if is_truthy "${SKIP_GH_INSTALL:-}"; then
    log "Skipping GitHub CLI install because SKIP_GH_INSTALL=${SKIP_GH_INSTALL}"
    return 0
  fi

  if have gh; then
    log "GitHub CLI already installed"
    return 0
  fi

  if ! have apt-get || ! have curl || ! as_root true >/dev/null 2>&1; then
    warn "apt/curl/sudo unavailable; skipping GitHub CLI install"
    return 0
  fi

  log "Installing GitHub CLI"
  apt_update_once || {
    warn "apt update failed; skipping GitHub CLI install"
    return 0
  }
  if ! as_root apt-get install -yq ca-certificates curl; then
    warn "GitHub CLI prerequisites install failed"
    return 0
  fi
  as_root install -m 0755 -d /etc/apt/keyrings
  gh_key="${TMPDIR:-/tmp}/githubcli-archive-keyring.gpg.$$"
  if ! curl -fsSL -o "$gh_key" https://cli.github.com/packages/githubcli-archive-keyring.gpg; then
    rm -f "$gh_key"
    warn "GitHub CLI key download failed"
    return 0
  fi
  as_root install -m 0644 "$gh_key" /etc/apt/keyrings/githubcli-archive-keyring.gpg
  rm -f "$gh_key"
  gh_arch=$(dpkg --print-architecture)
  printf '%s\n' "deb [arch=$gh_arch signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | as_root tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  APT_UPDATED=0
  apt_update_once
  as_root apt-get install -yq gh || warn "GitHub CLI install failed"
}

install_yq() {
  if is_truthy "${SKIP_YQ_INSTALL:-}"; then
    log "Skipping yq install because SKIP_YQ_INSTALL=${SKIP_YQ_INSTALL}"
    return 0
  fi

  if have yq; then
    log "yq already installed"
    return 0
  fi

  arch=$(tool_arch) || return 0
  case "$arch" in
    amd64|arm64) ;;
    *)
      warn "yq install does not support mapped architecture: $arch"
      return 0
      ;;
  esac

  log "Installing yq"
  download_local_bin yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch}" || true
}

install_k9s() {
  if is_truthy "${SKIP_K9S_INSTALL:-}" || is_truthy "${SKIP_K8S_TOOLING_INSTALL:-}"; then
    log "Skipping k9s install"
    return 0
  fi

  if have k9s; then
    log "k9s already installed"
    return 0
  fi

  arch=$(tool_arch) || return 0
  case "$arch" in
    amd64|arm64) ;;
    *)
      warn "k9s install does not support mapped architecture: $arch"
    return 0
      ;;
  esac

  if ! have curl || ! have tar; then
    warn "curl or tar is unavailable; skipping k9s install"
    return 0
  fi

  log "Installing k9s"
  k9s_archive="${TMPDIR:-/tmp}/k9s.$$"
  k9s_dir="${TMPDIR:-/tmp}/k9s-dir.$$"
  mkdir -p "$k9s_dir"
  if ! curl -fsSL -o "$k9s_archive" "https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_${arch}.tar.gz"; then
    rm -rf "$k9s_archive" "$k9s_dir"
    warn "k9s download failed"
    return 0
  fi
  if ! tar -xzf "$k9s_archive" -C "$k9s_dir" k9s; then
    rm -rf "$k9s_archive" "$k9s_dir"
    warn "k9s archive extraction failed"
    return 0
  fi
  chmod 0755 "$k9s_dir/k9s"
  mv "$k9s_dir/k9s" "$HOME/.local/bin/k9s"
  rm -rf "$k9s_archive" "$k9s_dir"
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

install_base_tooling
install_helm
install_kubectl
install_github_cli
install_yq
install_k9s
install_docker_cli

log "Coder dotfiles installed."
