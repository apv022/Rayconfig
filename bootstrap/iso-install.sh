#!/usr/bin/env bash
# iso-install — Arch + Rayconfig from the live ISO, in one command.
#
#   curl -fsSL <bootstrap-url> | sh
#
# Runs only from archiso, as root. Partitions one disk, pacstraps Arch, sets up
# bootloader/users/network, then installs Rayconfig into the new system.
#
# This destroys the target disk. It asks you to type the disk name first.
#
#   --disk /dev/vda     target disk (asked if omitted)
#   --user NAME         login user (asked if omitted)
#   --hostname NAME     defaults to rayarch
#   --timezone TZ       defaults to UTC (e.g. Europe/Berlin)
#   --no-encrypt        skip full-disk encryption (on by default: LUKS2,
#                       unlocked at boot with your password on the splash)
#   --yes               no prompts (requires --disk and --user)
#   --fast-mirrors      run reflector before installing
#   --dry-run           print every action, touch nothing
set -euo pipefail

DISK=""
NEWUSER=""
NEWHOST="rayarch"
NEWTZ="UTC"
YES=0
DRY=0
FAST=0
ENCRYPT=1
REPO_SRC=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

usage() {
	sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
	exit 0
}

while [ $# -gt 0 ]; do
	case $1 in
	--disk) DISK=$2; shift 2 ;;
	--user) NEWUSER=$2; shift 2 ;;
	--hostname) NEWHOST=$2; shift 2 ;;
	--timezone | --tz) NEWTZ=$2; shift 2 ;;
	--yes | -y) YES=1; shift ;;
	--dry-run) DRY=1; shift ;;
	--fast-mirrors) FAST=1; shift ;;
	--no-encrypt) ENCRYPT=0; shift ;;
	-h | --help) usage ;;
	*) printf 'iso-install: unknown argument: %s\n' "$1" >&2; exit 2 ;;
	esac
done

R=$'\033[38;5;203m'
Y=$'\033[38;5;215m'
G=$'\033[38;5;149m'
D=$'\033[38;5;244m'
Z=$'\033[0m'
[ -t 1 ] || { R=; Y=; G=; D=; Z=; }

say() { printf '%s==>%s %s\n' "$D" "$Z" "$*"; }
ok() { printf '%s ok %s %s\n' "$G" "$Z" "$*"; }
warn() { printf '%swarn%s %s\n' "$Y" "$Z" "$*" >&2; }
die() {
	printf '%sfail%s %s\n' "$R" "$Z" "$*" >&2
	exit 1
}
run() {
	if [ "$DRY" = 1 ]; then
		printf '  %s+%s %s\n' "$D" "$Z" "$*"
		return 0
	fi
	"$@"
}

# stdin is the curl pipe, so prompts must come from the tty explicitly.
tty_read() { # prompt -> answer on stdout (stdin is the curl pipe)
	if [ -r /dev/tty ]; then
		printf '%s' "$1" >&2
		IFS= read -r _ans </dev/tty || die "no answer"
		printf '%s' "$_ans"
	else
		die "no tty available; pass --disk and --user"
	fi
}

tty_secret() {
	printf '%s' "$1" >&2
	IFS= read -rs "$2" </dev/tty || die "no answer"
	printf '\n' >&2
}

part() { # disk index -> partition device
	case $1 in
	*[0-9]) printf '%sp%s' "$1" "$2" ;;
	*) printf '%s%s' "$1" "$2" ;;
	esac
}

fail_trap() {
	printf '\n%sinstall failed%s — the disk has already been modified.\n' "$R" "$Z" >&2
	printf 'see the error above; the complete command is echoed in --dry-run.\n' >&2
	printf 're-run the same command, or reboot into the ISO and retry.\n' >&2
}
trap fail_trap ERR

# ------------------------------------------------------------------ preflight

[ "$(id -u)" -eq 0 ] || die "must run as root (you are on the archiso, so you are)"

if [ ! -d /run/archiso ] && [ -z "${RAYCONFIG_FORCE_ISO:-}" ]; then
	die "this is the ISO installer, and you are not on the archiso.
For an existing Arch system use install.sh instead."
fi

say "archiso install: Arch + Rayconfig"
[ "$DRY" = 1 ] && warn "dry run: no disks will be touched"

for c in pacstrap sgdisk arch-chroot lsblk mkfs.ext4 cryptsetup; do
	command -v "$c" >/dev/null 2>&1 || die "missing tool on the ISO: $c"
done

if ! curl -fsI -m 8 https://archlinux.org >/dev/null 2>&1; then
	warn "cannot reach archlinux.org"
	printf 'connect first:  iwctl  (wifi)  or plug in ethernet\n' >&2
	[ "$DRY" = 1 ] || die "no network"
fi
ok "network"

if findmnt -rn /mnt >/dev/null 2>&1; then
	die "/mnt is in use. Run: umount -R /mnt"
fi
if [ -e /dev/mapper/root ]; then
	die "an encrypted 'root' is still open from an earlier attempt. Run: cryptsetup close root"
fi

if [ "$FAST" = 1 ] && command -v reflector >/dev/null 2>&1 && [ "$DRY" = 0 ]; then
	say "ranking mirrors"
	reflector --latest 20 --protocol https --sort rate \
		--save /etc/pacman.d/mirrorlist >/dev/null 2>&1 || warn "reflector failed, keeping defaults"
fi

timedatectl set-ntp true >/dev/null 2>&1 || true

# ---------------------------------------------------------------- disk choice

# Never offer the medium we booted from.
boot_mnt=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
boot_disk=""
if [ -n "$boot_mnt" ]; then
	boot_disk=/dev/$(lsblk -no PKNAME "$boot_mnt" 2>/dev/null | head -n1)
	[ "$boot_disk" = /dev/ ] && boot_disk=""
fi

mapfile -t DISKS < <(lsblk -dpno NAME,SIZE,MODEL | while read -r name size model; do
	[ "$name" = "$boot_disk" ] && continue
	printf '%s\t%s\t%s\n' "$name" "$size" "${model:-disk}"
done)

if [ -z "$DISK" ]; then
	[ ${#DISKS[@]} -gt 0 ] || die "no candidate disks found"
	if [ ${#DISKS[@]} -eq 1 ] && [ "$YES" = 1 ]; then
		DISK=${DISKS[0]%%$'\t'*}
	else
		printf '\navailable disks:\n' >&2
		i=1
		for d in "${DISKS[@]}"; do
			printf '  %d) %s\n' "$i" "$(printf '%s' "$d" | tr '\t' ' ')" >&2
			i=$((i + 1))
		done
		tty_read_choice=$(tty_read "disk number or /dev/...: ")
		case $tty_read_choice in
		/dev/*) DISK=$tty_read_choice ;;
		'' | *[!0-9]*) die "bad choice: $tty_read_choice" ;;
		*) DISK=$(printf '%s' "${DISKS[$((tty_read_choice - 1))]}" | cut -f1) ;;
		esac
	fi
fi

[ -b "$DISK" ] || die "not a block device: $DISK"
[ "$(lsblk -dno TYPE "$DISK")" = disk ] || die "$DISK is not a whole disk (pass the disk, not a partition)"
[ "$DISK" != "$boot_disk" ] || die "$DISK is the install medium"

# ------------------------------------------------------------------- identity

[ -n "$NEWUSER" ] || NEWUSER=$(tty_read "username: ")
printf '%s' "$NEWUSER" | grep -qE '^[a-z_][a-z0-9_-]*$' || die "invalid username: $NEWUSER"
printf '%s' "$NEWHOST" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9.-]*$' || die "invalid hostname: $NEWHOST"

USERPASS=""
if [ "$DRY" = 0 ]; then
	tty_secret "password for $NEWUSER: " USERPASS
	[ -n "$USERPASS" ] || die "empty password"
	tty_secret "repeat password: " USERPASS2
	[ "$USERPASS" = "$USERPASS2" ] || die "passwords do not match"
	unset USERPASS2
fi

UEFI=0
[ -d /sys/firmware/efi ] && UEFI=1

# ------------------------------------------------------------------ confirm

info=$(lsblk -dpno SIZE,MODEL "$DISK" | head -n1)
printf '\n%s  THIS WILL ERASE %s%s\n' "$R" "$DISK" "$Z" >&2
printf '  %s\n' "$info" >&2
printf '  boot mode: %s\n' "$([ "$UEFI" = 1 ] && echo UEFI || echo BIOS)" >&2
printf '  encryption: %s\n' "$([ "$ENCRYPT" = 1 ] && echo 'on — the same password unlocks the disk at boot' || echo off)" >&2
printf '  user: %s   host: %s   timezone: %s\n\n' "$NEWUSER" "$NEWHOST" "$NEWTZ" >&2

if [ "$YES" = 0 ]; then
	confirm=$(tty_read "type $(basename "$DISK") to continue: ")
	[ "$confirm" = "$(basename "$DISK")" ] || die "aborted"
fi

# -------------------------------------------------------------- partitioning

say "partitioning $DISK"
run wipefs -af "$DISK"
run sgdisk --zap-all "$DISK"
# UEFI: 1 ESP (/boot, 1G) + 2 root.
# BIOS: 1 bios_grub + 2 /boot (1G ext4, unencrypted so GRUB can read it) + 3 root.
if [ "$UEFI" = 1 ]; then
	run sgdisk -n "1:0:+1G" -t 1:ef00 -c 1:ESP "$DISK"
	run sgdisk -n "2:0:0" -t 2:8300 -c 2:root "$DISK"
else
	run sgdisk -n "1:0:+1M" -t 1:ef02 -c 1:BIOS "$DISK"
	run sgdisk -n "2:0:+1G" -t 2:8300 -c 2:boot "$DISK"
	run sgdisk -n "3:0:0" -t 3:8300 -c 3:root "$DISK"
fi
run partprobe "$DISK" || true
[ "$DRY" = 1 ] || udevadm settle

P1=$(part "$DISK" 1)
if [ "$UEFI" = 1 ]; then
	BOOTP=$P1
	ROOTP=$(part "$DISK" 2)
else
	BOOTP=$(part "$DISK" 2)
	ROOTP=$(part "$DISK" 3)
fi

say "filesystems"
if [ "$UEFI" = 1 ]; then
	run mkfs.fat -F32 -n ESP "$BOOTP"
else
	run mkfs.ext4 -F -L boot "$BOOTP"
fi
ROOTFS=$ROOTP
if [ "$ENCRYPT" = 1 ]; then
	say "encrypting $ROOTP (LUKS2)"
	# The password goes in on stdin with no trailing newline, exactly as it
	# will be typed at boot. It never touches a file.
	if [ "$DRY" = 1 ]; then
		printf '  %s+%s cryptsetup luksFormat --type luks2 %s  (password on stdin)\n' "$D" "$Z" "$ROOTP"
		printf '  %s+%s cryptsetup open %s root\n' "$D" "$Z" "$ROOTP"
	else
		printf '%s' "$USERPASS" | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$ROOTP"
		printf '%s' "$USERPASS" | cryptsetup open --key-file=- "$ROOTP" root
	fi
	ROOTFS=/dev/mapper/root
fi
run mkfs.ext4 -F -L root "$ROOTFS"

say "mounting"
run mount "$ROOTFS" /mnt
run mkdir -p /mnt/boot
run mount "$BOOTP" /mnt/boot

# ------------------------------------------------------------------ pacstrap

PKGS=(base linux linux-firmware networkmanager sudo git curl less man-db bash-completion cryptsetup plymouth)
case $(grep -m1 '^vendor_id' /proc/cpuinfo | awk '{print $3}') in
*Intel*) PKGS+=(intel-ucode) ;;
*AMD*) PKGS+=(amd-ucode) ;;
esac
# Broadcom BCM43xx wifi (Dell DW1560/1830, many MacBooks): the ISO's b43
# driver can't run these, so no wlan0 ever appears. broadcom-wl is the
# official-repo proprietary driver; it blacklists b43/bcma itself.
if lspci -n 2>/dev/null | grep -qiE '14e4:(4311|4312|4313|4315|4328|4329|432a|432b|432c|432d|4353|4357|4358|4359|4360|4365|43a0|43b1|43b2)'; then
	# Ask the repos instead of guessing: the prebuilt package has come and
	# gone; the dkms one builds against linux-headers. Never abort over wifi.
	pacman -Sy --noconfirm >/dev/null 2>&1 || true
	if pacman -Si broadcom-wl >/dev/null 2>&1; then
		PKGS+=(broadcom-wl)
		say "Broadcom wifi detected: adding broadcom-wl"
	elif pacman -Si broadcom-wl-dkms >/dev/null 2>&1; then
		PKGS+=(broadcom-wl-dkms linux-headers)
		say "Broadcom wifi detected: adding broadcom-wl-dkms + linux-headers"
	else
		warn "Broadcom wifi detected but no broadcom-wl package in the repos; wifi will need a driver after install"
	fi
fi
if [ "$UEFI" = 1 ]; then
	PKGS+=(efibootmgr)
else
	PKGS+=(grub)
fi

# Old ISOs ship stale keys; refreshing the keyring first avoids
# "signature is unknown trust" halfway through pacstrap.
say "refreshing the Arch keyring"
run pacman -Sy --noconfirm --needed archlinux-keyring

say "pacstrap (this is the slow part)"
run pacstrap -K /mnt "${PKGS[@]}"
if [ "$DRY" = 1 ]; then
	printf '  %s+%s genfstab -U /mnt >> /mnt/etc/fstab\n' "$D" "$Z"
else
	genfstab -U /mnt >>/mnt/etc/fstab
fi

ROOT_UUID=$(blkid -s UUID -o value "$ROOTFS" 2>/dev/null || echo DRYRUN-UUID)
LUKS_UUID=$(blkid -s UUID -o value "$ROOTP" 2>/dev/null || echo DRYRUN-LUKS-UUID)
# what the kernel needs to find (and unlock) the root filesystem
if [ "$ENCRYPT" = 1 ]; then
	KERNEL_ROOT="rd.luks.name=$LUKS_UUID=root root=/dev/mapper/root"
	ENCRYPT_HOOK=sd-encrypt
else
	KERNEL_ROOT="root=UUID=$ROOT_UUID"
	ENCRYPT_HOOK=
fi

# ------------------------------------------------------------------- chroot

say "configuring the system"
useradd_script=$(
	cat <<EOF
set -e
ln -sf /usr/share/zoneinfo/$NEWTZ /etc/localtime
hwclock --systohc || true

sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'KEYMAP=us' > /etc/vconsole.conf

echo '$NEWHOST' > /etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 $NEWHOST.localdomain $NEWHOST\n' > /etc/hosts

id -u '$NEWUSER' >/dev/null 2>&1 || useradd -m -G wheel,video -s /bin/bash '$NEWUSER'
printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

cat > /etc/profile.d/10-rayconfig.sh <<'PROFILE'
# Rayconfig: user scripts on PATH, solarvim as the editor.
case ":\$PATH:" in *":\$HOME/.local/bin:"*) ;; *) export PATH="\$HOME/.local/bin:\$PATH" ;; esac
export EDITOR=nvim VISUAL=nvim
export NVIM_APPNAME=\${NVIM_APPNAME:-solarvim}
# Start sway when logging in on tty1. Opt out: touch ~/.config/rayconfig-no-autostart
# profile.d runs in name order and this file comes before Arch's locale.sh;
# exec replaces the shell, so load the locale here or sway starts with LANG=C.
if [ "\$(tty)" = /dev/tty1 ] && [ -z "\${WAYLAND_DISPLAY:-}" ] && [ ! -e "\$HOME/.config/rayconfig-no-autostart" ] && command -v sway >/dev/null; then
	[ -r /etc/profile.d/locale.sh ] && . /etc/profile.d/locale.sh
	exec sway
fi
PROFILE

systemctl enable NetworkManager.service systemd-timesyncd.service >/dev/null 2>&1 || true

# systemd initramfs: plymouth draws the splash and asks for the disk
# password; sd-encrypt unlocks it. keyboard + sd-vconsole come before so the
# password can be typed with the right layout.
sed -i 's/^HOOKS=.*/HOOKS=(base systemd plymouth autodetect modconf kms keyboard sd-vconsole block $ENCRYPT_HOOK filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P
EOF
)

if [ "$DRY" = 1 ]; then
	printf '  %s+%s arch-chroot /mnt <setup script for %s>\n' "$D" "$Z" "$NEWUSER"
	printf '  %s+%s bootloader: %s\n' "$D" "$Z" "$([ "$UEFI" = 1 ] && echo systemd-boot || echo grub)"
else
	printf '%s\n' "$useradd_script" >/mnt/root/.ray-setup.sh
	arch-chroot /mnt /bin/bash /root/.ray-setup.sh
	rm -f /mnt/root/.ray-setup.sh
	# Passwords are piped from here, never written to a file in the new system.
	printf '%s:%s\n' "$NEWUSER" "$USERPASS" | arch-chroot /mnt chpasswd
	printf 'root:%s\n' "$USERPASS" | arch-chroot /mnt chpasswd
	ok "users, locale, network"
fi

say "bootloader"
if [ "$UEFI" = 1 ]; then
	boot_script=$(
		cat <<EOF
set -e
bootctl --path=/boot install >/dev/null
printf 'default arch.conf\ntimeout 3\neditor no\n' > /boot/loader/loader.conf
{
  echo 'title   Arch Linux'
  echo 'linux   /vmlinuz-linux'
  [ -f /boot/intel-ucode.img ] && echo 'initrd  /intel-ucode.img'
  [ -f /boot/amd-ucode.img ] && echo 'initrd  /amd-ucode.img'
  echo 'initrd  /initramfs-linux.img'
  echo 'options $KERNEL_ROOT rw quiet splash loglevel=3 rd.udev.log_level=3 vt.global_cursor_default=0'
} > /boot/loader/entries/arch.conf
EOF
	)
else
	boot_script=$(
		cat <<EOF
set -e
sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet splash rd.udev.log_level=3 vt.global_cursor_default=0"|' /etc/default/grub
sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="$KERNEL_ROOT"|' /etc/default/grub
grub-install --target=i386-pc '$DISK' >/dev/null
grub-mkconfig -o /boot/grub/grub.cfg >/dev/null
EOF
	)
fi
if [ "$DRY" = 1 ]; then
	printf '  %s+%s arch-chroot /mnt <bootloader script>\n' "$D" "$Z"
else
	printf '%s\n' "$boot_script" >/mnt/root/.ray-boot.sh
	arch-chroot /mnt /bin/bash /root/.ray-boot.sh
	rm -f /mnt/root/.ray-boot.sh
	ok "bootloader"
fi

# ----------------------------------------------------------------- rayconfig

say "installing rayconfig into the new system"
TARGET=/mnt/home/$NEWUSER/.local/share/rayconfig
if [ "$DRY" = 1 ]; then
	printf '  %s+%s copy %s -> %s\n' "$D" "$Z" "$REPO_SRC" "$TARGET"
	printf '  %s+%s arch-chroot /mnt env HOME=/home/%s RAYCONFIG_ALLOW_ROOT=1 ./bootstrap/install.sh --yes --skip verify\n' \
		"$D" "$Z" "$NEWUSER"
else
	mkdir -p "$TARGET"
	cp -a "$REPO_SRC/." "$TARGET/"
	# chown must run INSIDE the chroot: the ISO's /etc/passwd has no $NEWUSER.
	arch-chroot /mnt id -u "$NEWUSER" >/dev/null 2>&1 ||
		die "user $NEWUSER was not created in the new system"
	arch-chroot /mnt chown -R "$NEWUSER:$NEWUSER" "/home/$NEWUSER/.local"
	ok "repo owned by $NEWUSER"
	# No sudo and no tty here: run the config stage as root with HOME pointed
	# at the new user, so pacman is called directly and configs land in the
	# right home. Then hand the whole home back to the user. verify is skipped:
	# sway --validate inside a chroot has no seat or runtime dir; `ray doctor`
	# runs for real after the first login.
	arch-chroot /mnt env HOME="/home/$NEWUSER" RAYCONFIG_ALLOW_ROOT=1 \
		/bin/bash -c 'cd "$HOME/.local/share/rayconfig" && ./bootstrap/install.sh --yes --skip verify' ||
		die "rayconfig stage failed; see the error above"
	arch-chroot /mnt chown -R "$NEWUSER:$NEWUSER" "/home/$NEWUSER"
	ok "rayconfig"
fi

# ---------------------------------------------------------------------- done

if [ "$DRY" = 0 ]; then
	umount -R /mnt 2>/dev/null || true
	[ "$ENCRYPT" = 1 ] && cryptsetup close root 2>/dev/null || true
fi

printf '\n'
say "done — Arch + Rayconfig on $DISK"
cat <<EOF
  reboot (take the USB stick out), log in as $NEWUSER on tty1 —
  sway starts by itself. Then:

      Super+/            every shortcut, desktop and editor
      Super+Alt+Space    menu: update, theme, lock, power
      Super+Enter        terminal        Super+D   launcher
      ray update         update everything      ray doctor   health check

  VM with a black screen? log in, then:  WLR_RENDERER=pixman sway

  root and $NEWUSER both use the password you typed.$([ "$ENCRYPT" = 1 ] && printf '\n  The disk is encrypted: type that same password on the boot splash.\n  Lose it and the data is gone — there is no recovery key.')
  theme: ~/.local/share/rayconfig/themes/
EOF
