#!/bin/bash 

MIN_RHEL_VERSION=7.5
CURRENT_RHEL=$(grep -E '^VERSION_ID=.*' /etc/os-release | cut -d'"' -f2)
STATUS_LINE="${HOSTNAME}"
SELINUX_STATUS=$(getenforce)
PKGS_EL7="libselinux-python"
PKGS_EL8="python3-libselinux"
PKGS_ALL="policycoreutils policycoreutils-python setools-console checkpolicy audispd-plugins"
AUDISPCONFDIR="/etc/audit/plugins.d"

usage() {
  echo "usage: $(basename $0) <report|enable|status>"
  echo "    report: run 'selinux' commands to generate detailed reports"
  echo "    enable: ensure all options and services associated with SEL are configured and enabled"
  echo "    status: print selinux status and mode and whether auditd is enabled."
}

selinux_confchk() {
  case ${MAJOR_VERSION} in
    7)
      PKGS_ALL+=" $PKGS_EL7"
      AUDISPCONFDIR="/etc/audisp/plugins.d"
    ;;
    8)
      PKGS_ALL+=" $PKGS_EL8"	  
    ;;
  esac

  printf "Checking for required packages\n"
  for pkg in ${PKGS_ALL}; do
      printf "  $pkg...\t\t\t"
      rpm -qa | grep -q $pkg && printf "present\n" || printf "installing\n" || yum -y install $pkg &>/dev/null 
#      if [ $? -ne 0 ]; then
#        echo "Unable to install packages, bailing!"
#        exit 1
#      fi
    done
  printf "\nChecking auditd status\n"
  if [ -z "$AUDITD_STATUS" ]; then
    systemctl enable --now auditd
    echo "  AuditD has been enabled and started."
  else
    echo "  AuditD is currently running."
  fi

  #Enable auditd-to-syslog plugin
  _audit_syslogcnf="$AUDISPCONFDIR/syslog.conf"
  printf "\nChecking for auditd syslog plugin config\n"
  if [ ! -f "${_audit_syslogcnf}" ]; then
    echo "  Auditd is not configured to log through syslog, adding config at ${_audit_syslogcnf}"
    cat << EOF > "${_audit_syslogcnf}"
active = yes
direction = out
path = /sbin/audisp-syslog
type = always
args = LOG_INFO LOG_LOCAL2
format = string
EOF
    echo "Restarting auditd..."
    systemctl condrestart auditd
  else
    printf "  ${_audit_syslogcnf} file is already present.\n  NO CHANGES MADE.\n  It looks like auditd syslog plugin already configured. If this is unexpected confirm file contents manually"
  fi
     
}

selinux_reports() {
  echo "----SESTATUS_OUTPUT----"
  # Dump full sestatus
  sestatus 
  
  echo "----SEMODULE_LISTINGS---"
  #List all non-base modules
  semodule -lfull 

  
  echo "----SEBOOLEAN_LISTINGS---"
  #List local custom booleans
  semanage boolean --list -C 
}

if [ $# -ne 1 ]; then
  usage 
  exit 1
fi

CURRENT_OS=$(grep -E '^ID=.*' /etc/os-release | cut -d'"' -f2)
if [ x"$CURRENT_OS" != x"rhel" ]; then
  echo "This script should only run on RHEL"
  echo "Your OS appears to be $CURRENT_OS"
  exit 1
fi

MAJOR_VERSION=$(echo $CURRENT_RHEL | cut -d'.' -f1)
MINOR_VERSION=$(echo $CURRENT_RHEL | cut -d'.' -f2)
MIN_MAJV=$(echo $MIN_RHEL_VERSION | cut -d'.' -f1)
MIN_MINV=$(echo $MIN_RHEL_VERSION | cut -d'.' -f2)

if [ "$MAJOR_VERSION" -lt "$MIN_MAJV" ] || ([ "$MAJOR_VERSION" -eq "$MIN_MAJV" ] && [ "$MINOR_VERSION" -lt "$MIN_MINV" ]); then
  STATUS_LINE+=",OS_RELEASE_INCOMPATIBLE_${MAJOR_VERSION}.${MINOR_VERSION}"
  echo ${STATUS_LINE}
  exit 1
else
  STATUS_LINE+=",OS_RELEASE_COMPATIBLE_${MAJOR_VERSION}.${MINOR_VERSION}"
fi

AUDITD_STATUS=$(systemctl is-enabled auditd)

STATUS_LINE+=",${SELINUX_STATUS}"
STATUS_LINE+=",${AUDITD_STATUS}"

case $1 in
  "report")
     if [ ${SELINUX_STATUS} != "Disabled" -a ${AUDITD_STATUS} != "disabled" ]; then
       selinux_reports
     else
       STATUS_LINE+=",SELINUX_${SELINUX_STATUS}_UNABLE_TO_GENERATE_SELINUX_REPORTS"
     fi
     echo "${STATUS_LINE}"
  ;;
  "status")
    echo "${STATUS_LINE}"
  ;;
  "enable")
    selinux_confchk
    if [ ${SELINUX_STATUS} == "Disabled" ]; then
      printf "\nSELinux currently appears to be disabled.\n" 
      sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
      touch /.autorelabel
      echo "It has now been configured to be enabled in Permissive mode rupon next reboot and root filesystem will be relabeled"
    elif [ ${SELINUX_STATUS} == "Permissive" ]; then
      printf "\nSELinux already enabled in Permissive mode, for more details run the script in report mode.\n"
      printf "\tNote: If unexpected avc denials are encountered, filesystem may require relabeling, via 'restorecon' or 'touch /.autorelabel' and rebooting\n"
    elif [ ${SELINUX_STATUS} == "Enforcing" ]; then
      printf "\nSELinux is Enabled AND Enforcing, for more details run the script in report mode.\n"
    else
      printf "\nError, unexpected SELinux status of ${SELINUX_STATUS}. Aborting\n"
      exit 1
    fi
    # Rebuild SEL policy, ensuring dontaudit rules are enabled
    printf "\nRebuilding SEL policy with default settings\n"
    semodule -B
    echo "done"
  ;;
  *)
    usage 
    exit 1
  ;;
esac
