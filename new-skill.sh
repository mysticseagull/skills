#!/usr/bin/env bash
# new-skill.sh — scaffold a new skill by copying a template.
#
# Usage: ./new-skill.sh [template] [skill-name] [dest-dir]
#
#   [template]    folder under templates/ (e.g. minimal, full).
#                 Omit to pick from an interactive menu.
#   [skill-name]  kebab-case name for the new skill (also the folder name).
#                 Omit to be prompted.
#   [dest-dir]    where to create it (default: current directory).
#
# Copies templates/<template> to <dest-dir>/<skill-name> and rewrites the
# SKILL.md `name:` field to match the new folder name.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
templates_dir="$repo_root/templates"

# collect available templates (folders under templates/ with a SKILL.md)
templates=()
for d in "$templates_dir"/*/; do
  [[ -f "$d/SKILL.md" ]] && templates+=("$(basename "$d")")
done
if [[ ${#templates[@]} -eq 0 ]]; then
  echo "error: no templates found under $templates_dir" >&2
  exit 1
fi

is_template() { local t="$1" x; for x in "${templates[@]}"; do [[ "$x" == "$t" ]] && return 0; done; return 1; }

template="${1:-}"
skill_name="${2:-}"
dest_dir="${3:-$PWD}"

# --- choose a template (interactive if missing or unknown) ---
if [[ -n "$template" ]] && ! is_template "$template"; then
  echo "Unknown template: '$template'" >&2
  template=""
fi
if [[ -z "$template" ]]; then
  if [[ ! -t 0 ]]; then
    echo "error: no template given and no terminal to prompt from." >&2
    echo "usage: ./new-skill.sh [template] [skill-name] [dest-dir]" >&2
    printf 'available templates: %s\n' "${templates[*]}" >&2
    exit 1
  fi
  echo "Select a template:"
  PS3="Template number: "
  select choice in "${templates[@]}"; do
    if [[ -n "${choice:-}" ]]; then template="$choice"; break; fi
    echo "Invalid selection — enter a number from the list."
  done
fi

# --- skill name (prompt if missing) ---
if [[ -z "$skill_name" ]]; then
  if [[ ! -t 0 ]]; then
    echo "error: no skill name given and no terminal to prompt from." >&2
    exit 1
  fi
  read -rp "Skill name (kebab-case): " skill_name
fi

# validate skill name: kebab-case only
if [[ ! "$skill_name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
  echo "error: skill name must be kebab-case (lowercase, digits, hyphens): '$skill_name'" >&2
  exit 1
fi

dest="$dest_dir/$skill_name"
if [[ -e "$dest" ]]; then
  echo "error: '$dest' already exists — pick another name or remove it first" >&2
  exit 1
fi

mkdir -p "$dest_dir"
cp -r "$templates_dir/$template" "$dest"

# rewrite the frontmatter `name:` to match the folder name
skill_md="$dest/SKILL.md"
if grep -qE '^name:' "$skill_md"; then
  # only the first `name:` line, which lives in the frontmatter
  sed -i "0,/^name:.*/s//name: $skill_name/" "$skill_md"
else
  echo "warning: no 'name:' field found in $skill_md — set it manually" >&2
fi

# keep any bundled scripts executable
if [[ -d "$dest/scripts" ]]; then
  find "$dest/scripts" -type f -name '*.sh' -exec chmod +x {} +
fi

echo "Created skill '$skill_name' from template '$template':"
echo "  $dest"
echo ""
echo "Next steps:"
echo "  1. Edit $skill_md — write the description and guidance (fill in <...> placeholders)."
[[ -d "$dest/references" ]] && echo "  2. Flesh out the guides under $dest/references/."
[[ -d "$dest/scripts" ]]    && echo "  3. Implement the helper(s) under $dest/scripts/."
echo "  4. Add a row for it to the skills table in README.md."
