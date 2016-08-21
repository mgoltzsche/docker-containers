#!/bin/bash

# Create CA if not created
if [ ! -f "ca/ssl/certs/cacert.pem" ]; then
	echo "Creating new Certified Authority ..."
	read -p "Please enter CN: " CA_DN
	[ "$CA_DN" ] &&
	ca/ca.sh initca "$CA_DN" || exit 1
fi

ca/ca.sh updateca || exit 1

# Generate signed certificates
ca/ca.sh gensignedcerts ./ssl mail.algorythm.de web.algorythm.de
