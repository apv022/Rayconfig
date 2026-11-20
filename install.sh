#!/bin/sh
# Rayconfig bootstrap.
#
# The only file you pipe to sh. Deliberately tiny: the auditable logic lives in
# the repo, not in the thing you curl.
#
#   curl -fsSL .../install.sh | sh
#   ./install.sh --dry-run
#
# It installs the repo itself to ~/.local/share/rayconfig (override with
# RAYCONFIG_DIR) and runs the installer from there. That matters: the dotfile
# symlinks point into this directory, so it has to outlive the process. A
# temp-dir clone would leave you with dangling configs.
#
# Override with: RAYCONFIG_REPO, RAYCONFIG_REF, RAYCONFIG_DIR

set -eu

REPO=${RAYCONFIG_REPO:-https://github.com/apv022/Rayconfig.git}
REF=${RAYCONFIG_REF:-main}
DEST=${RAYCONFIG_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/rayconfig}

say() { printf '==> %s\n' "$*"; }
die() {
	printf 'rayconfig: %s\n' "$*" >&2
	exit 1
}

# Already inside a checkout? Use it as-is.
here=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || echo .)
if [ -f "$here/bootstrap/install.sh" ] && [ -d "$here/themes" ]; then
	exec "$here/bootstrap/install.sh" "$@"
fi

command -v git >/dev/null 2>&1 || die "git is required"

if [ -d "$DEST/.git" ]; then
	say "updating $DEST"
	# ff-only: never merge or discard local work. A dirty tree is a warning,
	# not a reason to wipe someone's edits.
	if ! git -C "$DEST" pull --quiet --ff-only; then
		printf 'rayconfig: could not fast-forward %s (local changes?); using it as-is\n' "$DEST" >&2
	fi
else
	[ -e "$DEST" ] && die "$DEST exists and is not a git checkout; move it aside"
	say "installing to $DEST"
	mkdir -p "$(dirname "$DEST")"
	git clone --quiet --depth 1 --branch "$REF" "$REPO" "$DEST" ||
		die "could not clone $REPO ($REF)"
fi

exec "$DEST/bootstrap/install.sh" "$@"
