#!/bin/sh
# Waits until a container has finished starting, so the first command you run in the dev container works.
# Gives up after START_LIMIT (e.g. 20m, 90s or 1m30s, set once in compose.yaml), so a broken startup is reported
# instead of being waited on forever. See "If the app won't start" in the README.
#
# Usage: wait-for-app.sh <service> <what> <command that succeeds once it's ready...>
service=$1 what=$2
shift 2
limit=${START_LIMIT:-10m}
seconds=0 rest=$limit
while [ -n "$rest" ]; do
  n=${rest%%[!0-9]*} && rest=${rest#"$n"}
  unit=${rest%%[0-9]*} && rest=${rest#"$unit"}
  [ -n "$n" ] || unit=none
  n=${n#"${n%%[!0]*}"} && n=${n:-0} # drop leading zeros, which shell arithmetic reads as octal
  case $unit in
    h) seconds=$((seconds + n * 3600)) ;;
    m) seconds=$((seconds + n * 60)) ;;
    s) seconds=$((seconds + n)) ;;
    # Including none, as compose.yaml also reads it as a duration, which needs units
    *)
      echo "Can't read START_LIMIT=$limit: use whole hours, minutes and seconds, such as 1h, 20m or 1m30s" >&2
      exit 1
      ;;
  esac
done
deadline=$(($(date +%s) + seconds))
until "$@" >/dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "Gave up waiting for $what after $limit: see make logs SERVICE=$service, and \"If the app won't start\" in the README" >&2
    exit 1
  fi
  echo "Waiting for $what (rechecking in 5 seconds, will give up after $limit), see make logs SERVICE=$service"
  sleep 5
done
