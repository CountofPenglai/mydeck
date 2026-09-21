#!/bin/sh
# Bound writes in this diagnostic child only; never fill the user's filesystem.
ulimit -f 1 || exit 2
trap '' XFSZ
exec "$@"
