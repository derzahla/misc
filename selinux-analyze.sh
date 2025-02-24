#!/bin/bash

_hours=24

help_msg() {
  printf "Usage: $0 [-h <previous_hours>] [-b <binary_name>]\n\n"
  printf "    previous_hours     Number of hours to search backward through audit history for denials (default: $_hours)\n"
  printf "    binary_name        Filter the denial list by the name of the binary that triggered it (default: include all binaries))\n\n"
}

_binary=""

#Check cmdline options - set variables accordingly
while getopts "h:b:" _opt; do
  case $_opt in
    h) _hours=$OPTARG ;;
    b) _binary="-x $OPTARG" ;;
    \?) help_msg && exit 1;;
  esac
done

_previous_date=$(date -u -d "-${_hours} hour" +%m/%d/%y\ %H:%M:%S)

echo "Auditing from : $_previous_date                                                                  "
echo "-----------------------------------------"

#Search for SELinux denials in the last 24 hours or number specified by -h option
_audit_results=$(ausearch -m avc -sv no -l -i -ts ${_previous_date} ${_binary})

#Set up temp files
_tmpf=$(mktemp)
_tmp_modtemplate=$(mktemp)

#Store audit results in temp file
cat <( echo "$_audit_results") > $_tmpf

#Declare menu function
menu_msg() {
  printf "\nEnter selection: (E)dit audit results, e(X)plain denials, (V)iew module template, (C)ompile module pp, (R)evert audit results\n" 
  read -N 1 -s -p ":> " _response
  case "$_response" in
    E)
      #Open audit results in text editor to allow manual pruning of which denials should be allowed in generated module
      _edit="${EDITOR:-vi}"
      bash -c "$_edit $_tmpf"
      menu_msg
      ;;
    X)
      #Explain in further detail the SELinux denials from audit results
      audit2why -i $_tmpf | less
      menu_msg
      ;;
    V)
      #Generate SELinux policy module template and display results in pager
      audit2allow -i $_tmpf -m working_policy > $_tmp_modtemplate 
      less $_tmp_modtemplate
      menu_msg
      ;;
    C) 
      #First (Re)generate policy module template from pruned audit results
      audit2allow -i $_tmpf -m working_policy > $_tmp_modtemplate 
      #Prompt for new module name based via user input
      printf "\nEnter a descriptive name for your new module(no spaces): "
      read _modname
      #Replace generic name in template with user chosen name
      sed -e "s/working_policy/$_modname/g" $_tmp_modtemplate > $_modname.te
      #Verify template syntax and generate non-base SELinux module
      checkmodule -M -m -o $_modname.mod $_modname.te
      #Compile SELinux policy package from module
      semodule_package -o $_modname.pp -m $_modname.mod
      printf "Module policy package for $_modname compiled...\nTo load your module policy package execute: \n\n\tsemodule -i $_modname.pp\nn"
      ;;
    R)
      #Revert any custom edits made to audit results
      cat <( echo "$_audit_results") > $_tmpf
      menu_msg
      ;;
    *)
      menu_msg
      ;;
  esac
}   

#Call menu function
menu_msg
