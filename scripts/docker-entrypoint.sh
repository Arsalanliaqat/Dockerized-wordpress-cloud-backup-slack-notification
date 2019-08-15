#!/bin/bash

set -e
if [ -z "$MYSQL_HOST" ]; then
  echo 'Please specify MariaDB $MYSQL_HOST via environment variable' >&2
  exit 1
fi
if [ -z "$MYSQL_DATABASE" ]; then
  echo 'Please specify MariaDB $MYSQL_DATABASE via environment variable' >&2
  exit 1
fi
if [ -z "$MYSQL_USER" ]; then
  echo 'Please specify MariaDB $MYSQL_USER via environment variable' >&2
  exit 1
fi
if [ -z "$MYSQL_PASSWORD" ]; then
  echo 'Please specify MariaDB $MYSQL_PASSWORD via environment variable' >&2
  exit 1
fi
if [ -z "$DESTINATION_SFTP_HOST" ]; then
  echo 'Please specify SFTP host $DESTINATION_SFTP_HOST via environment variable' >&2
  exit 1
fi
if [ -z "$DESTINATION_SFTP_USER" ]; then
  echo 'Please specify SFTP user $DESTINATION_SFTP_USER via environment variable' >&2
  exit 1
fi
if [ -z "$DESTINATION_SFTP_PATH" ]; then
  echo 'Please specify SFTP path $DESTINATION_SFTP_PATH via environment variable' >&2
  exit 1
fi

# regular expression to validate for positive numbers
pos_num_re="^[1-9][0-9]*$"

if [ ! -z "$DESTINATION_SFTP_PORT" ] &&  ! [[ "$DESTINATION_SFTP_PORT" =~ $pos_num_re ]]; then
  echo 'If specified, $DESTINATION_SFTP_PORT must be a positive integer number' >&2
  exit 1
fi

for KEEP_SETTING in KEEP_HOURLY KEEP_DAILY KEEP_WEEKLY KEEP_MONTHLY; do
  # ! in ${!KEEP_SETTING} to expand into value
  if [ ! -z ${!KEEP_SETTING} ] && ! [[ ${!KEEP_SETTING} =~ $pos_num_re ]]; then
    echo "If specified, $KEEP_SETTING must be a positive integer number" >&2
    exit 1
  fi
done

# default MySQL port
MYSQL_PORT="${MYSQL_PORT:-3306}"

# dynamically write the crontab file; add environment variables
# nb: avoid adding empty variables, such as FOO=, b/c this
# seems to confuse cron’s parser?
CRONTAB="/etc/cron.d/backup"

echo "MYSQL_HOST=$MYSQL_HOST" > $CRONTAB
echo "MYSQL_PORT=$MYSQL_PORT" >> $CRONTAB
echo "MYSQL_DATABASE=$MYSQL_DATABASE" >> $CRONTAB
echo "MYSQL_USER=$MYSQL_USER" >> $CRONTAB
echo "MYSQL_PASSWORD=$MYSQL_PASSWORD" >> $CRONTAB
# echo "MARIA_DUMP_TIMEOUT=$MARIA_DUMP_TIMEOUT" >> $CRONTAB
if [ ! -z "$TZ" ]; then
  echo "TZ=$TZ" >> $CRONTAB
fi
echo "DESTINATION_SFTP_HOST=$DESTINATION_SFTP_HOST" >> $CRONTAB
echo "DESTINATION_SFTP_PORT=$DESTINATION_SFTP_PORT" >> $CRONTAB
echo "DESTINATION_SFTP_USER=$DESTINATION_SFTP_USER" >> $CRONTAB
echo "DESTINATION_SFTP_PATH=$DESTINATION_SFTP_PATH" >> $CRONTAB
if [ ! -z "$NOTIFICATION_SLACK_WEBHOOK_URL" ]; then
  echo "NOTIFICATION_SLACK_WEBHOOK_URL=$NOTIFICATION_SLACK_WEBHOOK_URL" >> $CRONTAB
fi
if [ ! -z "$NOTIFICATION_SLACK_USERNAME" ]; then
  echo "NOTIFICATION_SLACK_USERNAME=$NOTIFICATION_SLACK_USERNAME" >> $CRONTAB
fi

if [ ! -z "$KEEP_HOURLY" ]; then
  #     +---------------- minute (0 - 59)
  #     |  +------------- hour (0 - 23) 
  #     |  |  +---------- day of month (1 - 31)
  #     |  |  |  +------- month (1 - 12)
  #     |  |  |  |  +---- day of week (0 - 6) (Sunday=0 or 7)
  #     |  |  |  |  |
  echo "0  *  *  *  * root /usr/local/bin/backup.sh -k $KEEP_HOURLY -l hourly > /proc/1/fd/1 2>/proc/1/fd/2" >> $CRONTAB
fi

if [ ! -z "$KEEP_DAILY" ]; then
  echo "0  1  *  *  * root /usr/local/bin/backup.sh -k $KEEP_DAILY -l daily > /proc/1/fd/1 2>/proc/1/fd/2" >> $CRONTAB
fi

if [ ! -z "$KEEP_WEEKLY" ]; then
  echo "0  1  *  *  0 root /usr/local/bin/backup.sh -k $KEEP_WEEKLY -l weekly > /proc/1/fd/1 2>/proc/1/fd/2" >> $CRONTAB
fi

if [ ! -z "$KEEP_MONTHLY" ]; then
  echo "0  1  1  *  * root /usr/local/bin/backup.sh -k $KEEP_MONTHLY -l monthly > /proc/1/fd/1 2>/proc/1/fd/2" >> $CRONTAB
fi

# this is undocumented and only here for debugging
if [ ! -z "$KEEP_MINUTELY" ]; then
  echo "*  *  *  *  * root /usr/local/bin/backup.sh   -k $KEEP_MINUTELY -l minutely > /proc/1/fd/1 2>/proc/1/fd/2" >> $CRONTAB
fi

chmod 0644 $CRONTAB

cat $CRONTAB

# run cron in foreground mode
cron -f
