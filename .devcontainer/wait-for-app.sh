#!/bin/sh
# Waits until a container has finished starting, so the first command you run in the dev container works.
# Gives up after START_LIMIT (e.g. 1h, 20m or 90s, set once in compose.yaml), so a broken startup is reported instead of
# being waited on forever. See "If the app won't start" in the README.
#
# Usage: wait-for-app.sh <service> <what> <command that succeeds once it's ready...>
service=$1 what=$2
shift 2
limit=${START_LIMIT:-10m}
# Compose reads it too, as a duration, which needs a unit
case $limit in
  *h) seconds=$((${limit%h} * 3600)) ;;
  *m) seconds=$((${limit%m} * 60)) ;;
  *s) seconds=${limit%s} ;;
  *) echo "START_LIMIT must be a number of hours, minutes or seconds, such as 1h, 20m or 90s, not $limit" >&2; exit 1 ;;
esac
deadline=$(($(date +%s) + seconds))
until "$@" >/dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "Gave up waiting for $what after $limit: see make logs SERVICE=$service, and \"If the app won't start\" in the README" >&2
    exit 1
  fi
  echo "Waiting for $what (rechecking in 5 seconds, will give up after $limit), see make logs SERVICE=$service"
  sleep 5
done
