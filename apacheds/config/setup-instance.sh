#!/bin/sh
##########################################################
# Sets up a single apacheds instance with one partition. #
# Usage: setup-instance.sh [DOMAIN [PARTITION_ID]]       #
##########################################################

# Check if fully qualified machine name defined
if [ -z "$(hostname -d)" ] || [ -z "$(hostname -f)" ]; then
	echo "Please configure hostname properly." >&2
	echo 'Setup a proper hostname by adding an entry to /etc/hosts like this:' >&2
	echo ' 172.17.0.2      auth.example.org auth' >&2
	echo 'When using docker start the container with the -h option' >&2
	echo 'to configure the hostname. E.g.: -h auth.example.org' >&2
	exit 1
fi

if [ -f '/apacheds/instances/default/conf/ou=config.ldif' ]; then
	echo 'Default instance already configured. Skipping configuration' >&2
	exit 0
fi

# Derive installation properties
LDAP_DOMAIN=${1:-$(hostname -d)} # Use host's domain name if not provided
LDAP_PARTITION_ID=${2:-$(echo $LDAP_DOMAIN | sed 's/\..*//')} # First domain segment as partition ID
LDAP_PARTITION_SUFFIX="dc=${LDAP_DOMAIN/./,dc=}"
KERBEROS_REALM=$(echo $LDAP_DOMAIN | tr '[:lower:]' '[:upper:]') # upper case domain
SASL_HOST=$(hostname -f)
SASL_PRINCIPAL="ldap/$SASL_HOST@$KERBEROS_REALM"
SASL_REALM="$LDAP_DOMAIN"
APACHEDS_DIR="$(dirname "$0")/.."

echo "Setting up apacheds instance for host $(hostname -f) ($(ip -o -4 addr list eth0 | awk '{print $4}')) with:
  LDAP_DOMAIN=$LDAP_DOMAIN
  LDAP_PARTITION_ID=$LDAP_PARTITION_ID
  LDAP_PARTITION_SUFFIX=$LDAP_PARTITION_SUFFIX
  KERBEROS_REALM=$KERBEROS_REALM
  SASL_REALM=$SASL_REALM
  SASL_HOST=$SASL_HOST
  SASL_PRINCIPAL=$SASL_PRINCIPAL"

# Escape values for sed
SASL_PRINCIPAL="$(echo "$SASL_PRINCIPAL" | sed -E 's/[@\/]/\\\0/g')"

LDAP_PARTITION_CONTEXT_ENTRY=$(
echo "dn: $LDAP_PARTITION_SUFFIX
dc: $LDAP_PARTITION_ID
objectclass: domain
objectclass: top" | base64 | tr -d '\n'
)

sed -e "s/ads-partitionid: example/ads-partitionid: $LDAP_PARTITION_ID/" \
    -e "s/ads-partitionId=example/ads-partitionId=$LDAP_PARTITION_ID/" \
    -e "s/dc=example,dc=com/$LDAP_PARTITION_SUFFIX/" \
    -e "s/ads-contextentry:: .*/ads-contextentry:: $LDAP_PARTITION_CONTEXT_ENTRY/" \
\
    -e "s/ads-krbPrimaryRealm: .*/ads-krbPrimaryRealm: $KERBEROS_REALM/" \
\
    -e "s/ads-saslHost: .*/ads-saslHost: $SASL_HOST/" \
    -e "s/ads-saslPrincipal: .*/ads-saslPrincipal: $SASL_PRINCIPAL/" \
    -e "s/ads-saslRealms: .*/ads-saslRealms: $SASL_REALM/" \
    -e "/^ .*/d" \
    $APACHEDS_DIR/ldif/default-config.ldif | uniq > $APACHEDS_DIR/instances/default/conf/config.ldif

#-e "s/ads-systemport: 10389/ads-systemport: 389/" \
#    -e "s/ads-systemport: 10636/ads-systemport: 636/" \
