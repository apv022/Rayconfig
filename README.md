# ☀ Rayconfig

A minimal Wayland desktop you own. Arch + sway, zero plugins, zero plugin
frameworks, zero AUR. Built-in bar, built-in lock/idle/wallpaper, and a
handful of shell utilities instead of an ecosystem.

The palette is solarvim's: warm suns, amber, and deep crimson, with a dark
"sunset" and light "sunny" variant. One palette file drives the terminal,
the compositor, notifications, the launcher, and Neovim.

```
themes/<name>/palette  ──►  bin/gen-theme  ──►  every config that has color
```

## Install

Read it first. It's a shell script that runs sudo.

```sh
curl -fsSL https://raw.githubusercontent.com/apv022/Rayconfig/refs/tags/v0.1.0/install.sh | sh
```

From a checkout instead:

```sh
./install.sh              # same thing, no clone
./install.sh --dry-run    # print every action, touch nothing
./install.sh --check      # verify an existing install, change nothing
```

Options: `--only <stages>`, `--skip <stages>`, `--yes`, `--extras`,
`--services`, `--theme sunny|sunset`.

The repo installs itself to `~/.local/share/rayconfig` and symlinks your
configs into it, so that directory is the live system — `ray update` is a
`git pull` plus a re-link. Set `RAYCONFIG_DIR` to put it elsewhere. Never run
the installer from a temp checkout; it refuses.

### Why the URL has a tag in it

`raw.githubusercontent.com` is served by Fastly with `cache-control: max-age=300`
and it does not treat a query string as a different object, so `?v=2` does
**not** bust it. A `/main/` URL can and does serve a five-minute-stale installer
— which is how you end up running a version that symlinks your configs into a
`mktemp` directory.

So the documented URL is pinned to an immutable ref. The bootstrap script is
frozen at that tag; the code it installs is still the newest `main` (or
`RAYCONFIG_REF`). Releasing:

```sh
git tag -a v0.2.0 -m "…" && git push origin v0.2.0   # then bump this README
```

## What it assumes

A **working Arch install with a user and sudo**, plus `git` and `curl`
(`sudo pacman -S --needed git curl` — neither is in Arch's `base` package, so a
bare archinstall does not have them).

It does not partition disks, install a bootloader, or set up networking — those
are yours, and they should be. It installs packages, links configs, renders the
theme, and verifies.

Safe to re-run. Existing non-symlink configs are moved to
`~/.config-backup/<timestamp>/`, never deleted.

## Stages

| stage | does |
|---|---|
| `preflight` | Arch check, sudo, disk space, git |
| `packages` | `pacman -Syu --needed` from `bootstrap/packages.txt` |
| `link` | symlinks `dots/*` into `~/.config`, `bin/*` into `~/.local/bin` |
| `theme` | renders configs from `themes/$THEME/palette` |
| `services` | only with `--services` |
| `verify` | `bin/doctor` — binaries, links, palette parity, sway config, bar JSON |

## The stack, and why

| job | tool | why not the alternative |
|---|---|---|
| compositor | `sway` | ships bar, lock, idle, wallpaper, nag — one C stack. Hyprland is a plugin-shaped ecosystem. |
| bar | `swaybar` | the i3bar protocol is stdin JSON. Your bar is a shell script. No plugin API. |
| terminal | `foot` | native Wayland, ~4 libs, config is a file not a patch queue, instant with `--server`. |
| launcher | `fuzzel` | `fuzzel --dmenu` turns anything into a picker |
| notifications | `mako` | dumb renderer, `makoctl` for actions |
| colors | `bin/gen-theme` | 60 lines of sh + sed instead of a theme framework |
| state | sysfs / `wpctl` / `swaymsg` | no daemon, no DBus round-trips |

**On the terminal specifically:** `st` is X11 and works only through
XWayland, and its "config" is a pile of patches you now maintain forever.
Writing your own terminal means owning a VT parser and escape-sequence
correctness — that's the one place where writing it yourself loses. `foot`
is the st of Wayland: small, static-ish, fast, and *your config lives in this
repo*. Alacritty still works if you want it (`--extras`); it's just a bigger
build and needs a multiplexer for splits.

## Keys

`$mod` is Super. `$mod+Shift+slash` prints the live list, generated from the
comments in `dots/sway/config.d/30-binds.conf`.

| key | action |
|---|---|
| `Super+Return` | terminal |
| `Super+d` | launcher |
| `Super+q` | close window |
| `Super+1..9` | workspace |
| `Super+Shift+1..9` | move window to workspace |
| `Super+hjkl` | focus |
| `Super+Shift+hjkl` | move |
| `Super+space` | float toggle |
| `Super+f` | fullscreen |
| `Super+t` | toggle sunny/sunset |
| `Super+Shift+s` | screenshot region → clipboard |
| `Print` | screenshot full → `~/Pictures/screenshots` |
| `Super+Shift+r` | reload sway |
| `Super+Shift+e` | exit |

## Layout

```
install.sh              the only thing you curl; installs the repo to ~/.local/share/rayconfig
bootstrap/              installer stages, package lists
bin/                    ray, status, theme, gen-theme, doctor, keys, vol, bright, shot
dots/                   hand-written configs; *.in files are templates
templates/              outputs that live outside the repo (solarvim colorscheme)
themes/                 palette files, one directory per theme
test/                   smoke test, no deps
```

**Editing rule:** edit `*.in`, never the generated file next to it. Generated
files are gitignored and rebuilt by `ray theme`.

## After install

Log into a TTY and run `exec sway`. Then:

```sh
ray doctor        # the same verification the installer runs
ray theme sunny   # or sunset, or toggle
ray update        # git pull + re-link + re-render
ray keys          # cheat sheet
```

## Roadmap (deliberately not in v0.1)

- `state/` — one long-lived daemon that owns volume/battery/workspaces and
  publishes them on a socket, instead of each script reading sysfs.
- OSD for volume/brightness (mako-driven).
- Wallpaper generated from the palette (a few dozen lines writing a PNG).
- `svc` — small wrappers around `systemctl --user` for the paranoid.

## License

MIT. Palette and Neovim colorscheme adapted from
[solarvim](https://github.com/apv022/SolarVim).
