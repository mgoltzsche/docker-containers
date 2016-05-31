#!/bin/sh

case "$1" in
		dump)
			ERROR=0
			chmod -R 770 $BACKUP_TMP_DIR &&
			chown -R root:dirsrv $BACKUP_TMP_DIR &&
			for DIR in $(find /etc/dirsrv/ -mindepth 1 -maxdepth 1 -type d -name "slapd-*" | xargs -n 1 basename); do
				for DB_NAME in $(find /var/lib/dirsrv/$DIR/db/ -mindepth 1 -maxdepth 1 -type d | xargs -n 1 basename); do
					ns-slapd db2ldif -D /etc/dirsrv/$DIR -n $DB_NAME -a $BACKUP_TMP_DIR/$(echo $DIR | sed -e 's/slapd-//g')-$DB_NAME.ldif >/dev/null || ERROR=$?
					done
			done
			exit $ERROR
		;;
		restore)
			ERROR=0
			for LDIF in $(ls $BACKUP_TMP_DIR | grep -P '^.*\.ldif$'); do
				NAMES=$(echo $LDIF | sed -e 's/\.ldif$//g')
				INSTANCE_NAME=$(echo $NAMES | cut -d - -f 1)
				DB_NAME=$(echo $NAMES | cut -d - -f 2)
				ns-slapd ldif2db -D /etc/dirsrv/slapd-$INSTANCE_NAME -n $DB_NAME -i $BACKUP_TMP_DIR/$LDIF || ERROR=$?
			done
			exit $ERROR
		;;
		*)
			echo "Usage: $0 {dump|restore}" >&2
			exit 1
		;;
esac
