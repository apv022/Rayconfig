# shellcheck shell=bash
# Rayconfig helpers. Sourced by bootstrap/install.sh, never executed.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	R=$'\033[38;5;203m'; Y=$'\033[38;5;215m'
	G=$'\033[38;5;149m'; D=$'\033[38;5;244m'; Z=$'\033[0m'
else
	R=; Y=; G=; D=; Z=
fi

say()  { printf '%s==>%s %s\n' "$D" "$Z" "$*"; }
ok()   { printf '%s ok %s %s\n' "$G" "$Z" "$*"; }
warn() { printf '%swarn%s %s\n' "$Y" "$Z" "$*" >&2; }
die()  { printf '%sfail%s %s\n' "$R" "$Z" "$*" >&2; exit 1; }

# run: honours --dry-run. Pass the whole command.
run() {
	if [ "${DRY:-0}" = 1 ]; then
		printf '  %s+%s %s\n' "$D" "$Z" "$*"
		return 0
	fi
	"$@"
}

# ask: skippable with --yes (or when stdin isn't a tty).
ask() {
	[ "${YES:-0}" = 1 ] && return 0
	if [ ! -t 0 ]; then
		warn "not a tty, assuming yes: $*"
		return 0
	fi
	printf '%s?%s %s [y/N] ' "$Y" "$Z" "$*"
	read -r reply
	case $reply in y | Y | yes | YES) return 0 ;; *) return 1 ;; esac
}
