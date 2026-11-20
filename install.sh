#!/bin/sh
# Rayconfig bootstrap.
#
# The only file you pipe to sh. Deliberately tiny: the auditable logic lives in
# the repo, not in the thing you curl.
#
#   curl -fsSL .../install.sh | sh          # on the Arch ISO: installs everything
#   curl -fsSL .../install.sh | sh          # on Arch: installs the desktop
#   ./install.sh --dry-run
#
# Two modes, picked automatically:
#
#   archiso  -> bootstrap/iso-install.sh: partitions, pacstraps, bootloader,
#               user, then Rayconfig. DESTROYS the target disk. Asks first.
#   Arch     -> installs the repo to ~/.local/share/rayconfig and runs the
#               config installer from there. Symlinks point into that
#               directory, so it has to outlive the process.
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

command -v git >/dev/null 2>&1 || die "git is required (pacman -S --needed git curl)"

# --- mode 1: live ISO -------------------------------------------------------
if [ -d /run/archiso ] && [ "$(id -u)" -eq 0 ]; then
	say "archiso detected: installing Arch + Rayconfig"
	say "this erases one disk — you will be asked which"
	tmp=$(mktemp -d)
	# shellcheck disable=SC2064
	trap "rm -rf '$tmp'" EXIT INT TERM HUP
	git clone --quiet --depth 1 --branch "$REF" "$REPO" "$tmp/rayconfig" ||
		die "could not clone $REPO ($REF)"
	"$tmp/rayconfig/bootstrap/iso-install.sh" "$@"
	exit 0
fi

# --- mode 2: existing checkout ---------------------------------------------
here=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || echo .)
if [ -f "$here/bootstrap/install.sh" ] && [ -d "$here/themes" ]; then
	exec "$here/bootstrap/install.sh" "$@"
fi

# --- mode 3: existing Arch system ------------------------------------------
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
