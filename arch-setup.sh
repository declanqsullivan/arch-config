#!/bin/sh
# Arch post install script to setup environment
# by decla (mostly)

### OPTIONS AND VARIABLES ###
dotfilesrepo="https://github.com/declanqsullivan/rice"
progsfile="https://raw.githubusercontent.com/declanqsullivan/my-os-setup/main/default-programs.csv"
aurhelper="yay"
repobranch="main"

### FUNCTIONS ###

installpkg(){ pacman --noconfirm --needed -S "$1" >/dev/null 2>&1;}

error() { clear; printf "ERROR:\\n%s\\n" "$1" >&2; exit 1;}

getuserandpass() { \
	# Prompts user for new username an password.
    printf "Enter the main user name: "
	read name
	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
        printf "Error: must be all lowercase and use only '-' or '_'"
        read name
	done
    printf "Enter user password: "
    read pass1
    printf "Re-enter password: "
    read pass2
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
        printf "They didn't match. Try again\n"
        printf "Enter user password: "
        read pass1
        printf "Re-enter password: " read pass2
	done ;}

adduserandpass() { \
	# Adds user `$name` with password $pass1.
    printf "Adding user $name\n"
	useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 ||
	usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
	repodir="/home/$name/.local/src"; mkdir -p "$repodir"; chown -R "$name":wheel "$(dirname "$repodir")"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2 ;}

refreshkeys() { \
	printf "Refreshing Arch Keyring...\n"
	# pacman -Q artix-keyring >/dev/null 2>&1 && pacman --noconfirm -S artix-keyring >/dev/null 2>&1
	pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
	}

newperms() { # Set special sudoers settings for install (or after).
	echo "$*" >> /etc/sudoers ;}

manualinstall() { # Installs $1 manually if not installed. Used only for AUR helper here.
	[ -f "/usr/bin/$1" ] || (
    printf "Installing $1\n"
	cd /tmp || exit 1
	rm -rf /tmp/"$1"*
	curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/"$1".tar.gz &&
	sudo -u "$name" tar -xvf "$1".tar.gz >/dev/null 2>&1 &&
	cd "$1" &&
	sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1
	cd /tmp || return 1) ;}

maininstall() { # Installs all needed programs from main repo.
    printf "Installing $1 ($n of $total)\n"
	installpkg "$1"
	}

gitmakeinstall() {
	progname="$(basename "$1" .git)"
	dir="$repodir/$progname"
    printf "Installing $progname ($n of $total) via git and make. $(basename "$1")\n"
	sudo -u "$name" git clone --depth 1 "$1" "$dir" >/dev/null 2>&1 || { cd "$dir" || return 1 ; sudo -u "$name" git pull --force origin master;}
	cd "$dir" || exit 1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1 ;}

aurinstall() { \
	printf "Installing $1 ($n of $total) from the AUR\n"
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
	}

pipinstall() { \
	printf "Installing the Python package $1 ($n of $total)."
	[ -x "$(command -v "pip")" ] || installpkg python-pip >/dev/null 2>&1
	yes | pip install "$1"
	}

installationloop() { \
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/programs.csv) || curl -Ls "$progsfile" | sed '/^#/d' > /tmp/programs.csv
	total=$(wc -l < /tmp/programs.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r method program comment; do
		n=$((n+1))
        echo "$comment" | grep -q "^\".*\"$" && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$method" in
			"aur") aurinstall "$program" ;;
			"git") gitmakeinstall "$program" ;;
			"pip") pipinstall "$program" ;;
			*) maininstall "$program" ;;
		esac
	done < /tmp/programs.csv ;}

putgitrepo() { # Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
	printf "Downloading and installing config files...\n"
	dir=$(mktemp -d)
	[ ! -d "$2" ] && mkdir -p "$2"
	chown "$name":wheel "$dir" "$2"
	sudo -u "$name" git clone --recursive -b "$repobranch" --depth 1 "$1" "$dir" >/dev/null 2>&1
	sudo -u "$name" cp -rfT "$dir" "$2"
	}

systembeepoff() { 
    printf "Removing the beeping\n"
	rmmod pcspkr
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;}

### THE ACTUAL SCRIPT ###

# Check if user is root on Arch distro. Install dialog.
pacman --noconfirm --needed -Sy || error "Are you root, on an Arch-based distro and have internet?"

# Welcome user and pick dotfiles.
printf "Hello and welcome to the install script\n" 
getuserandpass # Get and verify username and password.

# Refresh Arch keyrings.
refreshkeys || error "Error auto refreshing Arch keyring. Do it manually."

printf "Installing installation packages\n"
for x in curl base-devel git ntp zsh; do
    printf "Installing $x\n"
	installpkg "$x"
done

printf "Synchronising sys time\n"
ntpdate 0.us.pool.ntp.org >/dev/null 2>&1

adduserandpass || error "Error adding username and/or password."

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman/yay colorful and add eye candy on the progress bar.
grep -q "^Color" /etc/pacman.conf || sed -i "s/^#Color$/Color/" /etc/pacman.conf
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

# Install aur program
manualinstall $aurhelper || error "Failed to install AUR helper."

# Reads programs file and installs each program the way required. Run only
# after the user has been created and has su priviledges.
installationloop

# Install the dotfiles in the user's home directory
putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
rm -f "/home/$name/README.md"
# make git ignore deleted LICENSE & README.md files
git update-index --assume-unchanged "/home/$name/README.md"

# Most important command! Get rid of the beep!
# systembeepoff

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$name" >/dev/null 2>&1
sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"

# This line, overwriting the `newperms` command above will allow the user to
# run serveral important commands, `shutdown`, `reboot`, updating, etc. without
# a password.
newperms "%wheel ALL=(ALL) ALL
%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syyu,/usr/bin/yay"

# Last message! Install complete!
printf "All done! Just press ENTER, and the system will reboot"
read
# reboot

