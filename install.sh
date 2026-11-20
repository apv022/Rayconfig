#!/bin/sh
# Rayconfig bootstrap.
#
# The only file you pipe to sh. It clones the repo at a pinned ref and hands
# over to bootstrap/install.sh. Deliberately tiny: the auditable logic lives
# in the repo, not in the thing you curl.
#
#   curl -fsSL .../install.sh | sh
#   ./install.sh --dry-run
#
# Override with: RAYCONFIG_REPO, RAYCONFIG_REF

set -eu

REPO=${RAYCONFIG_REPO:-https://github.com/apv022/Rayconfig.git}
REF=${RAYCONFIG_REF:-main}

# If we're inside a checkout, run that instead of cloning ourselves.
here=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || echo .)
if [ -f "$here/bootstrap/install.sh" ] && [ -d "$here/themes" ]; then
	exec "$here/bootstrap/install.sh" "$@"
fi

command -v git >/dev/null 2>&1 || {
	echo "rayconfig: git is required" >&2
	exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM HUP

if ! git clone --quiet --depth 1 --branch "$REF" "$REPO" "$tmp/rayconfig"; then
	echo "rayconfig: could not clone $REPO ($REF)" >&2
	exit 1
fi

"$tmp/rayconfig/bootstrap/install.sh" "$@"
