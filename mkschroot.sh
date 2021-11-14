#!/bin/bash
#
#   MKSCHROOT
#   =========
#
#   Installing development packages might pollute or conflict with your machine
#   setup. Using a schroot means you have a completely minimal, consistent and
#   isolated build environment.
#
#   To use this script to set up your schroot:
#
#       $ sudo apt install debootstrap
#       $ sudo ./mkschroot.sh --release xenial xenial-build
#
#   This creates an Ubuntu 16.04 (xenial) schroot called xenial-build in
#   /var/chroots/xenial-build.
#
#   Once that's done, you need to set up your schroot for development:
#
#       * You DO need to install development packages (e.g. build-essential,
#         etc.)
#       * You DO have access to your home directory just as you normally would.
#       * You DON'T need to configure separate SSH keys or config for git,
#         stash, bucks etc.
#       * You DON'T need to re-clone repos inside your schroot. Use any existing
#         repo you like.
#       * You DO have to clean away previous build artifacts from builds from
#         other distros, though.
#
#   To enter the schroot:
#
#       $ schroot -c xenial-build
#
#   Or just execute commands in the schroot:
#
#       $ schroot -c xenial-build -- <cmd...>
#
#
#   LICENSE
#   =======
#   This is free and unencumbered software released into the public domain.
#
#   Anyone is free to copy, modify, publish, use, compile, sell, or
#   distribute this software, either in source code form or as a compiled
#   binary, for any purpose, commercial or non-commercial, and by any
#   means.
#
#   In jurisdictions that recognize copyright laws, the author or authors
#   of this software dedicate any and all copyright interest in the
#   software to the public domain. We make this dedication for the benefit
#   of the public at large and to the detriment of our heirs and
#   successors. We intend this dedication to be an overt act of
#   relinquishment in perpetuity of all present and future rights to this
#   software under copyright law.
#
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
#   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
#   IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
#   OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
#   ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
#   OTHER DEALINGS IN THE SOFTWARE.
#
#   For more information, please refer to <https://unlicense.org>
#

error() {
    echo "$@" >&2
    exit 1
}

usage() {
    echo "$0 [--options] <schroot name, e.g. xenial-build>"
    echo "  --release|-r <xenial>           - sets Ubuntu flavor"
    echo "  --path|-p </var/chroots/name>   - sets path of chroot"
    echo "  --name <Friendly Name>          - sets the friendly name of the schroot"
    echo "  --force|-f                      - overwrite existing schroot"
    echo "  --force|-f --skip               - skip steps that might already be complete"
}

bad_usage() {
    echo "$*" >&2
    usage >&2
    exit 1
}

missing_packages() {
    error "Please run: sudo apt install debootstrap schroot"
}

SCHROOTNAME=
UBUNTUFLAVOR=
CHROOTPATH=
opt_force=
opt_skip=

set_name() {
    [ -z "$SCHROOTNAME" ] || bad_usage "Duplicate schroot name." ; SCHROOTNAME="$1"
}
set_flavor() {
    [ -z "$UBUNTUFLAVOR" ] || bad_usage "Duplicate Ubuntu release." ; UBUNTUFLAVOR="$1"
}
set_path() {
    [ -z "$CHROOTPATH" ] || bad_usage "Duplicate chroot path." ; CHROOTPATH="$1"
}
set_fname() {
    [ -z "$FRIENDLYNAME" ] || bad_usage "Duplicate friendly name." ; FRIENDLYNAME="$1"
}

while [ -n "$1" ]; do
    case "$1" in
        --release|-r)   set_flavor "$2" ; shift ;;
        --path|-p)      set_path "$2" ; shift ;;
        --name)         set_fname "$2" ; shift ;;
        --skip)         opt_skip=yes ;;
        --force|-f)     opt_force=yes ;;
        --help)         usage ; exit 0 ;;
        --*)            bad_usage "Unknown option $1" ;;
        *)              set_name "$1" ;;
    esac
    shift
done

if [ -n "$opt_skip" ] && [ -z "$opt_force" ]; then
    bad_usage "Can't use --skip without --force."
fi

[ -n "$SCHROOTNAME" ] || bad_usage "Missing schroot name."
[ -n "$UBUNTUFLAVOR" ] || UBUNTUFLAVOR="xenial"
[ -n "$CHROOTPATH" ] || CHROOTPATH="/var/chroots/$SCHROOTNAME"
[ -n "$FRIENDLYNAME" ] || FRIENDLYNAME="$(tr '[:lower:]' '[:upper:]' <<< ${UBUNTUFLAVOR:0:1})${UBUNTUFLAVOR:1} Schroot"

SCHROOTCONF="/etc/schroot/chroot.d/$SCHROOTNAME"

#
# construct schroot config
#
SCHROOTCONFIG="

[$SCHROOTNAME]
description=$FRIENDLYNAME
directory=$CHROOTPATH
users=$USER
groups=sudo
root-groups=sudo
preserve-environment=true
type=directory
setup.fstab=$SCHROOTNAME/fstab"

add_mount_to_fstab() {
    entry="$1"
    fstab="$2"
    if ! grep "$entry" "$fstab" ; then
        echo "$entry" | sudo tee -a "$fstab" >/dev/null
    fi
}

#
# installs the schroot
#
install_schroot() {
    [ -x /usr/sbin/debootstrap ] || missing_packages
    [ -x /usr/bin/schroot ] || missing_packages

    fstab_file="/etc/schroot/$SCHROOTNAME/fstab"

    #
    # check for destructive actions early
    #
    [ ! -e "$SCHROOTCONF" ] || [ -n "$opt_force" ] || error "$SCHROOTCONF already exists. Refusing to overwrite without --force."
    [ ! -e "$fstab_file" ] || [ -n "$opt_force" ] || error "$fstab_file already exists. Refusing to overwrite without --force."
    [ ! -e "$CHROOTPATH" ] || [ -n "$opt_force" ] || error "$CHROOTPATH already exists. Refusing to overwrite without --force."

    set -e

    #
    # get keys for precise
    #
    DEBOOTSTRAP_OPTIONS=
    if [ "$UBUNTUFLAVOR" == "precise" ]; then
        echo "Fetching precise GPG key..."
        PRECISE_KEYRING=/tmp/ubuntu-precise-keyring.gpg
        gpg --keyring="${PRECISE_KEYRING}" --no-default-keyring --keyserver keyserver.ubuntu.com --receive-keys 0x40976EAF437D05B5
        DEBOOTSTRAP_OPTIONS="--keyring=${PRECISE_KEYRING}"
    fi

    #
    # fetch the distro
    #
    if [ -e "$CHROOTPATH" ] && [ -n "$opt_skip" ]; then
        echo "WARNING: $CHROOTPATH already exists. Skipping debootstrap." >&2
    else
        [ ! -e "$CHROOTPATH" ] || sudo rm -rf "$CHROOTPATH"
        sudo mkdir -p "$CHROOTPATH"
        sudo debootstrap $DEBOOTSTRAP_OPTIONS "$UBUNTUFLAVOR" "$CHROOTPATH" http://archive.ubuntu.com/ubuntu
    fi

    #
    # set up fstab
    #
    if [ -e "$fstab_file" ] && [ -n "$opt_skip" ]; then
        echo "WARNING: $fstab_file already set up. Skipping creation."
    else
        sudo mkdir -p "$(dirname "$fstab_file")"
        sudo cp -v /etc/schroot/default/fstab "$fstab_file"
    fi

    #
    # add entry to schroot.conf
    #
    if [ ! -f "$SCHROOTCONF" ]; then
        echo "$SCHROOTCONFIG" | sudo tee "$SCHROOTCONF" 1>/dev/null
    else
        echo "WARNING: $SCHROOTCONF already exists. The file has not been modified." >&2
        echo "Ensure the configuration matches the below:" >&2
        echo "$SCHROOTCONFIG" >&2
        echo >&2
    fi

    #
    # configure locales
    #
    if grep -q "LC_ALL=en_US.UTF-8" "$CHROOTPATH/etc/locale.conf" 2>/dev/null && [ -n "$opt_skip" ]; then
        echo "WARNING: locale.conf already set up. Skipping locale generation."
    else
        echo "LC_ALL=en_US.UTF-8
en_US.UTF-8 UTF-8
LANG=en_US.UTF-8" | sudo tee "$CHROOTPATH/etc/locale.conf" >/dev/null
        schroot -c "$SCHROOTNAME" -d / -u root -- locale-gen en_US.UTF-8
    fi

    #
    # configure the chroot apt sources
    #
    if grep -q "$UBUNTUFLAVOR" "$CHROOTPATH/etc/apt/sources.list" && [ -n "$opt_skip" ]; then
        echo "WARNING: sources.list already set up. Skipping setup."
    else
        # Configure the minimal repos for now
        printf "deb http://us.archive.ubuntu.com/ubuntu/ %s main restricted
deb http://us.archive.ubuntu.com/ubuntu/ %s-updates main restricted\n\n\n\n" "$UBUNTUFLAVOR" "$UBUNTUFLAVOR" |
            sudo tee "$CHROOTPATH/etc/apt/sources.list" >/dev/null

        # However, let's copy this over (commented out) for convenience:
        sed "s/$(lsb_release -sc)/$UBUNTUFLAVOR/g" /etc/apt/sources.list |
            awk '/^\s*$/ { print $0 } /^\s*#/ { print $0 } /^\s*[^#]/ { print "# " $0 }' |
            sudo tee -a "$CHROOTPATH/etc/apt/sources.list" >/dev/null

        #
        # for older distros, we need to divert upstart
        #
        if [ "$UBUNTUFLAVOR" == "precise" ] || [ "$UBUNTUFLAVOR" == "trusty" ]; then
            schroot -c "$SCHROOTNAME" -d / -u root -- dpkg-divert --local --rename --add /sbin/initctl
            schroot -c "$SCHROOTNAME" -d / -u root -- ln -s /bin/true /sbin/initctl
        fi
    fi

    #
    # update apt
    #
    schroot -c "$SCHROOTNAME" -d / -u root -- apt-get update
    schroot -c "$SCHROOTNAME" -d / -u root -- apt-get upgrade -y

    #
    # now set up mounting of /run/shm and /dev/shm
    #
    add_mount_to_fstab "/dev/shm /dev/shm none rw,bind 0 0" "$fstab_file"
    add_mount_to_fstab "/run/shm /run/shm none rw,bind 0 0" "$fstab_file"

    #
    # restore vt shortcuts (I hate this so much)
    #
    sudo kbd_mode -s

    #
    # done
    #
    echo "Setup complete. Use 'schroot -c $SCHROOTNAME' to use your schroot."
    echo "You may wish to uncomment Apt sources in /etc/apt/sources.list "
    echo "before installing more packages."
}

install_schroot
