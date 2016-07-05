#!/bin/sh

for DIR in $(find $(dirname $0) -name Makefile -print0 | xargs -0); do
	(
		cd "$(dirname $DIR)" &&
		make || exit 1
	)
done
