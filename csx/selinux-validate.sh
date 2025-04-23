#!/bin/bash

usage() {
  printf "Usage: $0 [-v] || [-d <module_name> [-k] [-c] ]\n"
  printf "    -v                 Validate SELinux packages and all files under /var/lib/selinux\n"
  printf "    -d                 Decompile SELinux module and list plain text rules\n"
  printf "    -p                 Use pager on output\n"
  printf "    -k                 Keep module.extract directory, do not clean up\n\n"
}

#Check cmdline options - set variables accordingly
while getopts "d:pkv" _opt; do
  case $_opt in
    d) _modname="$OPTARG" ;;
    p) _ocmd="less" ;;
    k) _noclean=1 ;;
    v) _validate=1 ;;
   \?) usage && exit 1;;
  esac
done
_OCMD=${_ocmd:-cat}
# Also show usage if no options are passed
if ((OPTIND == 1)); then 
  usage && exit 1
fi

decompile_mod() {
  #If module specified is valid, run extract & decompile, else print error and exit
  semodule -l | grep -qE "^${_modname}$"
  if [[ "$?" -eq  "0" ]]; then
    # Delete module.extract dir if exists
    test -d ${_modname}.extract && rm -rf ${_modname}.extract
    mkdir ${_modname}.extract
    cd ${_modname}.extract
    semodule -E ${_modname} &>/dev/null
    semodule_unpackage ${_modname}.pp ${_modname}.mod ${_modname}.fc
    cd ..
    /usr/libexec/selinux/hll/pp ${_modname}.extract/${_modname}.pp > ${_modname}.extract/${_modname}.out
    bash -c "$_OCMD ${_modname}.extract/${_modname}.out"
    
    # Keep extract dir if ((_noclean))
    if ((_noclean)); then
      exit 0
    else
      rm -rf ${_modname}.extract
      exit 0 
    fi
  else
    printf "${_modname} is not a valid SELinux module\n\n"
    exit 1
  fi 
}

se_validate() {
_fmt="%-30s%-35s\n" 

printf "\nValidating installed SELinux packages for file integrity...\n-----------------------\n" 
for x in $(rpm -qa | grep -i selinux) ; do 
   _shortn=$( echo ${x} | awk -F'-[0-9]' '{print $1 }')
   _result="$(rpm -V "${x}")"
   _retv=$?
   if ((! _retv)); then
     printf "$_fmt" "$_shortn" "SUCCESS: files are original and unmodifed"
   else
     printf "$_fmt" "$_shortn" "FAILURE: Discrepencies detected with files:"
     printf "\n#######\n$_result\n#######\n\n"
   fi
done
printf "\n\n"
printf "Validating files under /var/lib/selinux for package ownership...\n-----------------------\n"
for x in $(find /var/lib/selinux -type f) ; do
  rpm -qf $x &>/dev/null || echo "WARNING: $x is not owned by an installed package"
done
exit 0
}

# _validate overrules any other options when set
if ((_validate)); then
  se_validate
elif [ -n $_modname ]; then
  decompile_mod
fi

