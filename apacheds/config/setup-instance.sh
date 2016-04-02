#!/bin/bash
##########################################################
# Sets up a single apacheds instance with one partition. #
# Usage: setup-instance.sh DOMAIN [INSTANCE_ID]          #
##########################################################

DOMAIN=${1:-$(hostname -d)} # Use host's domain name if not provided

if [ -z "$DOMAIN" ]; then
	echo "Usage: $0 DOMAIN [INSTANCE_ID]" >&2
	echo "Or make dnsdomainname resolve domain name and call $0 again without parameters" >&2
	exit 1
fi

PARTITION_ID=${2:-$(sed 's/\..*//' <<< $DOMAIN)} # First domain segment as partition ID
PARTITION_SUFFIX="dc=${DOMAIN/./,dc=}"
KERBEROS_REALM=${DOMAIN^^} # upper case domain
SASL_HOST=$(hostname -f)
SASL_PRINCIPAL="ldap\/$SASL_HOST@$KERBEROS_REALM"
SASL_REALM=$DOMAIN
APACHEDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

CONTEXTENTRY=$(
echo "dn: $PARTITION_SUFFIX
dc: $PARTITION_ID
objectclass: domain
objectclass: top" | base64 | tr -d '\n'
)

sed -e "s/ads-partitionid: example/ads-partitionid: $PARTITION_ID/" \
    -e "s/ads-partitionId=example/ads-partitionId=$PARTITION_ID/" \
    -e "s/dc=example,dc=com/$PARTITION_SUFFIX/" \
    -e "s/ads-contextentry:: .*/ads-contextentry:: $CONTEXTENTRY/" \
\
    -e "s/ads-krbPrimaryRealm: .*/ads-krbPrimaryRealm: $KERBEROS_REALM/" \
\
    -e "s/ads-saslHost: .*/ads-saslHost: $SASL_HOST/" \
    -e "s/ads-saslPrincipal: .*/ads-saslPrincipal: $SASL_PRINCIPAL/" \
    -e "s/ads-saslRealms: .*/ads-saslRealms: $SASL_REALM/" \
    -e "/^ .*/d" \
    $APACHEDS_DIR/ldif/default-config.ldif | uniq > $APACHEDS_DIR/instances/default/conf/config.ldif

# TODO: to change ports
#     -e "s/ads-systemport: 10389/ads-systemport: 389/" \
#    -e "s/ads-systemport: 10636/ads-systemport: 636/" \
