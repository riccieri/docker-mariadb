#!/bin/bash
# Starts up MariaDB within the container.

# Stop on error
set -e

USER=${USER:-super}
PASS=${PASS:-$(pwgen -s -1 16)}
DATA_DIR=/data
MYSQL_LOG=$DATA_DIR/mysql.log

# Echo out info to later obtain by running `docker logs container_name`
echo "MARIADB_USER=$USER"
echo "MARIADB_PASS=$PASS"
echo "MARIADB_DATA_DIR=$DATA_DIR"

# test if DATA_DIR has content
if [[ ! "$(ls -A $DATA_DIR)" ]]; then
    echo "Initializing MariaDB at $DATA_DIR"
    # Copy the data that we generated within the container to the empty DATA_DIR.
    cp -R /var/lib/mysql/* $DATA_DIR
fi

# Ensure mysql owns the DATA_DIR
chown -R mysql $DATA_DIR
chown root $DATA_DIR/debian*.flag

/usr/bin/mysqld_safe --skip-syslog --log-error=$MYSQL_LOG >> /dev/null &

# Wait for mysql to finish starting up first.
while [[ ! -e /run/mysqld/mysqld.sock ]] ; do
    inotifywait -q -e create /run/mysqld/ >> /dev/null
done

# The password for 'debian-sys-maint'@'localhost' is auto generated.
# The database inside of DATA_DIR may not have been generated with this password.
# So, we need to set this for our database to be portable.
DB_MAINT_PASS=$(cat /etc/mysql/debian.cnf | grep -m 1 "password\s*=\s*"| sed 's/^password\s*=\s*//')
mysql -u root -e \
    "GRANT ALL PRIVILEGES ON *.* TO 'debian-sys-maint'@'localhost' IDENTIFIED BY '$DB_MAINT_PASS';"

# Create the superuser.
mysql -u root -e "$(cat << EOF
    DELETE FROM mysql.user WHERE user = '$USER';
    FLUSH PRIVILEGES;
    CREATE USER '$USER'@'localhost' IDENTIFIED BY '$PASS';
    GRANT ALL PRIVILEGES ON *.* TO '$USER'@'localhost' WITH GRANT OPTION;
    CREATE USER '$USER'@'%' IDENTIFIED BY '$PASS';
    GRANT ALL PRIVILEGES ON *.* TO '$USER'@'%' WITH GRANT OPTION;
EOF
)"

PID=$(cat /run/mysqld/mysqld.pid)
kill $PID

# Wait until the process doesn't exists or becomes a zombie.
while [[ ( -d /proc/$PID ) && ( $(grep -c zombie /proc/$PID/status) -eq 0 ) ]]; do
    sleep 1
done

# Start MariaDB
echo "Starting MariaDB..."
/usr/bin/mysqld_safe --skip-syslog --log-error=$MYSQL_LOG
