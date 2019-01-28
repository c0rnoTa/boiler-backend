#!/bin/bash

#http://192.168.10.82/status.xml
#		T_KOTLA => $message->{val0} . "." . $message->{val6},
#		T_OBRATKI => $message->{val1} . "." . $message->{val7},
#		MOSHNOST => $message->{val2} . "." . $message->{val10},
#		RASCHOD => $message->{val3},
#		PLAMJA => $message->{val4},
#		REZHIM => $message->{val5},
#		T_KOMNATY1 => $message->{val11});

HOST="192.168.10.82"
PORT="80"
status="status"

function request() {
	curl -s http://${HOST}:${PORT}/${status}.xml | grep "<$1>" | awk -F'>|<' '{ print $3}'
}

function query() {

case "$1" in
"t-kotla")
	INT=`request "val0"`
        FLOAT=`request "val6"`
        echo $INT.$FLOAT
;;
"t-obratki")
	INT=`request "val1"`
        FLOAT=`request "val7"`
        echo $INT.$FLOAT
;;
"moshnost")
	INT=`request "val2"`
        FLOAT=`request "val10"`
        echo $INT.$FLOAT
;;
"rashod")
    	request "val3"
;;
"plamja")
	request "val4"
;;
"rezhim")
      	request "val5"
;;
"t-komnaty1")
	request "val11"
;;
*) echo ZBX_NOTSUPPORTED; exit 1 ;;
esac

}

if [ $# == 0 ]; then
		echo $"Usage $0 {t-kotla|t-obratki|moshnost|rashod|plamja|rezhim|t-komnaty1}"
		exit
else
	query "$1"
fi
