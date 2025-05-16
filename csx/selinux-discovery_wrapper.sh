#!/bin/bash

usage() {
  echo 'usage: $(basename $0) <ptc|dispatch|csxt> <enable|report|status>'
}

if [ $# -ne 2 ]; then
  usage
  exit 1
fi

ALL_STATUS_FILE="all_statuses.csv"

export MODE="$2"
case ${MODE} in
  "enable"|"report"|"status")
    scp selinux-discovery.sh lnx30563.csxt.csx.com:~/
    if [ ${MODE} == "status" ]; then
      [ -d RESULTS ] || mkdir RESULTS 
      echo "application,hostname,os_compatibility,selinux_status,auditd_status" > RESULTS/${ALL_STATUS_FILE}
    fi
    for h in $(grep '^      lnx' inventory/ptc.yaml); do
      APP_TYPE=$(yamlpp-load inventory/ptc.yaml  | awk -vH=$h '{if($0 ~ H) {gsub("\"","",$0); print $1}}') 
      ping -c 1 $h 2>&1>/dev/null
      if [ $? -eq 0 ]; then
        ssh $h "cp -f ~/selinux-discovery.sh /tmp && sudo chmod +x /tmp/selinux-discovery.sh  && sudo bash /tmp/selinux-discovery.sh ${MODE}; sudo unlink /tmp/selinux-discovery.sh" > RESULTS/${APP_TYPE}_${h}_selinux-discovery-${MODE}
      else
        echo "$h,does_not_respond_to_ping" > RESULTS/${APP_TYPE}_${h}_selinux-discovery-${MODE}
      fi

      if [ ${MODE} == "status" ]; then
        echo -n "${APP_TYPE},$(cat RESULTS/${APP_TYPE}_${h}_selinux-discovery-${MODE})" >> RESULTS/${ALL_STATUS_FILE}
        echo >> RESULTS/${ALL_STATUS_FILE}
      fi
    done
  ;;
  *)
    usage
    exit 1
  ;;
esac
