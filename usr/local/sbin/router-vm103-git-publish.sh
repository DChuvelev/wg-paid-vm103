#!/bin/sh
set -eu
exec env ROUTER_MACHINE_GIT_PROFILE=/etc/router-machine-git-source.conf /usr/local/sbin/router-machine-git-publish.sh "$@"
