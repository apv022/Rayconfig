#!/usr/bin/env bash
# smoke — no dependencies, no root, no graphics. Run this before pushing.
#
#   ./test/smoke.sh
set -uo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FAIL=0

pass() { printf '  ok   %s\n' "$*"; }
fail() {
	printf '  FAIL %s\n' "$*"
	FAIL=$((FAIL + 1))
}

printf 'syntax\n'
while IFS= read -r -d '' f; do
	[ -f "$f" ] || continue
	case $(head -n1 "$f") in
	*'bash'*) bash -n "$f" && pass "${f#"$ROOT"/}" || fail "${f#"$ROOT"/}" ;;
	*'sh'*) sh -n "$f" && pass "${f#"$ROOT"/}" || fail "${f#"$ROOT"/}" ;;
	esac
done < <(find "$ROOT/bin" "$ROOT/bootstrap" "$ROOT/install.sh" -type f -print0)
sh -n "$ROOT/install.sh" || fail "install.sh"

printf '\nthemes\n'
keys() { grep -vE '^[[:space:]]*(#|$)' "$1" | cut -d= -f1 | sort; }
if [ "$(keys "$ROOT/themes/sunset/palette")" = "$(keys "$ROOT/themes/sunny/palette")" ]; then
	pass "sunset/sunny palette parity"
else
	fail "palette keys differ"
fi

printf '\nrender (into a copy)\n'
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R "$ROOT/dots" "$ROOT/themes" "$tmp/"
for theme in sunset sunny; do
	if RAY_RENDER_ROOT="$tmp" XDG_CONFIG_HOME="$tmp/none" XDG_STATE_HOME="$tmp/state" \
		"$ROOT/bin/gen-theme" "$theme" >/dev/null; then
		pass "gen-theme $theme"
	else
		fail "gen-theme $theme"
		continue
	fi
	bad=$(find "$tmp/dots" -type f ! -name '*.in' -exec grep -lE '@[A-Za-z_][A-Za-z0-9_]*@' {} + 2>/dev/null || true)
	if [ -n "$bad" ]; then
		fail "$theme: unresolved @tokens@ in: $bad"
	else
		pass "$theme: all tokens resolved"
	fi
	if grep -q 'set \$bg ' "$tmp/dots/sway/config.d/00-colors.conf"; then
		pass "$theme: sway colors generated"
	else
		fail "$theme: sway colors missing"
	fi
	if [ -s "$tmp/state/rayconfig/theme.sh" ]; then
		pass "$theme: theme.sh written"
	else
		fail "$theme: theme.sh missing"
	fi
	section=dark
	[ "$theme" = sunny ] && section=light
	if grep -q "^\[colors-$section\]" "$tmp/dots/foot/foot.ini" &&
		grep -q "^initial-color-theme=$section" "$tmp/dots/foot/foot.ini" &&
		! sed -n '/^\[main\]/,/^\[/p' "$tmp/dots/foot/foot.ini" | grep -q '^alpha='; then
		pass "$theme: foot colors section and alpha placement"
	else
		fail "$theme: foot.ini uses the wrong foot color dialect"
	fi
done

printf '\nbehavior\n'
out=$( "$ROOT/bin/status" --once 2>/dev/null || true)
case $out in
'['*']') pass "status --once looks like i3bar JSON" ;;
*) fail "status --once output: ${out:-<empty>}" ;;
esac

keyout=$("$ROOT/bin/keys" 2>/dev/null || true)
if printf '%s' "$keyout" | grep -q 'Super+Return'; then
	pass "keys parses the binds file"
else
	fail "keys produced nothing usable"
fi

for theme in sunset sunny; do
	if [ -s "$ROOT/themes/$theme/wallpaper.png" ]; then
		pass "$theme wallpaper present"
	else
		fail "$theme wallpaper missing"
	fi
done

printf '\n'
if [ "$FAIL" -gt 0 ]; then
	printf '%d failure(s)\n' "$FAIL"
	exit 1
fi
printf 'smoke: clean\n'
