#!/usr/bin/env bash
# Rayconfig installer. Idempotent: safe to run as many times as you like.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=bootstrap/lib.sh
. "$ROOT/bootstrap/lib.sh"

CFG=${XDG_CONFIG_HOME:-$HOME/.config}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/rayconfig
LOCAL_BIN=$HOME/.local/bin
BACKUP_ROOT=$HOME/.config-backup
# keep the theme the user picked; re-running must never reset it
THEME=${RAYCONFIG_THEME:-$(cat "$STATE/theme" 2>/dev/null || echo sunset)}
SUDO=(sudo)

ALL_STAGES=(preflight packages link solarvim muhfm theme services verify)
ONLY=()
SKIP=()
DRY=0
YES=0
EXTRAS=0
SERVICES=0

usage() {
	cat <<'EOF'
usage: install.sh [options]

  --only a,b     run only these stages
  --skip a,b     skip these stages
  --check        verify an existing install (= --only verify)
  --dry-run      print what would happen, change nothing
  --yes          don't prompt
  --extras       also install bootstrap/optional.txt
  --services     enable system units (bluetooth)
  --theme NAME   sunset (default), sunny, dusk, moss

stages: preflight packages link solarvim muhfm theme services verify
EOF
}

while [ $# -gt 0 ]; do
	case $1 in
	--only)
		IFS=, read -r -a ONLY <<<"$2"
		shift 2
		;;
	--skip)
		IFS=, read -r -a SKIP <<<"$2"
		shift 2
		;;
	--check)
		ONLY=(verify)
		shift
		;;
	--dry-run)
		DRY=1
		shift
		;;
	--yes | -y)
		YES=1
		shift
		;;
	--extras)
		EXTRAS=1
		shift
		;;
	--services)
		SERVICES=1
		shift
		;;
	--theme)
		THEME=$2
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown argument: $1 (try --help)" ;;
	esac
done

wants() {
	local stage=$1 s
	if [ ${#ONLY[@]} -gt 0 ]; then
		for s in "${ONLY[@]}"; do [ "$s" = "$stage" ] && return 0; done
		return 1
	fi
	for s in "${SKIP[@]}"; do [ "$s" = "$stage" ] && return 1; done
	return 0
}

# ---------------------------------------------------------------- stages

stage_preflight() {
	say "preflight"

	[ "$(id -u)" -ne 0 ] || [ "${RAYCONFIG_ALLOW_ROOT:-0}" = 1 ] ||
		die "run as your user, not root (the script calls sudo itself; set RAYCONFIG_ALLOW_ROOT=1 in containers)"
	if [ "$(id -u)" -eq 0 ]; then
		warn "running as root; configs will land in $HOME"
		SUDO=()
	else
		SUDO=(sudo)
	fi
	[ -f /etc/os-release ] || die "no /etc/os-release; unsupported system"
	# shellcheck disable=SC1091
	local id; id=$(. /etc/os-release && printf '%s' "${ID:-unknown}")
	case $id in
	arch | cachyos | endeavouros) ok "distro: $id" ;;
	*) warn "distro is '$id', not Arch; package names may not resolve" ;;
	esac

	for cmd in git curl; do
		command -v "$cmd" >/dev/null 2>&1 ||
			die "missing: $cmd — install it first: sudo pacman -S --needed git curl"
	done
	ok "git, curl"

	command -v sudo >/dev/null 2>&1 || [ "$(id -u)" -eq 0 ] || die "missing: sudo"
	if [ "$DRY" = 0 ] && [ "$(id -u)" -ne 0 ]; then
		sudo -v || die "sudo failed"
		ok "sudo"
	fi

	local free
	free=$(df -Pk "$HOME" | awk 'NR==2 {print $4}')
	[ "${free:-0}" -gt 500000 ] || die "need ~500MB free in \$HOME, have ${free}K"
	ok "disk: $((free / 1024))MB free"

	# Symlinked configs point into $ROOT. A temp-dir checkout (e.g. a hand-rolled
	# `curl | sh` that clones to /tmp with mktemp) would leave dangling configs.
	case $ROOT in
	/tmp/tmp.* | /var/tmp/tmp.*)
		die "running from a temporary checkout ($ROOT); configs would dangle. Use install.sh, or clone somewhere permanent"
		;;
	esac
	ok "source: $ROOT"

	if [ ! -t 0 ]; then
		warn "stdin is not a tty (piped install); assuming --yes"
		YES=1
	fi

	[ -e "$STATE" ] || mkdir -p "$STATE"
}

stage_packages() {
	say "packages"

	local pkgs=()
	mapfile -t pkgs < <(grep -vE '^[[:space:]]*(#|$)' "$ROOT/bootstrap/packages.txt")

	# Arch does not support partial upgrades. -Syu is the only correct form.
	run "${SUDO[@]}" pacman -Syu --needed --noconfirm "${pkgs[@]}"
	ok "${#pkgs[@]} packages"

	# Settings TUIs: one at a time so a renamed/removed package can't block
	# the rest. Already-installed ones cost nothing (--needed).
	local t got=0 miss=()
	while IFS= read -r t; do
		if run "${SUDO[@]}" pacman -S --needed --noconfirm "$t" >/dev/null 2>&1; then
			got=$((got + 1))
		else
			miss+=("$t")
		fi
	done < <(grep -vE '^[[:space:]]*(#|$)' "$ROOT/bootstrap/tuis.txt")
	ok "$got settings apps"
	[ ${#miss[@]} -eq 0 ] || warn "not in the repos, using fallbacks: ${miss[*]}"
	if [ "$DRY" = 0 ] && systemctl list-unit-files power-profiles-daemon.service >/dev/null 2>&1; then
		"${SUDO[@]}" systemctl enable --now power-profiles-daemon.service >/dev/null 2>&1 || true
	fi

	if [ "$EXTRAS" = 1 ]; then
		local extra=()
		mapfile -t extra < <(grep -vE '^[[:space:]]*(#|$)' "$ROOT/bootstrap/optional.txt")
		run "${SUDO[@]}" pacman -S --needed --noconfirm "${extra[@]}"
		ok "${#extra[@]} extras"
	fi
}

# backup: move a real file or dir out of the way, never delete it
backup() {
	local dst=$1
	[ -e "$dst" ] || [ -L "$dst" ] || return 0
	[ -L "$dst" ] && return 0 # a symlink costs nothing to replace
	local dest
	dest="$BACKUP_ROOT/$STAMP/$(basename "$dst")"
	say "backing up $dst -> $dest"
	run mkdir -p "$BACKUP_ROOT/$STAMP"
	run mv "$dst" "$dest"
}

linkdir() {
	local src=$1 dst=$2
	if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
		ok "$dst"
		return 0
	fi
	backup "$dst"
	run ln -sfn "$src" "$dst"
	ok "$dst -> $src"
}

stage_link() {
	say "link"
	STAMP=$(date +%Y%m%d-%H%M%S)

	run mkdir -p "$CFG" "$LOCAL_BIN" "$BACKUP_ROOT"

	linkdir "$ROOT/dots/sway" "$CFG/sway"
	linkdir "$ROOT/dots/foot" "$CFG/foot"
	linkdir "$ROOT/dots/mako" "$CFG/mako"
	linkdir "$ROOT/dots/fuzzel" "$CFG/fuzzel"
	linkdir "$ROOT/dots/swaylock" "$CFG/swaylock"
	linkdir "$ROOT/dots/muhfm" "$CFG/muhfm"

	# bash: one line in ~/.bashrc sources the repo's rc (prompt, aliases, fm)
	local rc=$HOME/.bashrc line=". \"$ROOT/dots/shell/rc.sh\""
	if grep -qF "dots/shell/rc.sh" "$rc" 2>/dev/null; then
		ok "$rc sources dots/shell/rc.sh"
	else
		if [ "$DRY" = 1 ]; then
			printf '  + append to %s: %s\n' "$rc" "$line"
		else
			printf '\n# rayconfig: prompt, aliases, fm (cd on quit). Remove this line to opt out.\n[ -f "%s/dots/shell/rc.sh" ] && %s\n' "$ROOT" "$line" >>"$rc"
		fi
		ok "$rc -> dots/shell/rc.sh"
	fi

	local f
	for f in "$ROOT"/bin/*; do
		[ -f "$f" ] || continue
		run ln -sfn "$f" "$LOCAL_BIN/$(basename "$f")"
	done
	ok "bin -> $LOCAL_BIN"

	case ":$PATH:" in
	*":$LOCAL_BIN:"*) ok "PATH contains $LOCAL_BIN" ;;
	*) warn "$LOCAL_BIN is not on PATH; add it to your shell rc" ;;
	esac
}

# solarvim is its own repo; clone it next to rayconfig and let its own
# idempotent installer link ~/.config/solarvim. gen-theme then drops the
# palette-driven colors/ray.lua into it.
SV_REPO=${SOLARVIM_REPO:-https://github.com/apv022/SolarVim.git}
SV_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/solarvim
stage_solarvim() {
	say "solarvim"
	if [ -d "$SV_DIR/.git" ]; then
		run git -C "$SV_DIR" pull --quiet --ff-only || warn "solarvim has local changes; left as-is"
	elif [ -e "$SV_DIR" ]; then
		warn "$SV_DIR exists and is not a git checkout; skipped"
		return 0
	else
		run git clone --quiet --depth 1 "$SV_REPO" "$SV_DIR" || { warn "could not clone solarvim; skipped"; return 0; }
	fi
	run "$SV_DIR/install.sh" >/dev/null
	ok "solarvim -> $CFG/solarvim"
}

# muhfm, the file manager, is its own repo: one Go file, standard library only.
# Build it from source (official-repo `go`), rebuild only when it changed, and
# make it the default for folders so every app's "open folder" lands there.
MF_REPO=${MUHFM_REPO:-https://github.com/apv022/muhfm.git}
MF_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/muhfm
stage_muhfm() {
	say "muhfm"
	if [ -d "$MF_DIR/.git" ]; then
		run git -C "$MF_DIR" pull --quiet --ff-only || warn "muhfm has local changes; building them as-is"
	elif [ -e "$MF_DIR" ]; then
		warn "$MF_DIR exists and is not a git checkout; skipped"
		return 0
	else
		run git clone --quiet --depth 1 "$MF_REPO" "$MF_DIR" || { warn "could not clone muhfm; skipped"; return 0; }
	fi
	if [ "$DRY" = 0 ] && [ ! -f "$MF_DIR/main.go" ]; then
		warn "muhfm checkout has no main.go (old Python version?); skipped"
		return 0
	fi
	command -v go >/dev/null 2>&1 || [ "$DRY" = 1 ] || { warn "go is not installed; run: install.sh --only packages,muhfm"; return 0; }
	local rev
	rev=$(git -C "$MF_DIR" rev-parse HEAD 2>/dev/null || echo none)
	if [ -x "$LOCAL_BIN/muhfm" ] && [ "$(cat "$STATE/muhfm.rev" 2>/dev/null)" = "$rev" ]; then
		ok "muhfm up to date (${rev:0:7})"
	else
		# keep Go's caches out of ~/go
		run env GOPATH="${XDG_DATA_HOME:-$HOME/.local/share}/go" CGO_ENABLED=0 \
			go -C "$MF_DIR" build -trimpath -ldflags="-s -w" -o "$LOCAL_BIN/muhfm" . ||
			{ warn "muhfm failed to build"; return 0; }
		[ "$DRY" = 1 ] || { mkdir -p "$STATE" && printf '%s\n' "$rev" >"$STATE/muhfm.rev"; }
		ok "muhfm built (${rev:0:7}) -> $LOCAL_BIN/muhfm"
	fi
	run "$LOCAL_BIN/muhfm" --set-default >/dev/null
	run "$ROOT/bin/ray" _defaults
	ok "default apps: folders -> muhfm, text -> solarvim, images/video/pdf if installed"
}

stage_theme() {
	say "theme: $THEME"
	[ -d "$ROOT/themes/$THEME" ] || die "no such theme: $THEME (have: $(ls "$ROOT/themes" | tr '\n' ' '))"
	run "$ROOT/bin/gen-theme" "$THEME"
	run "$ROOT/bin/ray" _render
	# btop owns btop.conf and rewrites it; we only point it at our theme file
	local bc=$CFG/btop/btop.conf
	if [ "$DRY" = 0 ]; then
		mkdir -p "$CFG/btop"
		if [ -f "$bc" ] && grep -q '^color_theme' "$bc"; then
			sed -i 's|^color_theme.*|color_theme = "ray"|' "$bc"
		else
			printf 'color_theme = "ray"\n' >>"$bc"
		fi
	fi
	ok "rendered from themes/$THEME/palette"
}

stage_services() {
	say "services"
	if [ "$SERVICES" = 0 ]; then
		say "skipped (pass --services to enable bluetooth)"
		return 0
	fi
	run "${SUDO[@]}" systemctl enable --now bluetooth.service
	ok "bluetooth"

	# PipeWire user units are usually already enabled by the base install.
	for unit in pipewire pipewire-pulse wireplumber; do
		if systemctl --user list-unit-files "$unit.service" >/dev/null 2>&1; then
			run systemctl --user enable --now "$unit.service" || warn "$unit failed"
		fi
	done
	ok "audio units"
}

stage_verify() {
	say "verify"
	if [ "$DRY" = 1 ]; then
		printf '  + %s/bin/doctor\n' "$ROOT"
		return 0
	fi
	"$ROOT/bin/doctor" || die "verification failed — run 'ray doctor' for detail"
}

stage_done() {
	printf '\n'
	say "rayconfig installed"
	cat <<EOF
  log in on tty1 and run:   sway
  then:                     Super+/          every key
                            Super+Alt+Space  menu (update, theme, power)
                            ray update       update the whole system

  configs:  $CFG/{sway,foot,mako,fuzzel,swaylock,muhfm,solarvim}
  scripts:  $LOCAL_BIN/{ray,status,theme,gen-theme,doctor,keys,vol,bright,shot,snap,winlist}
  files:    $LOCAL_BIN/muhfm  (Super+E, default for folders)
  theme:    themes/$THEME/palette  (edit, then: ray theme $THEME)
  backups:  $BACKUP_ROOT
EOF
}

# ------------------------------------------------------------------- main

say "rayconfig from $ROOT"
[ "$DRY" = 1 ] && warn "dry run: nothing will be changed"

for stage in "${ALL_STAGES[@]}"; do
	wants "$stage" || continue
	"stage_$stage"
done

[ "${ONLY[*]:-}" = verify ] || stage_done
