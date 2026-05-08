# dotfiles-coder

Coder-specific dotfiles for Kubernetes workspaces.

This repo is intentionally smaller than a normal workstation bootstrap. It only:

- links `.zshenv` and `.zshrc` into `$HOME`;
- creates `$HOME/.zshenv.local` for machine-local secrets;
- sets the workspace user's login shell to `zsh` when zsh is already installed
  and sudo/root access is available.

It does not install Docker, Docker-in-Docker, Node/NVM, global npm packages,
Helm, GitHub CLI, IDEs, or any apt packages. The Coder template should provide
base tooling such as zsh.

Use this as the Coder dotfiles URL:

```text
https://github.com/abhi1693/dotfiles-coder
```

The installer is POSIX `sh` so it can run through Coder's `coder dotfiles` startup path.
