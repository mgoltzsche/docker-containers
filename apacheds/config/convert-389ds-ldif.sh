#!/bin/sh

LDIF="$1"
grep -Evi "^(nsUniqueId:|aci:|passwordGraceUserTime:|objectClass: mailRecipient$|objectClass: applicationProcess$)" "$LDIF" | sed -E 's/^mailAlternateAddress: (.*)/mail: \1/gi' | sed -E 's/^mailForwardingAddress: (.*)/l: \1/gi'

# ATTENTION: applicationProcess and javaContainer objectClasses have been replaced manually with inetOrgPerson in the 389ds system to have the mail attribute availble in apacheds
