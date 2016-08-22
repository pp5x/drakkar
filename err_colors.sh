#!/bin/bash

NORMAL=$(tput sgr0)
GREEN=$(tput setaf 2; tput bold)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)

function debug() { ((DEBUG)) && echo ">>> $*"; }

function err() { echo -e "$RED[ERROR]      $*$NORMAL"; }
function success() { echo -e "$GREEN[SUCCESS]    $*$NORMAL"; }
function info() { echo -e "$YELLOW[INFO]       $*$NORMAL"; }

# Trigger failure
function fatal_error() { err $*; return 1; }
