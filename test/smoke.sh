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
ref=$(keys "$ROOT/themes/sunset/palette")
for p in "$ROOT"/themes/*/palette; do
	t=$(basename "$(dirname "$p")")
	if [ "$(keys "$p")" != "$ref" ]; then
		fail "$t: palette keys differ from sunset"
	elif ! grep -vE '^[[:space:]]*(#|$|variant=)' "$p" | grep -qvE '^[a-z0-9]+=#[0-9a-fA-F]{6}$'; then
		pass "$t: palette complete and well-formed"
	else
		fail "$t: malformed palette line"
	fi
	[ -s "${p%palette}wallpaper.jpg" ] || fail "$t: wallpaper.jpg missing"
done

printf '\nrender (into a copy)\n'
tmp=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] || rm -rf "$tmp"' EXIT
cp -R "$ROOT/dots" "$ROOT/themes" "$tmp/"
for tdir in "$ROOT"/themes/*/; do
	theme=$(basename "$tdir")
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
	if [ -s "$tmp/state/rayconfig/plymouth/rayconfig.script" ] &&
		grep -q 'SetBackgroundTopColor([0-9.]*, [0-9.]*, [0-9.]*)' "$tmp/state/rayconfig/plymouth/rayconfig.script"; then
		pass "$theme: boot splash rendered"
	else
		fail "$theme: boot splash missing or colours not floats"
	fi
	if [ -s "$tmp/state/rayconfig/theme.sh" ]; then
		pass "$theme: theme.sh written"
	else
		fail "$theme: theme.sh missing"
	fi
	section=$(sed -n 's/^variant=//p' "$ROOT/themes/$theme/palette")
	if grep -q "^\[colors-$section\]" "$tmp/dots/foot/foot.ini" &&
		grep -q "^initial-color-theme=$section" "$tmp/dots/foot/foot.ini" &&
		! sed -n '/^\[main\]/,/^\[/p' "$tmp/dots/foot/foot.ini" | grep -q '^alpha='; then
		pass "$theme: foot colors section and alpha placement"
	else
		fail "$theme: foot.ini uses the wrong foot color dialect"
	fi
done

printf '\nsettings render (empty, partial, full)\n'
for case in empty partial full; do
	st=$tmp/st-$case
	mkdir -p "$st/rayconfig" "$tmp/gen-$case"
	case $case in
	empty) : >"$st/rayconfig/settings" ;;
	partial) printf 'kb_layout=de\ngaps=0\n' >"$st/rayconfig/settings" ;;
	full) printf '%s\n' kb_layout=us,de kb_caps=caps:escape repeat_rate=50 mouse_accel=flat tap=enabled \
		gaps=12 border=title bar_position=bottom bar_background=clear workspace_layout=tabbed >"$st/rayconfig/settings" ;;
	esac
	if out=$(cd "$tmp" && XDG_STATE_HOME=$st bash -c 'eval "$(sed -n "/^get() {/,/^}/p" "$1")"; SETTINGS=$2/rayconfig/settings; SWAYGEN=$3/85.conf; in_sway() { false; }; eval "$(sed -n "/^render_settings() {/,/^}/p" "$1")"; set -euo pipefail; render_settings' _ "$ROOT/bin/ray" "$st" "$tmp/gen-$case" 2>&1) &&
		grep -q '^input "type:keyboard" {' "$tmp/gen-$case/85.conf"; then
		pass "render_settings: $case"
	else
		fail "render_settings: $case: $out"
	fi
done
grep -q '^bar main position bottom' "$tmp/gen-full/85.conf" && grep -q 'xkb_options grp:alt_shift_toggle,caps:escape' "$tmp/gen-full/85.conf" &&
	pass "full settings render bar and keyboard options" || fail "full settings render incomplete"

printf '\nbehavior\n'
out=$( "$ROOT/bin/status" --once 2>/dev/null || true)
case $out in
'['*']') pass "status --once looks like i3bar JSON" ;;
*) fail "status --once output: ${out:-<empty>}" ;;
esac

keyout=$("$ROOT/bin/keys" 2>/dev/null || true)
if printf '%s' "$keyout" | grep -q 'Super+Enter'; then
	pass "keys parses the binds file"
else
	fail "keys produced nothing usable"
fi

for theme in sunset sunny; do
	if [ -s "$ROOT/themes/$theme/wallpaper.jpg" ]; then
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
