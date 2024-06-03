#!/bin/sh
set -o errexit

COLOR_RED="31"
COLOR_GREEN="32"
COLOR_YELLOW="33"
COLOR_BLUE="34"

RED="\e[${COLOR_RED}m"
GREEN="\e[${COLOR_GREEN}m"
YELLOW="\e[${COLOR_YELLOW}m"
BLUE="\e[${COLOR_BLUE}m"

BOLD="\e[1m"
BOLDGREEN="\e[1;${COLOR_GREEN}m"
BOLDRED="\e[1;${COLOR_RED}m"
BOLDBLUE="\e[1;${COLOR_BLUE}m"
ITALICRED="\e[3;${COLOR_RED}m"
CLEARFORMAT="\e[0m"

bold (){
  echo -e "\n${BOLD}$1${CLEARFORMAT}"
}

info (){
  echo -e "\n${BLUE}$1${CLEARFORMAT}\n"
}
alert (){
  echo -e "\n${YELLOW}$1${CLEARFORMAT}\n"
}
error (){
  echo -e "\n${BOLDRED}$1${CLEARFORMAT}\n"
}
ok (){
  echo -e "\n${BOLDGREEN}$1${CLEARFORMAT}\n"
}

check_context(){
  CONFIG=$(kubectl config current-context)
  if [ "$CONFIG" != "kind-$1" ]; then
    error "Error: You are not in the correct kubectl context, please use $CONTEXT_NAME"
    exit 1
  fi
}

check_folder() {
    if [ -d "$1" ]; then
        # Folder exists
        return 0
    else
        # Folder does not exists
        return 1
    fi
}

check(){
    if [ ! command -v $1 &> /dev/null ]; then
        error "$1 is not installed, please install. Check link in README.md."
        exit 1
    else
        ok "$1 - OK"
    fi
}