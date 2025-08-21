#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

# Move to repository root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

normalize_folder() {
  local src="SImphoniMacOS"
  local dst="SimphoniMacOS"
  if [[ -d "$src" ]]; then
    if [[ -d "$dst" ]]; then
      log "Merging '$src' into existing '$dst'"
      local ts="$(date +%Y%m%d%H%M%S)"
      local backup="$dst/_backup_conflicts/$ts"
      mkdir -p "$backup"
      # Ensure directory structure exists in destination
      (cd "$src" && find . -type d | tail -n +2 | while read -r d; do
        mkdir -p "$dst/${d#./}"
      done)
      # Move files
      (cd "$src" && find . -type f | while read -r f; do
        local src_file="$src/${f#./}"
        local dest_file="$dst/${f#./}"
        if [[ -e "$dest_file" ]]; then
          log "Conflict for ${f#./}; moving source to backup"
          mkdir -p "$backup/$(dirname "${f#./}")"
          mv "$src_file" "$backup/${f#./}"
        else
          log "Moving ${f#./} to '$dst'"
          mkdir -p "$(dirname "$dest_file")"
          mv "$src_file" "$dest_file"
        fi
      done)
      log "Removing old directory '$src'"
      rm -rf "$src"
    else
      log "Renaming '$src' to '$dst'"
      mv "$src" "$dst"
    fi
  else
    log "'$src' not found; no normalization needed"
  fi
}

cleanup_cruft() {
  log "Removing .DS_Store files"
  find . -name '.DS_Store' -print -delete

  if [[ -d "__MACOSX" ]]; then
    log "Removing __MACOSX directory"
    rm -rf "__MACOSX"
  fi

  log "Removing xcuserdata directories"
  find . -name 'xcuserdata' -type d -print | while read -r dir; do
    rm -rf "$dir"
  done

  ensure_gitignore
}

ensure_gitignore() {
  local gitignore=".gitignore"
  local lines=(
    ".DS_Store"
    "__MACOSX/"
    "build/"
    "DerivedData/"
    "*.xcuserdata/"
    "xcuserdata/"
    "*.xcuserstate"
  )
  touch "$gitignore"
  for line in "${lines[@]}"; do
    if ! grep -Fxq "$line" "$gitignore"; then
      log "Adding '$line' to $gitignore"
      echo "$line" >> "$gitignore"
    fi
  done
}

flatten_mmi() {
  local outer_mmi="SimphoniMacOS/SimphoniMMI/SimphoniMMI"
  local inner_mmi="$outer_mmi/SimphoniMMI"
  local inner_tests="$outer_mmi/SimphoniMMITests"
  if [[ -d "$inner_mmi" || -d "$inner_tests" ]]; then
    local ts="$(date +%Y%m%d%H%M%S)"
    local backup="SimphoniMacOS/SimphoniMMI/_backup_nested_$ts"
    log "Creating backup directory $backup"
    mkdir -p "$backup"

    if [[ -d "$inner_mmi" ]]; then
      log "Processing INNER_MMI at $inner_mmi"
      (cd "$inner_mmi" && find . -type f | while read -r f; do
        local src_file="$inner_mmi/${f#./}"
        local dest_file="$outer_mmi/${f#./}"
        if [[ -f "$dest_file" ]]; then
          if [[ "$(shasum -a 256 "$src_file" | cut -d' ' -f1)" == "$(shasum -a 256 "$dest_file" | cut -d' ' -f1)" ]]; then
            log "Duplicate identical file ${f#./}; removing inner copy"
            rm "$src_file"
          else
            log "Differing file ${f#./}; moving to backup"
            mkdir -p "$backup/SimphoniMMI/$(dirname "${f#./}")"
            mv "$src_file" "$backup/SimphoniMMI/${f#./}"
          fi
        else
          log "Unique file ${f#./}; moving to backup"
          mkdir -p "$backup/SimphoniMMI/$(dirname "${f#./}")"
          mv "$src_file" "$backup/SimphoniMMI/${f#./}"
        fi
      done)
      log "Removing INNER_MMI directory $inner_mmi"
      rm -rf "$inner_mmi"
    else
      log "INNER_MMI directory not found; skipping"
    fi

    if [[ -d "$inner_tests" ]]; then
      local outer_tests="SimphoniMacOS/SimphoniMMI/SimphoniMMITests"
      log "Processing INNER_TESTS at $inner_tests"
      (cd "$inner_tests" && find . -type f | while read -r f; do
        local src_file="$inner_tests/${f#./}"
        local dest_file="$outer_tests/${f#./}"
        if [[ -f "$dest_file" ]]; then
          if [[ "$(shasum -a 256 "$src_file" | cut -d' ' -f1)" == "$(shasum -a 256 "$dest_file" | cut -d' ' -f1)" ]]; then
            log "Duplicate identical test file ${f#./}; removing inner copy"
            rm "$src_file"
          else
            log "Differing test file ${f#./}; moving to backup"
            mkdir -p "$backup/SimphoniMMITests/$(dirname "${f#./}")"
            mv "$src_file" "$backup/SimphoniMMITests/${f#./}"
          fi
        else
          log "Unique test file ${f#./}; moving to backup"
          mkdir -p "$backup/SimphoniMMITests/$(dirname "${f#./}")"
          mv "$src_file" "$backup/SimphoniMMITests/${f#./}"
        fi
      done)
      log "Removing INNER_TESTS directory $inner_tests"
      rm -rf "$inner_tests"
    else
      log "INNER_TESTS directory not found; skipping"
    fi
  else
    log "No nested MMI directories found; skipping"
  fi
}

show_tree() {
  if [[ -d "SimphoniMacOS" ]]; then
    if command -v tree >/dev/null 2>&1; then
      log "Resulting tree for SimphoniMacOS (depth 3):"
      tree -L 3 "SimphoniMacOS"
    else
      log "tree command not available; using find to list structure"
      find "SimphoniMacOS" -maxdepth 3 | sort
    fi
  else
    warn "SimphoniMacOS directory missing; cannot show tree"
  fi
}

verify_result() {
  if [[ ! -d "SimphoniMacOS" ]]; then
    warn "SimphoniMacOS directory is missing after cleanup"
    exit 1
  fi
}

normalize_folder
cleanup_cruft
flatten_mmi
show_tree
verify_result

log "Cleanup step completed successfully"

