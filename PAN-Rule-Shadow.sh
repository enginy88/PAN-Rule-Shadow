#!/bin/bash

# AUTHOR: Engin YUCE <enginy88@gmail.com>
# DESCRIPTION: Shell script for fetching rule shadow warning messages on PANOS. (Only works with v9.1+)
# VERSION: 1.0
# LICENSE: Copyright 2020 Engin YUCE. Licensed under the Apache License, Version 2.0.


PAN_USERNAME="admin"
PAN_PASSWORD="admin"
PAN_IP="1.2.3.4"
PAN_VSYS="vsys1"


# BELOW THIS LINE, THERE BE DRAGONS!


_checkVariables()
{
	[[ ! -z "$PAN_USERNAME" ]] || { echo "Script variable is missing, exiting!" ; exit 1 ; }
	[[ ! -z "$PAN_PASSWORD" ]] || { echo "Script variable is missing, exiting!" ; exit 1 ; }
	[[ ! -z "$PAN_IP" ]] || { echo "Script variable is missing, exiting!" ; exit 1 ; }
	[[ ! -z "$PAN_VSYS" ]] || { echo "Script variable is missing, exiting!" ; exit 1 ; }
}


_checkCurlAvailable()
{
	curl --version &>/dev/null
	if [[ $? != 0 ]]
	then
		echo "Error on finding curl, install the curl utility, exiting!" ; exit 1
	fi
}


_getAPIKey()
{
	local CALL=$(curl -X GET --insecure -m 5 "https://$PAN_IP/api/?type=keygen&user=$PAN_USERNAME&password=$PAN_PASSWORD" 2>/dev/null)
	if [[ $? != 0 || -z "$CALL" ]]
	then
		echo "Error on curl call, check the IP, exiting!" ; exit 1
	fi
	echo "$CALL" | grep -F "response" | grep -F "status" | grep -F "success" &>/dev/null
	if [[ $? != 0 ]]
	then
		echo "Error on curl response, check the PAN credentials, exiting!" ; exit 1
	fi
	KEY=$(echo "$CALL" | sed -n 's/.*<key>\([a-zA-Z0-9=]*\)<\/key>.*/\1/p')
	if [[ $? != 0 || X"$KEY" == X"" ]]
	then
		echo "Error on curl response, cannot parse API key, exiting!" ; exit 1
	fi
}


_callXMLAPIShadowCount()
{
	local CALL=$(curl -H "X-PAN-KEY: $KEY" --insecure -m 5 "https://$PAN_IP/api/?type=op&cmd=<show><shadow-warning><count><vsys>$PAN_VSYS</vsys></count></shadow-warning></show>" 2>/dev/null)
	if [[ $? != 0 || -z "$CALL" ]]
	then
		echo "Error on curl call, check the IP, exiting!" ; exit 1
	fi
	echo "$CALL" | grep -F "response" | grep -F "status" | grep -F "success" &>/dev/null
	if [[ $? != 0 ]]
	then
		echo "Error on curl response, check the PANOS version, exiting!" ; exit 1
	fi
	COUNT_RESPONSE=$CALL
}


_callXMLAPIShadowWarning()
{
	local CALL=$(curl -H "X-PAN-KEY: $KEY" --insecure -m 5 "https://$PAN_IP/api/?type=op&cmd=<show><shadow-warning><warning-message><vsys>$PAN_VSYS</vsys><uuid>$1</uuid></warning-message></shadow-warning></show>" 2>/dev/null)
	if [[ $? != 0 || -z "$CALL" ]]
	then
		echo "Error on curl call, check the IP, exiting!" ; exit 1
	fi
	echo "$CALL" | grep -F "response" | grep -F "status" | grep -F "success" &>/dev/null
	if [[ $? != 0 ]]
	then
		echo "Error on curl response, check the PANOS version, exiting!" ; exit 1
	fi
	WARNING_RESPONSE=$CALL
}


_iterateShadowCount()
{
	while :
	do
		local ENTRY_SEPERATOR="<entry name="
		case $COUNT_RESPONSE in
		(*"$ENTRY_SEPERATOR"*)
			local FOUND="y"
			local BEFORE=${COUNT_RESPONSE%%"$ENTRY_SEPERATOR"*}
			local AFTER=${COUNT_RESPONSE#*"$ENTRY_SEPERATOR"}
			;;
		(*)
			local FOUND="n"
			local BEFORE=$COUNT_RESPONSE
			local AFTER=
			;;
		esac
			if [[ x$FOUND == xy ]]
			then
				local UUID_SEPERATOR="uuid="
				local UUID_STRING=${AFTER#*"$UUID_SEPERATOR"}
				local UUID_STRING=$(echo $UUID_STRING | head)
				local UUID=$(echo $UUID_STRING | cut -d \" -f 2)
				UUID_ARRAY+=("$UUID")

				COUNT_RESPONSE=$AFTER
			else
				break
			fi
	done
}


_iterateShadowWarning()
{
	while :
	do
		local MEMBER_SEPERATOR="<member>"
		case $WARNING_RESPONSE in
		(*"$MEMBER_SEPERATOR"*)
			local FOUND="y"
			local BEFORE=${WARNING_RESPONSE%%"$MEMBER_SEPERATOR"*}
			local AFTER=${WARNING_RESPONSE#*"$MEMBER_SEPERATOR"}
			;;
		(*)
			local FOUND="n"
			local BEFORE=$WARNING_RESPONSE
			local AFTER=
			;;
		esac
			if [[ x$FOUND == xy ]]
			then
				local MEMBER_CLOSE_SEPERATOR="</member>"
				local MESSAGE_STRING_BEFORE=${AFTER%%"$MEMBER_CLOSE_SEPERATOR"*}
				local MESSAGE_STRING_AFTER=${AFTER#*"$MEMBER_CLOSE_SEPERATOR"}
				local MESSAGE_STRING=$(echo $MESSAGE_STRING_BEFORE | head)
				MESSAGE_ARRAY+=("$MESSAGE_STRING")

				WARNING_RESPONSE=$MESSAGE_STRING_AFTER					
			else
				break
			fi
	done
}


_main()
{
	_checkVariables
	_checkCurlAvailable
	echo "Attempt to fetch rule shadow warnings. (TIME: $(date))"
	echo "Using IP: $PAN_IP, USER: $PAN_USERNAME, VSYS: $PAN_VSYS."
	echo "---"
	_getAPIKey
	_callXMLAPIShadowCount
	_iterateShadowCount

	for VALUE in "${UUID_ARRAY[@]}"
	do
		_callXMLAPIShadowWarning $VALUE
		_iterateShadowWarning

		for VALUE in "${MESSAGE_ARRAY[@]}"
		do
			echo $VALUE
		done

		unset MESSAGE_ARRAY
	done

	echo "---"
	echo "All succeeded, bye!"
}


_main
