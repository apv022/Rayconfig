# shellcheck shell=bash
# Rayconfig shell setup. ~/.bashrc sources this with one line the installer
# adds; delete that line to opt out. No framework, no prompt engine: the
# colours are the terminal's ANSI ones, so the prompt follows the theme.

case $- in *i*) ;; *) return 0 ;; esac

export TERMINAL=${TERMINAL:-foot}
export EDITOR=${EDITOR:-nvim}

HISTSIZE=20000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize globstar 2>/dev/null

alias ls='ls --color=auto --group-directories-first'
alias ll='ls -lh'
alias la='ls -lAh'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias n='NVIM_APPNAME=solarvim nvim'

# fm: browse with muhfm, and land in the folder you quit from
fm() {
	local f d
	f=$(mktemp) || return
	muhfm --choosedir="$f" "$@"
	d=$(cat "$f" 2>/dev/null)
	rm -f "$f"
	[ -d "$d" ] && [ "$d" != "$PWD" ] && cd -- "$d" || return 0
}

# git branch without git: read .git/HEAD walking up (fast, no subprocess)
__ray_branch() {
	local d=$PWD h
	while :; do
		if [ -f "$d/.git/HEAD" ]; then
			read -r h <"$d/.git/HEAD"
			case $h in ref:*) printf ' %s' "${h##*/}" ;; *) printf ' %.7s' "$h" ;; esac
			return
		fi
		[ -z "$d" ] || [ "$d" = / ] && return
		d=${d%/*}
	done
}

# ~/src/rayconfig main
# ❯                      (red when the last command failed)
__ray_prompt() {
	local s=$?
	local c='\[\e[32m\]'
	[ "$s" -ne 0 ] && c='\[\e[31m\]'
	PS1="\n\[\e[1;33m\]\w\[\e[0;2m\]$(__ray_branch)\[\e[0m\]\n$c❯\[\e[0m\] "
}
PROMPT_COMMAND=__ray_prompt
