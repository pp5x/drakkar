# Drakkar

*Work in progress.*

Inspired by this project: <https://github.com/yantis/instant-archlinux-on-mac>

Starting from a clean OS X install the script will download all necessary tools
and setup an EXT4 partition (disk0s4).

## TODO

* Mount the partition into boot2docker VirtualBox VM.
* Setup a Docker image with my own configuration. Once the image built, we
  should rely on it to install ArchLinux on the physical partition.
* Must remain a minimal installation, but will embeds working drivers for 15"
  MacBook Pro 2012.
