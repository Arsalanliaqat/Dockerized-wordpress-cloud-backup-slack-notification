#!/bin/bash

while getopts ":k:l:" opt; do
  case $opt in
    k) KEEP="$OPTARG"
    ;;
    l) LABEL="$OPTARG"
    ;;
    \?)
    echo "Invalid option -$OPTARG" >&2
    exit 1
    ;;
  esac
done

echo "====================================================================================================================================="
echo "--- Starting $LABEL Wordpress backup to ${DESTINATION_SFTP_HOST}:${DESTINATION_SFTP_PATH} at $(date) ---"

TEMP_DIR=$(mktemp --directory dump.XXXXXXXXXX)
HTML_DIR="/var/www/html"
TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")
SQL_FILE="${TEMP_DIR}/db_${TIMESTAMP}.sql"
SQL_GZ_FILE="${SQL_FILE}.gz"
HTML_FILE="${TEMP_DIR}/html_${TIMESTAMP}.tar.gz"

function cleanup {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

function fail_on_error {
  EXIT_STATUS=$?
  if [ "$EXIT_STATUS" -ne 0 ]; then
    ERROR_MESSAGE="$1 (status $EXIT_STATUS)"
    echo "--- ERROR: $ERROR_MESSAGE ---" >&2
    send_slack_notification "ERROR" "$ERROR_MESSAGE"
    exit 1
  fi
}

function send_slack_notification {
  COLOR="good"
  if [ "$1" = "ERROR" ]; then
    COLOR="danger"
  fi
  if [ ! -z "$NOTIFICATION_SLACK_WEBHOOK_URL" ]; then
    curl -s -X POST -H 'Content-type: application/json' \
      --data "{\"username\":\"$NOTIFICATION_SLACK_USERNAME\",\"attachments\":[{\"color\":\"$COLOR\",\"title\":\"$1\",\"text\":\"$2\"}],\"icon_emoji\":\":construction_worker:\"}" \
      --output /dev/null \
      "$NOTIFICATION_SLACK_WEBHOOK_URL" || true
      # ignore potential notification failures
  fi
}

# echo "--- CREATING MYSQL DUMP ---"
# https://wordpress.org/support/article/backing-up-your-database/#using-straight-mysqlmariadb-commands
mysqldump --add-drop-table --user=$MYSQL_USER --password=$MYSQL_PASSWORD --host=$MYSQL_HOST wordpress > ${SQL_FILE}
fail_on_error "Failed to Create DB Dump"

# echo "--- COMPRESSING MYSQL DUMP ---"
gzip --best ${SQL_FILE}
fail_on_error "Failed to gzip DB Dump"

echo "--- MariaDB Dump Created Successfully ---"

# echo "--- CREATING WORDPRESS BACKUP ---"
tar -zcf "${HTML_FILE}" -C ${HTML_DIR} .
fail_on_error "Failed to Wordpress Backup"
echo "--- Wordpress Backup Created Successfully ---"

echo "--- Wordpress Backup created -- uploading via SFTP to ${DESTINATION_SFTP_HOST}:${DESTINATION_SFTP_PATH} now ---"
# build an SFTP batch
SFTP_BATCH=()

# cd into the destination
SFTP_BATCH+=("cd $DESTINATION_SFTP_PATH")

# rotation logic
# some of the following commands are prefixed with a `-`;
# this way, a failing command (file does not exist)
# will keep the script running (hopefully)
###################################################

# temporarily append `.0` to newest 
# (`daily` becomes `daily.0`)
SFTP_BATCH+=("-rename $LABEL $LABEL.0")

# create new snapshot directory and put dump
SFTP_BATCH+=("mkdir $LABEL")
SFTP_BATCH+=("cd $LABEL")
SFTP_BATCH+=("put $SQL_GZ_FILE")
SFTP_BATCH+=("put ${HTML_FILE}")
SFTP_BATCH+=("cd ..")

# delete oldest snapshot
SFTP_BATCH+=("-rm $LABEL.$(($KEEP-1))/*")
SFTP_BATCH+=("-rmdir $LABEL.$(($KEEP-1))")

# rotate snapshots
for (( i=$(($KEEP-1)); i>0; i-- )); do
  # e.g. 'daily.6' becomes 'daily.7'
  SFTP_BATCH+=("-rename $LABEL.$((i-1)) $LABEL.$((i))")
done

# here we go
SFTP_BATCH=$(IFS=$'\n' ; echo "${SFTP_BATCH[*]}")
echo "$SFTP_BATCH" | sftp -oPort="${DESTINATION_SFTP_PORT}" -b - "${DESTINATION_SFTP_USER}@${DESTINATION_SFTP_HOST}"
fail_on_error "sftp failed"

# send success Slack notification for wordpress backup
SUCCESS_MESSAGE="Finished $LABEL Wordpress backup to ${DESTINATION_SFTP_HOST}:${DESTINATION_SFTP_PATH} at $(date)."
send_slack_notification "SUCCESS" "$SUCCESS_MESSAGE"
echo "--- $SUCCESS_MESSAGE --- "
