#!/bin/bash

CURDIR=$(dirname $0)
NAME=$(basename $0)
DEBUG=1
EXT4SIZE=-1

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
  echo -e '             \tto an error if there is no disk0s4 partition. {size} is'
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
          info "disk0s4 EXT4 partition will be of size ${EXT4SIZE} GB."
        fi
        ;;
      *)
    esac
  fi
  if [ "$EXT4SIZE" -eq -1 ]; then
    info 'disk0s4 EXT4 partitionning will be skipped.'
  fi
}

optparse $@

###############################################################################
# Check System Integrity Protection
################################################################################

info 'Check that System Integrity Protection is turned off'
if ! csrutil status | grep -q 'disabled'; then
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

if diskutil info disk0s2 | grep -q 'Core Storage'; then
  info '/dev/disk0s2 is a Core Storage Volume. Converting to HFS+'
  COREVOLUME=$(diskutil list | grep -A1 'Logical Volume on disks2' | tail -1)
  sudo diskutil coreStorage revert $COREVOLUME
  success 'disk0s2 has been converted to HFS+.'
  info "Please $RED*REBOOT*$NORMAL now and run this script again!"
  exit 2
else
  success 'Volume disk0s2 is HFS+.'
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
  info 'Check disk0s4 EXT4 filesystem'
  if diskutil list disk0 | grep -q 'Linux Filesystem'; then
    if diskutil list disk0 | grep -q 'Linux Filesystem.*disk0s4$'; then
      info 'disk0s4 EXT4 is already created. Formatting in EXT4...'
      diskutil eraseVolume UFSD_EXTFS4 'Linux' disk0s4
      success 'disk0s4 volume has been erased to EXT4 format.'
    else
      debug diskutil list && diskutil list
      fatal_error 'Linux Filesystem found but not at disk0s4. Please check.'
    fi
  else
    info 'Resizing disk0s2 to create EXT4 disk0s4 partition...'
    sudo diskutil resizeVolume disk0s2 ${EXT4SIZE}g 1 UFSD_EXTFS4 'Linux' 0g
    success 'disk0s4 EXT4 volume has been created.'
  fi
else
  info 'Skipping EXT4 partition creation'
fi

if diskutil list disk0 | grep -q 'Linux Filesystem.*disk0s4$'; then
  success 'Found disk0s4 EXT4 volume.'
else
  fatal_error 'A disk0s4 partition is required beyond this point.'
fi

###############################################################################
# Virtual disk to physical disk mapping
###############################################################################

# TODO

info 'Exiting...'
cleanup
