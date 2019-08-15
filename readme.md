Dockerized-wordpress-backup
===========================
 
This image can be used to automatically create [MariaDB](https://mariadb.org/) dumps using [`mysqldump`](https://mariadb.com/kb/en/library/mysqldump/) client and Wordpress files backup within a Docker environment. The backups are created periodically (hourly, daily, weekly, and/or monthly) with a cron job and then kept on an SFTP destination with a defined retention count. Optionally, a notification can be sent on [Slack](https://slack.com/) after a backup has finished.

The reason why we explicitly use SFTP for uploading (and **not** SCP, which would make things much easier): This tool is intended to work with Hetzner’s [Storage Box](https://www.hetzner.de/storage/storage-box) to keep the dumps, and those do [apparently](https://wiki.hetzner.de/index.php/Storage_Boxes/en) not (fully) support shell access.

Usage
-----

There are the following configuration options which need to be specified using environment variables:

### General Settings

* `MYSQL_HOST` -- MariabDB Host name for creating dump

* `MYSQL_PORT` (optional) -- Define port for MariaDB host (defaults to `3306`)

* `MYSQL_DATABASE` -- specify the name of a database

* `MYSQL_USER` -- specify the user of the database

* `MYSQL_PASSWORD` -- specify the user's password

* `KEEP_HOURLY` (optional) -- Set to a value greater one to perform hourly backups. The number specifies how many recent backups should be kept, e.g. for `KEEP_HOURLY=24`, the 24 most recent backups for every hour are kept, older ones will be cleaned after a new successful backup run. Hourly backups are created at the beginning of every hour. Leave empty to perform **no** hourly backups.

* `KEEP_DAILY` (optional) -- ditto, but for daily backups. Daily backups are created every night at 1:00 AM.

* `KEEP_WEEKLY` (optional) -- ditto, but for weekly backups. Weekly backups are created every Sunday at  1:00 AM.

* `KEEP_MONTHLY` (optional) -- ditto, but for monthly backups. Monthly backups are created on the first day of every month at 1:00 AM.

Beside that, it makes sense to set explicitly set the time zone. Elsewise, UTC will be used inside the container:

* `TZ` -- Set to the correct local time zone, e.g. `Europe/Berlin` (see [here](https://github.com/moby/moby/issues/12084#issuecomment-160177087) for some background). **This is important,** because (a) cron uses local times and (b) you probably want meaningful timestamps on the dump files!

### SFTP Settings

Uploading the dumps via SFTP, the following configuration is necessary:

* `DESTINATION_SFTP_HOST` -- SFTP host to where to copy dumps

* `DESTINATION_SFTP_USER` -- SFTP user name

* `DESTINATION_SFTP_PORT` (optional) -- SFTP port (defaults to `22` if not explicitly specified; on Hetzner use port `23`)

* `DESTINATION_SFTP_PATH` (optional) -- Directory on the host were to copy dumps (**no** leading `/` on Hetzner’s environment)


To allow establishing an SFTP connection without any prompts for fingerprints and/or passwords, perform the following steps:

1. Create a new directory, called e.g. `ssh`, which will contain the following files.

    ```
    $ mkdir ssh
    ```

2. Create a `./ssh/known_hosts` file for the server (**note:** port `23` is [Hetzner-specific](https://wiki.hetzner.de/index.php/Backup_Space_SSH_Keys/en#SSH_key_authentification_for_backup_spaces_und_storage_boxes)):

    ```
    $ ssh-keyscan -p 23 -H backup.example.com > ./ssh/known_hosts
    ```

    We only create an entry for the hostname, and **not** the IP address, because according to Hetzner, the IP addresses of the Storage Boxes might change:

    > It is very important to use the DNS name (<username>.your-storagebox.de) instead of the IP address for your Storage Box; this is because the IP address can change. With the DNS address, you can  access your Storage Box via IPv4 and IPv6.

    This produces the following message when executing `sftp`:

    > ED25519 host key for IP address 'xxx.xxx.xxx.xxx' not in list of known hosts.

    As this is only a warning, it doesn’t affect execution. To supress it, we could pass the option `-oCheckHostIP=no` to `sftp`, but I don’t feel like hard-coding security-weakening options.

3. Create an SSH key pair (see Hetzner’s instructions [here](https://wiki.hetzner.de/index.php/Backup_Space_SSH_Keys/en)):

    ```
    $ ssh-keygen -f ./ssh/id_rsa
    ```

    Add the public key `id_rsa.pub` to the destination server by adding it to `~/.ssh/authorized_keys`.

4. Mount the `ssh` directory with the files `known_hosts` and `id_rsa` to `/root/.ssh` into the container.

### Slack Settings

Slack notifications are optional. To use them, you’ll need to add the [“Incoming Webhooks”](https://api.slack.com/incoming-webhooks) to your slack channel, and then configure the corresponding Webhook URL:

* `NOTIFICATION_SLACK_WEBHOOK_URL` (optional) -- URL for the Slack Webhook to send success/error notifications.

* `NOTIFICATION_SLACK_USERNAME` (optional) -- Set this to specify the username.

Example
-------

For a minimal, complete example configuration using Docker Compose have a look at the included [`docker-compose.yml`](docker-compose.yml) file. 

Builds, (re)creates, starts, and attaches to containers as follow:

```
$ docker-compose up 
```

### Windows peculiarities

* Use [`Windows Subsystem For Linux:`](https://docs.microsoft.com/en-us/windows/wsl/about) The Windows Subsystem for Linux lets developers run a GNU/Linux environment -- including most command-line tools, utilities, and applications -- directly on Windows, unmodified, without the overhead of a virtual machine. This provides 100% compatibility with Ubuntu for debugging and running Bash scripts.


* Windows and Linux implement the permissions in different ways. Resulting the following error on Windows:

    ```
    Permissions 0777 for '/Users/username/.ssh/id_rsa' are too open.
    It is recommended that your private key files are NOT accessible by others.
    This private key will be ignored.
    ```

* Use additional [`docker-compose.windows.yml`](docker-compose.windows.yml) file which creates a container with key `ssh_key` and shares the key using volume with `backup` container.

    ```
    $ docker-compose -f docker-compose.yml -f docker-compose.windows.yml up
    ```
