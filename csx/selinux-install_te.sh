#!/bin/bash
usage() {
  printf "Usage: $0 [-b] <file.te>\n"
  printf "Build <file.te> into policy package and install it - Requires sudo or root\n\n"
  printf "    -b                Build pp only - do not install\n\n"
}

#Check cmdline options - set variables accordingly
while getopts "hb" _opt; do
  case $_opt in
    b) _buildonly=1 ;;
    \?) usage && exit 1;;
  esac
done

shift $(($OPTIND-1))

_fext=$( echo $1 | cut -d. -f2)

if [ ! "x$_fext" == "xte" ]; then 
  usage
  exit 1
fi

_modname=$(egrep '^module.*;$' ${1} | cut -d" " -f 2)

if [ -z $_modname ]; then 
  usage
  printf "\n$1 does not appear to be a valid te file\n\n"
  exit 1
fi

checkmodule -M -m -o /tmp/$_modname.mod $_modname.te
#Compile SELinux policy package from module
semodule_package -o /tmp/$_modname.pp -m /tmp/$_modname.mod
if ((_buildonly)) ; then
  printf "Module policy package for $_modname compiled...\nTo load your module policy package execute: \n\n\tsemodule -i /tmp/$_modname.pp\nn"
  exit 0
fi
sudo semodule -i /tmp/$_modname.pp


