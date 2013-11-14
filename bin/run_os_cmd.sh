#!/bin/sh

CMD=$@
base_dir=/x/itools/cloud_minion
conf_file=${base_dir}/conf/cm.cfg

if [ "$CMD" = "" ]; then
    echo "Usage: $0 <os command>"
    exit
fi

for OS_VAR in `cat $conf_file | egrep "^OS_|^SERVICE_"`; do
    export $OS_VAR
done


$CMD

