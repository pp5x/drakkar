#!/bin/bash

CURDIR=$(dirname $0)
NAME=$(basename $0)
DEBUG=1
EXT4SIZE=-1
ROOTDISK=disk0s2
TARGETDISK=disk0s5

source $CURDIR/err_colors.sh

# Exit on error  -  trap ERR
set -o errexit
# Exit on uninitialized variables
set -o nounset

# Xcode Command Line Tools

function failure() {
  set +o errexit
  set +o nounset
  err "$1: Line $2: returned code $3"
  exit 1
}

function cleanup() {
  info 'Executing cleanup routine...'
  sudo sed -i.bak '/Defaults timestamp_timeout=-1/d' /etc/sudoers
  success 'Restored sudoers timestamp timeout.'
}

trap 'failure $NAME $LINENO $?' ERR

################################################################################
# Print usage
################################################################################

function usage() {
  echo -e "${NAME}, usage:"
  echo -e '-h\t\tPrints this message.'
  echo -e '--format size\tCreates a EXT4 partition with {size}. Does nothing if'
  echo -e '             \tnot specified and will skip this step. It might lead'
  echo -e "             \tto an error if there is no $TARGETDISK partition. {size} is"
  echo -e '             \tin GB [ 1; 999 ].'
}

function optparse() {
  if [ "$#" -ge 1 ]; then
    case $1 in
      '-h')
        usage
        exit 0
        ;;
      '--format')
        if [ "$#" -ne 2 ] || [ "$2" -le 0 ] || [ "$2" -gt 1000 ]; then
          err 'A size argument in GB is expected or not in the range [ 1; 999 ].'
          usage
          exit 0
        else
          EXT4SIZE=$2
          info "$TARGETDISK EXT4 partition will be of size $EXT4SIZE GB."
        fi
        ;;
      *)
    esac
  fi
  if [ "$EXT4SIZE" -eq -1 ]; then
    info "$TARGETDISK EXT4 partitionning will be skipped."
  fi
}

optparse $@

###############################################################################
# Check System Integrity Protection
################################################################################

info 'Check that System Integrity Protection is turned off'
if hash csrutil 2> /dev/null && csrutil status | grep -q 'disabled'; then
  info 'You must disable System Integrity Protection:'
  info 'Reboot on Recovery HD and execute the command: csrutil disable'
  fatal_error 'System Integrity Protection is enabled.'
else
  success 'System Integrity Protection is disabled.'
fi

################################################################################
# Disable sudo password request
################################################################################

echo 'This script requires admin rights. Please enter your password.'
info 'Attempt to disable sudo timeout.'
info 'The timeout setting will be restored at the end of the script.'
sudo sh -c 'echo "Defaults timestamp_timeout=-1" >> /etc/sudoers'
success 'Sudo timeout has been disabled in /etc/sudoers.'

# Enable cleanup on error.
trap 'cleanup' ERR

################################################################################
# Convert from Core Storage to HFS+ if required.
################################################################################

if diskutil info $ROOTDISK | grep -q 'Core Storage'; then
  info '/dev/disk0s2 is a Core Storage Volume. Converting to HFS+'
  COREVOLUME=$(diskutil list | grep -A1 "Logical Volume on $ROOTDISK" | tail -1)
  sudo diskutil coreStorage revert $COREVOLUME
  success "$ROOTDISK has been converted to HFS+."
  info "Please $RED*REBOOT*$NORMAL now and run this script again!"
  exit 2
else
  success "Volume $ROOTDISK is HFS+."
fi

################################################################################
# Xcode CLI tools and Homebrew
################################################################################

info 'Check homebrew installation'
if ! hash brew 2> /dev/null; then
  info 'Installing Xcode CLI tools...'
  curl -fsSL https://raw.githubusercontent.com/timsutton/osx-vm-templates/master/scripts/xcode-cli-tools.sh \
    | sh
  success 'Xcode CLI tools installed.'

  info 'Installing Homebrew...'
  /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" < /dev/null
  success 'Homebrew installed.'
else
  success 'Xcode CLI and Homebrew already installed.'
fi

################################################################################
# Install docker-machine and docker
################################################################################

info 'Check docker-machine and docker installations'
if ! ( hash docker-machine && hash docker ) 2> /dev/null; then
  info 'Installing docker-machine and docker'
  brew install docker-machine docker
  success 'docker-machine and docker are installed.'
else
  success 'docker-machine and docker are already installed.'
fi

################################################################################
# Get VirtualBox
################################################################################

info 'Check VirtualBox installation'
if ! vboxmanage --help 2> /dev/null 1>&2; then
  if ! [ -a VirtualBox-5.1.4-110228-OSX.dmg ]; then
    info 'Downloading VirtualBox...'
    curl -fOL http://download.virtualbox.org/virtualbox/5.1.4/VirtualBox-5.1.4-110228-OSX.dmg
  fi
  info 'VirtualBox image available. Proceeding installation...'

  hdiutil attach VirtualBox-5.1.4-110228-OSX.dmg
  # NOTE: target is / to install in addition command line tools
  sudo installer -pkg /Volumes/VirtualBox/VirtualBox.pkg -target /
  hdiutil detach /Volumes/VirtualBox/
  success 'VirtualBox installed.'
else
  success 'VirtualBox is already installed.'
fi

################################################################################
# Initialize docker-machine
################################################################################

info 'Check docker-machine initialization'
if ! docker-machine status docker-vm 2> /dev/null 1>&2; then
  docker-machine create --driver virtualbox docker-vm
  success "Docker machine 'docker-vm' created."
else
  success "Docker machine 'docker-vm' already prepared."
fi

################################################################################
# Install Paragon ExtFS
################################################################################

if ! diskutil listFilesystems | grep -q 'UFSD_EXTFS4' 2> /dev/null; then
  if ! [ -a extmac10_trial.dmg ]; then
    info 'Downloading Paragon ExtFS...'
    curl -fOL http://dl.paragon-software.com/demo/extmac10_trial.dmg
  fi
  info 'Paragon ExtFS image available. Proceeding installation...'

  hdiutil attach extmac10_trial.dmg
  sudo installer -pkg /Volumes/ParagonFS.localized/FSInstaller.app/Contents/Resources/Paragon\ ExtFS\ for\ Mac\ OS\ X.pkg -target /
  hdiutil detach /Volumes/ParagonFS.localized
  success 'Paragon ExtFS installed.'
else
  success 'Paragon ExtFS already installed.'
fi

################################################################################
# Resize the disk
################################################################################

if ! [ "$EXT4SIZE" -eq -1 ]; then
  info "Check $TARGETDISK EXT4 filesystem"
  if diskutil list disk0 | grep -q 'Linux Filesystem\|Microsoft Basic Data'; then
    if diskutil list disk0 | grep "\(Linux Filesystem\|Microsoft Basic Data\).*${TARGETDISK}$"; then
      info "$TARGETDISK EXT4 is already created. Formatting in EXT4..."
      diskutil eraseVolume UFSD_EXTFS4 '1' $TARGETDISK
      success "$TARGETDISK volume has been erased to EXT4 format."
    else
      debug diskutil list && diskutil list
      fatal_error "Linux Filesystem found but not at /dev/$TARGETDISK. Please check."
    fi
  else
    info "Resizing $ROOTDISK to create EXT4 $TARGETDISK partition..."
    sudo diskutil resizeVolume $ROOTDISK ${EXT4SIZE}g UFSD_EXTFS4 '1' 0g
    success "$TARGETDISK EXT4 volume has been created."
  fi
else
  info 'Skipping EXT4 partition creation'
fi

if diskutil list disk0 | grep -q "\(Linux Filesystem\|Microsoft Basic Data\).*${TARGETDISK}$"; then
  success "Found $TARGETDISK EXT4 volume."
else
  fatal_error "A $TARGETDISK partition is required beyond this point."
fi

###############################################################################
# Virtual disk to physical disk mapping
###############################################################################

if ! docker-machine status docker-vm | grep -q 'Running'; then
  VIRTUALDISK=`mktemp /tmp/main.vmdk.XXXXXX` || \
    fatal_error 'Cannot create temporary virtual disk'

  rm $VIRTUALDISK

  # Physical partition must remain unmounted
  if [ -d /Volumes/1 ]; then
    info 'Unmounting the "1" partition'
    diskutil umount '1'
  fi

  info 'Creating vmdk'
  sudo vboxmanage internalcommands createrawvmdk -filename $VIRTUALDISK -rawdisk /dev/${TARGETDISK}
  sudo chmod 666 $VIRTUALDISK
  sudo chmod 666 /dev/${TARGETDISK}

  info 'Attaching physical partition to the docker-vm'
  vboxmanage storageattach docker-vm --storagectl "SATA" --port 2 --device 0 --type hdd --medium $VIRTUALDISK

  info 'Starting docker-vm'
  docker-machine start docker-vm
  success 'Docker machine ready'
fi

info 'Exiting...'
cleanup
