#!/usr/bin/env bash
# jira-swarms one-click installer
# Default install location (code): ~/.cursor/skills/jira-swarms
# Usage: curl -fsSL https://raw.githubusercontent.com/upendra243/jira-swarms/main/scripts/install.sh | bash
# Or:    INSTALL_DIR=~/.cursor/skills/jira-swarms REPO_URL=https://github.com/upendra243/jira-swarms bash -c "$(curl -fsSL https://...)"
set -e

REPO_URL="${REPO_URL:-https://github.com/upendra243/jira-swarms}"
DEFAULT_INSTALL_DIR="${HOME}/.cursor/skills/jira-swarms"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
# Expand tilde if passed as literal
[[ "$INSTALL_DIR" == "~"* ]] && INSTALL_DIR="${HOME}${INSTALL_DIR:1}"

# Only prompt when stdin is a TTY (interactive)
interactive() { [[ -t 0 ]]; }

prompt_yes() {
  local msg="$1"
  local default="${2:-N}"
  if [[ "$default" == "Y" ]]; then
    read -r -p "$msg [Y/n]: " ans
    [[ -z "$ans" || "$ans" == [yY] || "$ans" == [yY][eE][sS] ]]
  else
    read -r -p "$msg [y/N]: " ans
    [[ "$ans" == [yY] || "$ans" == [yY][eE][sS] ]]
  fi
}

echo "jira-swarms installer"
echo ""

# Optional: ask for install directory (interactive only)
if interactive; then
  read -r -p "Installation directory [$INSTALL_DIR]: " input_dir
  [[ -n "$input_dir" ]] && INSTALL_DIR="$input_dir"
  [[ "$INSTALL_DIR" == "~"* ]] && INSTALL_DIR="${HOME}${INSTALL_DIR:1}"
fi

# If directory exists, ask whether to reinstall (interactive) or fail (non-interactive)
if [[ -d "$INSTALL_DIR" ]] && [[ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
  if interactive; then
    if prompt_yes "Directory $INSTALL_DIR already exists. Reinstall (re-clone)?"; then
      echo "Removing existing directory..."
      rm -rf "$INSTALL_DIR"
    else
      echo "Installation cancelled."
      exit 0
    fi
  else
    echo "Error: $INSTALL_DIR already exists and is non-empty. Set INSTALL_DIR or run interactively." >&2
    exit 1
  fi
fi

# Prerequisites

# Detect platform (for Git/Jira CLI guidance)
OS_NAME="$(uname -s 2>/dev/null || echo unknown)"
DISTRO_ID=""
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO_ID="${ID:-}"
fi

ensure_git() {
  if command -v git &>/dev/null; then
    return 0
  fi

  echo "Git is required for jira-swarms (to clone the repo and use worktrees)." >&2

  case "$OS_NAME" in
    Darwin)
      if command -v brew &>/dev/null; then
        echo "Detected macOS with Homebrew." >&2
        if interactive && prompt_yes "Install Git via Homebrew now?"; then
          if brew install git; then
            echo "Installed Git via Homebrew." >&2
            return 0
          else
            echo "Warning: Homebrew install of Git failed." >&2
          fi
        fi
      fi
      echo "Please install Git on macOS (e.g. via Xcode Command Line Tools or Homebrew) and rerun this installer." >&2
      ;;
    Linux)
      if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "debian" ]]; then
        echo "On Ubuntu/Debian, install Git with (run manually):" >&2
        echo "  sudo apt update && sudo apt install -y git" >&2
      else
        echo "Please install Git via your distribution's package manager and rerun this installer." >&2
      fi
      ;;
    *)
      echo "Unknown or unsupported platform ('$OS_NAME'). Please install Git manually and rerun this installer." >&2
      ;;
  esac

  return 1
}

ensure_jira_cli() {
  if command -v jira &>/dev/null; then
    return 0
  fi

  echo "" >&2
  echo "jira-swarms requires a Jira CLI ('jira' command) configured for your Jira server." >&2

  case "$OS_NAME" in
    Darwin)
      if command -v brew &>/dev/null; then
        echo "Detected macOS with Homebrew." >&2
        if interactive && prompt_yes "Install the open-source 'go-jira' CLI via Homebrew now?"; then
          if brew install go-jira; then
            echo "Installed 'go-jira' Jira CLI successfully." >&2
            return 0
          else
            echo "Warning: Homebrew install of 'go-jira' failed." >&2
          fi
        fi
      fi
      echo "Please install a Jira CLI that provides the 'jira' command (e.g. 'go-jira') and ensure it is on your PATH." >&2
      echo "See: https://github.com/go-jira/jira" >&2
      ;;
    Linux)
      if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "debian" ]]; then
        echo "Detected Ubuntu/Debian." >&2
        echo "Install a Jira CLI that provides the 'jira' command (e.g. 'go-jira') using your package manager or Go tooling." >&2
        echo "Example (run manually with the appropriate privileges):" >&2
        echo "  # Using apt and Go (pseudo example, adjust to your environment)" >&2
        echo "  sudo apt update && sudo apt install -y golang-go" >&2
        echo "  GO111MODULE=on go install github.com/go-jira/jira/cmd/jira@latest" >&2
      else
        echo "Please install a Jira CLI that provides the 'jira' command (e.g. 'go-jira') using your OS package manager or Go tooling." >&2
      fi
      echo "See: https://github.com/go-jira/jira" >&2
      ;;
    *)
      echo "Unknown or unsupported platform ('$OS_NAME')." >&2
      echo "Please install a Jira CLI that provides the 'jira' command (e.g. 'go-jira') manually." >&2
      echo "See: https://github.com/go-jira/jira" >&2
      ;;
  esac

  return 1
}

if ! ensure_git; then
  exit 1
fi

if ! ensure_jira_cli; then
  echo "Jira CLI is required for jira-swarms; install it and rerun this installer." >&2
  exit 1
fi

echo "Installing to $INSTALL_DIR from $REPO_URL ..."
mkdir -p "$(dirname "$INSTALL_DIR")"
git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"

echo ""
echo "Installed successfully to $INSTALL_DIR"
echo ""
echo "Next steps:"
echo "  1. Open your app repo in Cursor (git repo required)."
echo "  2. In Cursor, run: run jira-swarms on PROJ-101 PROJ-102"
echo "     - The skill code is at: $INSTALL_DIR"
echo "     - The skill will default to:"
echo "         MULTI_JIRA_SKILL_DIR = the install dir above"
echo "         JIRA_GIT_REPO_DIR    = your current Cursor workspace repo root"
echo "         JIRA_WORKTREE_BASE   = ~/.jira-swarms/worktrees/<project-id>"
echo "     - On first use for each repo, jira-swarms will guide you through a short setup to create"
echo "       ~/.jira-swarms/config/<project-id>.env with project-specific Jira, PR provider, and"
echo "       worktree copy-path settings (no need to hard-code global tokens in your shell)."
echo ""
echo "  3. Per-project config and overrides live under ~/.jira-swarms/config/<project-id>.env."
echo "     You can use that file to set Jira credentials, Bitbucket/GitHub settings,"
echo "     JIRA_WORKTREE_COPY_PATHS, and override JIRA_GIT_REPO_DIR, JIRA_WORKTREE_BASE, etc."
echo ""
echo "Docs: $INSTALL_DIR/README.md, $INSTALL_DIR/docs/custom-login-flow.md"
