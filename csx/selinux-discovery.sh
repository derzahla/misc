#!/bin/bash -x

usage() {
  echo "usage: $(basename $0) <report|enable|status>"
  echo "report: run 'selinux' commands to generate detailed reports"
  echo "enable: enable 'selinux', NOTE: this requires a reboot before it will be effective."
  echo "status: print whether selinux and auditd are enabled, and in the case of selinux if it is in enforcing or permissive mode."
}

if [ $# -ne 1 ]; then
  usage 
  exit 1
fi

selinux_reports() {
  echo "----SESTATUS_OUTPUT----"
  # Dump full sestatus
  sestatus 

  # Turn on all AVC Messages for which SELinux currently is "dontaudit"ing.
  semodule -DB

  
  echo "----SEMODULE_LISTINGS---"
  #List all non-base modules
  semodule -lfull 

  
  echo "----SEBOOLEAN_LISTINGS---"
  #List local custom booleans
  semanage boolean --list -C 
}

MIN_RHEL_VERSION=7.9
CURRENT_RHEL=$(grep -E '^VERSION_ID=.*' /etc/os-release | cut -d'"' -f2)
STATUS_LINE="${HOSTNAME}"
SELINUX_STATUS=$(getenforce)
PKGS_EL7="libselinux-python"
PKGS_EL8="python3-libselinux"
PKGS_ALL="policycoreutils policycoreutils-python setools-console checkpolicy"

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

case "$1" in
  "report"|"enable"|"status")
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
      *)
        usage
        exit 1
      ;;
    esac
    if [ $1 == "enable" ]; then
      if [ ${SELINUX_STATUS} == "Disabled" ]; then
        #Install $PKGS if not already installed
        for pkg in ${PKGS_ALL}; do
          rpm -qa | grep -q $pkg || yum -y install $pkg
          if [ $? -ne 0 ]; then
            echo "Unable to install packages, bailing!"
            exit 1
          fi
        done

        if [ ${MAJOR_VERSION} -eq 7 ]; then
          for pkg in ${PKGS_EL7}; do
            rpm -qa | grep -q $pkg || yum -y install $pkg
            if [ $? -ne 0 ]; then
              echo "Unable to install packages, bailing!"
              exit 1
            fi
          done
        else
          for pkg in ${PKGS_EL8}; do
            rpm -qa | grep -q $pkg || yum -y install $pkg
            if [ $? -ne 0 ]; then
              echo "Unable to install packages, bailing!"
              exit 1
            fi
          done
        fi

        if [ -z "$auditd_status" ]; then
          systemctl enable --now auditd
          echo "AuditD has been enabled and started."
        else
          echo "AuditD is already running."
        fi

        echo "SELinux will be enabled permissively on reboot and root filesystem will be relabeled"
        sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
        touch /.autorelabel
      else
        echo "SELinux already enabled, run the script in report mode."
        exit 0
      fi
    fi
  ;;
  *)
    usage 
    exit 1
  ;;
esac
