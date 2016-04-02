hosts = #{HOST}:#{PORT}
dn = #{USER_DN}
dnpass = #{PASSWORD}
tls = no
auth_bind = yes
base = #{SEARCH_BASE}
user_attrs = =mail=maildir:/var/vmail/%d/%n/
user_filter = (&(objectClass=inetOrgPerson)(mail=%u))
pass_attrs = 
pass_filter = (&(objectClass=inetOrgPerson)(mail=%u))
scope = subtree
ldap_version = 3
