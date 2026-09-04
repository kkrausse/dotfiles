#!/bin/sh

# One-time migration from the old symlink layout to machine-local entry points.
# Existing real files are never overwritten. Removed symlinks are retained with
# a .pre-import-symlink suffix so the migration is easy to inspect or undo.

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
expected_root=$HOME/Documents/repos/kkrausse/dotfiles

if [ "$repo_root" != "$expected_root" ]; then
  echo "Repository is at $repo_root"
  echo "Edit the paths in bootstrap/ before running this migration."
  exit 1
fi

replace_file_link() {
  source_file=$1
  target_file=$2
  backup_file=$target_file.pre-import-symlink

  if [ -L "$target_file" ]; then
    if [ -e "$backup_file" ] || [ -L "$backup_file" ]; then
      echo "Refusing to replace $target_file: backup already exists."
      exit 1
    fi
    mv "$target_file" "$backup_file"
  elif [ -e "$target_file" ]; then
    echo "Keeping existing real file: $target_file"
    return
  fi

  mkdir -p "$(dirname -- "$target_file")"
  cp "$source_file" "$target_file"
  echo "Installed real file: $target_file"
}

# Capture identity while ~/.gitconfig still resolves through its old symlink.
git_name=$(git config --file "$HOME/.gitconfig" --get user.name 2>/dev/null || true)
git_email=$(git config --file "$HOME/.gitconfig" --get user.email 2>/dev/null || true)

replace_file_link "$repo_root/bootstrap/gitconfig" "$HOME/.gitconfig"
if [ -n "$git_name" ]; then
  git config --file "$HOME/.gitconfig" user.name "$git_name"
fi
if [ -n "$git_email" ]; then
  git config --file "$HOME/.gitconfig" user.email "$git_email"
fi

replace_file_link "$repo_root/bootstrap/tmux.conf" "$HOME/.tmux.conf"
replace_file_link "$repo_root/bootstrap/vimrc" "$HOME/.vimrc"
replace_file_link "$repo_root/bootstrap/ghostty_config" \
  "$HOME/.config/ghostty/config"

doom_dir=$HOME/.doom.d
doom_backup=$HOME/.doom.d.pre-import-symlink
if [ -L "$doom_dir" ]; then
  if [ -e "$doom_backup" ] || [ -L "$doom_backup" ]; then
    echo "Refusing to replace $doom_dir: backup already exists."
    exit 1
  fi
  mv "$doom_dir" "$doom_backup"
  mkdir -p "$doom_dir"
  cp "$repo_root/bootstrap/doom.d/"*.el "$doom_dir/"
  # Older checkouts tracked these local files. Preserve them when present.
  if [ -f "$repo_root/doom.d/custom.el" ]; then
    cp "$repo_root/doom.d/custom.el" "$doom_dir/custom.el"
  fi
  if [ -f "$repo_root/doom.d/machine-specific.el" ]; then
    cp "$repo_root/doom.d/machine-specific.el" "$doom_dir/machine-specific.el"
  fi
  echo "Installed real Doom directory: $doom_dir"
elif [ -e "$doom_dir" ]; then
  echo "Keeping existing real Doom directory: $doom_dir"
else
  mkdir -p "$doom_dir"
  cp "$repo_root/bootstrap/doom.d/"*.el "$doom_dir/"
  echo "Installed real Doom directory: $doom_dir"
fi

lsp_dir=$HOME/.lsp
lsp_backup=$HOME/.lsp.pre-import-symlink
if [ -L "$lsp_dir" ]; then
  if [ -e "$lsp_backup" ] || [ -L "$lsp_backup" ]; then
    echo "Refusing to replace $lsp_dir: backup already exists."
    exit 1
  fi
  mv "$lsp_dir" "$lsp_backup"
  cp -R "$repo_root/lsp" "$lsp_dir"
  echo "Copied LSP config (no native import available): $lsp_dir"
elif [ -e "$lsp_dir" ]; then
  echo "Keeping existing real LSP directory: $lsp_dir"
fi

echo "Migration complete. ~/.zshrc was already a real importing file."
