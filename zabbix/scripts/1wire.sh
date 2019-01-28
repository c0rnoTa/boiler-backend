#!/bin/bash
HOST="192.168.10.22"
PORT="80"
status="get_temp.php"

function query() {
	curl -s "http://${HOST}:${PORT}/${status}?id=$1"
}

if [ $# == 0 ]; then
		echo $"Usage $0 {device-id}"
		exit
else
	query "$1"
fi
