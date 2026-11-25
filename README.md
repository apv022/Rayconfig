# ☀ Rayconfig

A minimal Wayland desktop you own. Arch + sway, zero plugins, zero plugin
frameworks, no AUR. Built-in bar, built-in lock/idle/wallpaper, and a handful
of shell utilities instead of an ecosystem.

Everything Omarchy gives you — menus for everything, one-key themes that
restyle every app, screenshots and recording, clipboard history, an emoji
picker, web apps, OSD, a screensaver — as small shell functions you can read,
plus [muhfm](https://github.com/apv022/muhfm), a one-file Go file manager that
does what Dolphin does.

17 themes ship: sunset and sunny (solarvim's own), dusk, moss, graphite, jade,
and ports of Tokyo Night, Catppuccin (Mocha and Latte), Gruvbox, Nord,
Everforest, Kanagawa, Rosé Pine (and Dawn), Flexoki Light and Ristretto. One
palette file drives the terminal, compositor, bar, notifications, launcher,
lock screen, file manager, btop, GTK's light/dark choice, wallpaper and Neovim.

```
themes/<name>/palette  ──►  bin/gen-theme  ──►  every config that has color
```

## Install

### From the Arch ISO — the whole machine, one command

Boot the Arch ISO, connect to the network (`iwctl` for wifi), then:

```sh
curl -fsSL https://raw.githubusercontent.com/apv022/Rayconfig/refs/heads/main/install.sh | sh
```

It detects archiso and runs `bootstrap/iso-install.sh`, which:

1. lists candidate disks (excluding the ISO medium) and asks which one to erase,
2. asks for a username and password, and for you to type the disk name back,
3. GPT-partitions the disk (1 GiB ESP + root on UEFI; bios_grub + 1 GiB /boot + root on BIOS)
   and **encrypts the root with LUKS2** — the same password you log in with
   unlocks it at boot (`--no-encrypt` to skip),
4. refreshes the keyring and `pacstrap`s Arch with a kernel, NetworkManager, sudo, git and curl,
5. writes bootloader, locale, timezone, users and sudoers, and a boot splash
   in your theme (plymouth) that also asks for the disk password,
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
curl -fsSL https://raw.githubusercontent.com/apv022/Rayconfig/refs/heads/main/install.sh | sh
./install.sh --dry-run
./install.sh --check
```

Options: `--only <stages>`, `--skip <stages>`, `--yes`, `--extras`, `--services`,
`--theme sunny|sunset`.

The repo installs itself to `~/.local/share/rayconfig` and symlinks your configs
into it, so that directory is the live system — `ray update` is a `git pull` plus
a re-link. Set `RAYCONFIG_DIR` to put it elsewhere. Never run the installer from
a temp checkout; it refuses.

There are no versions: the URL, the installer and `ray update` all follow `main`.
GitHub caches the raw file for up to 5 minutes, so right after you change
`install.sh` itself, a fresh install may get the old copy briefly.

## Installed system

| job | tool | why not the alternative |
|---|---|---|
| compositor | `sway` | ships bar, lock, idle, wallpaper, nag — one C stack |
| bar | `swaybar` | the i3bar protocol is stdin JSON; the bar is a shell script, and clicks come back on stdin |
| terminal | `foot` | native Wayland, ~5 libs, config is a file, instant with `--server` |
| files | `muhfm` | one Go file, no deps; tabs, split, trash, archives, drives, previews — default for folders |
| launcher | `fuzzel` | `fuzzel --dmenu` turns anything into a picker |
| notifications | `mako` | dumb renderer, `makoctl` for actions, modes for do-not-disturb, OSD styling |
| clipboard | `cliphist` | `wl-paste --watch` stores, fuzzel picks |
| capture | `grim` + `slurp` + `wf-recorder` | screenshots, recording, colour picking: one `shot` script |
| wallpaper | `swaybg` + generated PNG | gradient derived from the palette, no wallpaper daemon |
| colors | `bin/gen-theme` | ~100 lines of sh + sed instead of a theme framework |

**On the terminal:** `st` is X11-only (XWayland) and its config is a patch queue
you maintain forever. Writing your own means owning a VT parser. `foot` is the
st of Wayland. Alacritty is available with `--extras` if you want to A/B it.

## Settings without the command line

`Super+I` opens the settings hub, a small floating list. Every item opens a
graphical picker or a terminal app in a floating window:

| setting | opens |
|---|---|
| Wi-Fi | `impala`, else `nmtui` |
| Bluetooth | `bluetui`, else `bluetoothctl` (starts the service for you) |
| Sound | `wiremix`, else `pulsemixer` / `alsamixer` |
| Display | pick a screen → scale or resolution |
| Theme | all 17, with a one-line description each |
| Font | any installed monospace family, applied to every app |
| Wallpaper | any image in `~/Pictures/wallpapers`, or the theme's |
| Keyboard layout, Touchpad | pick from a list |
| Night light, Power profile | `wlsunset`, `power-profiles-daemon` |
| Default apps | folders → muhfm, text → solarvim, images → imv, video → mpv, PDF → zathura |
| DNS | automatic, Cloudflare, Quad9 or Google, via NetworkManager |
| Timezone, Password | `timedatectl`, `passwd` |
| Fingerprint | installs `fprintd`, enrolls, lets sudo and the lock screen accept it |
| Autologin | log in on tty1 without a password (asks first) |
| Updates, System monitor | `ray update`, `btop` |
| Ask an agent | Claude Code inside this repo (or claude.ai/code) |

Choices are stored in `~/.local/state/rayconfig/settings` (plain `key=value`)
and rendered to `dots/sway/config.d/85-settings.conf` (gitignored), so they
survive updates and you can still read every line.

## Omarchy, feature by feature

[Omarchy](https://omarchy.org) gets the *experience* right: one command to a
finished desktop, menus for everything, themes that restyle every app at once,
TUIs instead of GTK settings panels, one-key updates. Rayconfig keeps that
experience and drops the parts that cost ownership: no Hyprland plugin
ecosystem, no AUR, no ~100 scripts. Each row below is one function in `ray`,
one script in `bin/`, or one line of config.

| Omarchy | Rayconfig | where |
|---|---|---|
| one-command install from the ISO | same, `curl … \| sh` | `install.sh` |
| full-disk encryption (LUKS) | on by default, one password for disk and login | `iso-install.sh` |
| Plymouth boot splash | the palette's wordmark, pulsing; the disk password is typed on it | `ray splash`, Menu → Style |
| Omarchy menu (Super+Alt+Space): apps, learn, trigger, style, setup, install, remove, update, about, system | same tree | `ray menu` |
| keybindings cheat sheet | generated from the configs (desktop, editor, files) | `Super+/`, `ray keys` |
| themes that restyle everything | 17 palettes → foot, sway, bar, mako, fuzzel, swaylock, muhfm, btop, GTK, wallpaper, Neovim | `ray theme`, `Super+T`, `Super+Ctrl+T` |
| next background | cycle theme wallpaper + `~/Pictures/wallpapers` | `Super+Ctrl+Space` |
| font picker | one font for every app | Settings → Font |
| Hyprland | sway — bar, lock, idle and wallpaper ship in the box | |
| Waybar with click actions | `swaybar` + `bin/status`: click wifi, volume (scroll/right-click), battery, clock, updates | `bin/status` |
| Walker launcher | `fuzzel` | `Super+D` |
| SwayOSD | mako bubble with a progress bar, replaced in place | `bin/vol`, `bin/bright` |
| hyprlock, hypridle | swaylock, swayidle (screensaver 4 min → lock 5 → screen off 10) | `ray idle` |
| screensaver | a sun drifting in theme colours | `ray screensaver` |
| hyprsunset night light | `wlsunset` | `Super+Ctrl+N` |
| idle-lock toggle, do not disturb, toggle bar, gaps, transparency | same, with bar indicators | `Super+Ctrl+I`, `Super+Ctrl+,`, `Super+Shift+Space`, `Super+Shift+Backspace`, `Super+Backspace` |
| screenshots + annotate | `grim`/`slurp`, `satty` | `Super+Shift+S`, `Print`, `Shift+Print` |
| screen recording | `wf-recorder`, `● REC` in the bar | `Super+Alt+R` |
| colour picker (hyprpicker) | `grim` one pixel → `#hex` on the clipboard | `Super+Shift+C` |
| clipboard history | `cliphist` + fuzzel | `Super+Ctrl+V` |
| emoji picker | fuzzel over a plain list | `Super+.` |
| web apps | desktop entries running `chromium --app=…` | `ray webapp`, Menu → Install |
| install / remove packages from a menu | fuzzel over `pacman -Sl` / `pacman -Qe` | `ray install`, `ray remove` |
| fonts install | official `ttf-*` / `otf-*` packages | Menu → Install → Font |
| Nautilus | muhfm: tabs, split, trash, archives, drives, Open With | `Super+E` |
| imv, mpv as defaults | same, via `xdg-mime` | Settings → Default apps |
| btop themed | rendered from the palette | `Super+Shift+Escape` |
| bash with prompt and aliases | `dots/shell/rc.sh`, one line in `~/.bashrc` | `fm` cds where you quit muhfm |
| omarchy-update, firmware, restart pieces | `ray update` (Arch + rayconfig + solarvim + muhfm), `fwupd`, `ray restart` | Menu → Update |
| Wi-Fi, Bluetooth, audio, monitors, power, DNS, timezone, password | TUIs and pickers | `Super+I` |
| fingerprint (fprintd) | enroll + PAM for sudo and swaylock | Settings → Fingerprint |
| autologin | getty drop-in on tty1 | Settings → Autologin |
| low battery warning | critical notification at 10% | `bin/status` |
| hibernate in the power menu | shown when swap exists | `Super+Escape` |
| AUR helpers + AUR packages | official repos only | |
| LazyVim (dozens of plugins) | solarvim: one file, zero plugins | `Super+N` |

Not mapped yet: btrfs snapshots (an "undo" for the whole system after a bad
update — needs a btrfs install and a boot menu that lists snapshots),
LocalSend (AirDrop-style sharing with your phone; AUR only) and universal
Super+C/V copy-paste (needs a key-injection tool outside sway).

## Everyday use

| | |
|---|---|
| `Super+/` | **cheat sheet** — every desktop, editor and file-manager shortcut, generated from the configs |
| `Super+Alt+Space` | menu: apps, learn, capture, toggle, style, setup, install, remove, update, about, system |
| `Super+I` | settings |
| `Super+E` | files (muhfm) |
| `Super+Escape` | power menu |
| `Super+Ctrl+V` · `Super+.` | clipboard history · emoji |
| `Super+Shift+S` · `Super+Alt+R` · `Super+Shift+C` | screenshot · record · colour picker |
| `ray update` | pulls rayconfig, solarvim and muhfm, then updates Arch and installs anything new — on the running system, no reinstall |
| bar | `↑ N updates` when Arch has updates; click anything to open its setting |

Mod is Super and behaves like Windows: `Super+Left/Right` snap, `Up/Down`
maximise/restore, `Tab` switch window, `E` files, `L` lock, `Enter` terminal,
`D` launcher, `N` editor, `T` light/dark, `.` emoji. Run `ray keys` for the full list.
For vim-style `h/j/k/l` focus, add binds to `~/.config/sway/config.d/90-local.conf`
(gitignored); `ray edit local` opens it.

The cheat sheet has no second copy to maintain: sway's comes from the
`## section` / `# description` comments in `dots/sway/config.d/30-binds.conf`,
solarvim's from the table that creates its mappings, muhfm's from its key table.

## Layout

```
install.sh                 entry point: archiso -> full disk install, Arch -> config install
bootstrap/iso-install.sh   partitioning, pacstrap, bootloader, users, handoff
bootstrap/                 installer stages, package lists
bin/                       ray, status, theme, gen-theme, doctor, keys, vol,
                           bright, shot, snap, winlist
dots/                      hand-written configs; *.in files are templates
dots/shell/rc.sh           prompt, aliases, fm — sourced from ~/.bashrc
templates/                 outputs that live outside the repo (solarvim, btop)
themes/                    palette files + generated wallpaper PNGs
data/emoji.txt             the emoji picker's list
tools/make-wallpaper.py    dev tool: regenerate wallpapers from a palette
test/smoke.sh              dependency-free smoke test
```

muhfm and solarvim are their own repos, cloned to `~/.local/share/` and kept
current by `ray update`. muhfm is built from source with the official `go`
package; nothing is downloaded but the code.

**Editing rule:** edit `*.in`, never the generated file next to it. Generated
files are gitignored and rebuilt by `ray theme`. Wallpapers are generated by
the dev tool and committed; any monitor size is fine (`-m fill`).

## After install

Log in on tty1; sway starts by itself (opt out: `touch ~/.config/rayconfig-no-autostart`).
On an existing Arch box, log in on a TTY and type `sway`.

```sh
ray doctor        # health check, read-only
ray update        # everything up to date
ray theme nord    # any folder in themes/, or toggle | next | prev | list
ray keys          # cheat sheets (sway | vim | fm)
ray menu          # everything else
ray edit          # open the repo in solarvim
```

## Roadmap

- Btrfs snapshots with a rollback entry in the boot menu.
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
