# ☀ Rayconfig

A minimal Wayland desktop you own. Arch + sway, zero plugins, zero plugin
frameworks, no AUR. Built-in bar, built-in lock/idle/wallpaper, and a handful
of shell utilities instead of an ecosystem.

The palette is solarvim's: warm suns, amber and deep crimson, with a dark
"sunset" and light "sunny" variant. One palette file drives the terminal,
compositor, notifications, launcher, wallpaper and Neovim.

```
themes/<name>/palette  ──►  bin/gen-theme  ──►  every config that has color
```

## Install

### From the Arch ISO — the whole machine, one command

Boot the Arch ISO, connect to the network (`iwctl` for wifi), then:

```sh
curl -fsSL https://raw.githubusercontent.com/apv022/Rayconfig/refs/tags/v0.2.4/install.sh | sh
```

It detects archiso and runs `bootstrap/iso-install.sh`, which:

1. lists candidate disks (excluding the ISO medium) and asks which one to erase,
2. asks for a username and password, and for you to type the disk name back,
3. GPT-partitions the disk (1 GiB ESP + ext4 root on UEFI; bios_grub + ext4 on BIOS),
4. refreshes the keyring and `pacstrap`s Arch with a kernel, NetworkManager, sudo, git and curl,
5. writes bootloader, locale, timezone, users and sudoers,
6. installs Rayconfig into the new user's home and runs the config stage,
7. installs solarvim, makes `nvim` mean solarvim, and starts sway on tty1 login,
8. unmounts and tells you to reboot.

Non-interactive form (still prompts for the password, from `/dev/tty`):

```sh
curl -fsSL <same-url> | sh -s -- --disk /dev/vda --user apv --timezone Europe/Berlin --yes
```

`--dry-run` prints every action without touching a disk. `--fast-mirrors` runs
reflector first. This **destroys the target disk** — there is a typed confirmation
unless you pass `--yes`.

### On an existing Arch system

The same URL, no flags: it detects that you are not on the ISO and only
installs the desktop (packages, configs, theme, verify).

```sh
curl -fsSL https://raw.githubusercontent.com/apv022/Rayconfig/refs/tags/v0.2.4/install.sh | sh
./install.sh --dry-run
./install.sh --check
```

Options: `--only <stages>`, `--skip <stages>`, `--yes`, `--extras`, `--services`,
`--theme sunny|sunset`.

The repo installs itself to `~/.local/share/rayconfig` and symlinks your configs
into it, so that directory is the live system — `ray update` is a `git pull` plus
a re-link. Set `RAYCONFIG_DIR` to put it elsewhere. Never run the installer from
a temp checkout; it refuses.

The URL is pinned to a tag on purpose. `raw.githubusercontent.com` is
Fastly-cached with `max-age=300` and ignores query strings in its cache key, so
a `/main/` URL can serve a stale installer for five minutes. A tag URL cannot.
The bootstrap itself is frozen at that tag; the code it installs is still the
newest `main` (or `RAYCONFIG_REF`). Releasing:

```sh
git tag -a vX.Y.Z -m "…" && git push origin vX.Y.Z   # then bump this README
```

## Installed system

| job | tool | why not the alternative |
|---|---|---|
| compositor | `sway` | ships bar, lock, idle, wallpaper, nag — one C stack |
| bar | `swaybar` | the i3bar protocol is stdin JSON; the bar is a shell script |
| terminal | `foot` | native Wayland, ~5 libs, config is a file, instant with `--server` |
| launcher | `fuzzel` | `fuzzel --dmenu` turns anything into a picker |
| notifications | `mako` | dumb renderer, `makoctl` for actions |
| wallpaper | `swaybg` + generated PNG | gradient derived from the palette, no wallpaper daemon |
| colors | `bin/gen-theme` | 70 lines of sh + sed instead of a theme framework |

**On the terminal:** `st` is X11-only (XWayland) and its config is a patch queue
you maintain forever. Writing your own means owning a VT parser. `foot` is the
st of Wayland. Alacritty is available with `--extras` if you want to A/B it.

## Everyday use

| | |
|---|---|
| `Super+/` | **cheat sheet** — every desktop and editor shortcut, generated from the configs |
| `Super+Alt+Space` | menu: update, theme, keys, doctor, lock, suspend, reboot, power off |
| `Super+Escape` | power menu |
| `ray update` | updates Arch, rayconfig and solarvim, re-renders, checks, tells you if a reboot is due |
| bar | shows `↑ N updates` when Arch has updates (checked every 30 min) |

Mod is Super and behaves like Windows: `Super+Left/Right` snap, `Up/Down`
maximise/restore, `Tab` switch window, `E` files, `L` lock, `Enter` terminal,
`D` launcher, `N` editor, `T` sunny/sunset. Run `ray keys` for the full list.
For vim-style `h/j/k/l` focus, add binds to `~/.config/sway/config.d/90-local.conf`
(gitignored); `ray edit local` opens it.

The cheat sheet has no second copy to maintain: sway's comes from the
`## section` / `# description` comments in `dots/sway/config.d/30-binds.conf`,
solarvim's from the table that creates its mappings.

## Layout

```
install.sh                 entry point: archiso -> full disk install, Arch -> config install
bootstrap/iso-install.sh   partitioning, pacstrap, bootloader, users, handoff
bootstrap/                 installer stages, package lists
bin/                       ray, status, theme, gen-theme, doctor, keys, vol,
                           bright, shot, snap, winlist
dots/                      hand-written configs; *.in files are templates
templates/                 outputs that live outside the repo (solarvim colorscheme)
themes/                    palette files + generated wallpaper PNGs
tools/make-wallpaper.py    dev tool: regenerate wallpapers from a palette
test/smoke.sh              dependency-free smoke test
```

**Editing rule:** edit `*.in`, never the generated file next to it. Generated
files are gitignored and rebuilt by `ray theme`. Wallpapers are generated by
the dev tool and committed; any monitor size is fine (`-m fill`).

## After install

Log in on tty1; sway starts by itself (opt out: `touch ~/.config/rayconfig-no-autostart`).
On an existing Arch box, log in on a TTY and type `sway`.

```sh
ray doctor        # health check, read-only
ray update        # everything up to date
ray theme sunny   # or sunset, or toggle — also swaps wallpaper, lock screen, editor
ray keys          # cheat sheets (sway | vim)
ray edit          # open the repo in solarvim
```

## Roadmap

- OSD for volume/brightness via mako.
- Rounded corners / blur are not possible without swayfx (a sway fork, AUR).
  Deliberately left out.

## Working on the repo

Read `CLAUDE.md` (also linked as `AGENTS.md`) before changing anything. It has
the ethos, the non-negotiables, the landmines already hit, and the exact
verification commands. Do not "improve" the design by adding plugins, a bar
framework, AUR packages or a second source of truth for colour.

## License

MIT. Palette and Neovim colorscheme adapted from
[solarvim](https://github.com/apv022/SolarVim).
