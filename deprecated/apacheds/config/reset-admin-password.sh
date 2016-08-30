#!/bin/sh

if [[ "$(id -u)" -ne 0 ]]; then
   echo "Only root can reset directory admin password" 1>&2
   exit 1
fi

NEWADSPW=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32)

touch /etc/apachedspw &&
chmod 600 /etc/apachedspw &&
echo "dn: uid=admin,ou=system
changetype: modify
replace: userPassword
userPassword: $NEWADSPW" |
ldapmodify -x -h localhost -p 10389 -D uid=admin,ou=system -w $(cat /etc/apachedspw) &&
echo -n "$NEWADSPW" > /etc/apachedspw &&
chmod 400 /etc/apachedspw
