#!/bin/bash
set -e

# if command starts with an option, prepend mysqld
if [ "${1:0:1}" = '-' ]; then
  CMDARG="$@"
fi

#get server_id from ip address
ipaddr=$(hostname -i | awk ' { print $1 } ')
server_id=$(echo $ipaddr | tr . '\n' | awk '{s = s + $1} END{print s}')

# perform slave routine
while : 
  do
    echo $ipaddr | nc ${MASTER_HOST} 4566

    if [ "$?" -eq 0 ]; then
      break
    fi
    
    echo "connection failed, trying again..."
done

DATADIR=/var/lib/mysql
cd $DATADIR
  
echo "Receiving stream ..."

nc -l -p 4565 | xbstream -x
innobackupex --apply-log --use-memory=1G ./
slavepass="$(pwmake 128)"
mysql -h${MASTER_HOST} -uroot -p${MYSQL_ROOT_PASSWORD} -e "GRANT REPLICATION SLAVE ON *.*  TO 'repl'@'$ipaddr' IDENTIFIED BY '$slavepass';"
chown -R mysql:mysql "$DATADIR"

# start slave 
echo "Starting slave..."
mysqld --user=mysql --server-id=$server_id --gtid-mode=ON --enforce-gtid-consistency --log-bin=/var/log/mysql/mysqlbinlog $CMDARG &
pid="$!"
  
echo "Started with PID $pid, waiting for initialization..."

for i in {300..0}; do
  mysql -uroot -p${MYSQL_ROOT_PASSWORD} -Bse "SELECT 1" mysql
    if [ "$?" -eq 0 ]; then
      break
    else
      echo 'MySQL init process in progress...'
      sleep 5
    fi	    
done

if [ "$i" = 0 ]; then
  echo >&2 'MySQL init process failed.'
  exit 1
fi

echo "Slave initialized, connecting to master..."
mysql -uroot -p${MYSQL_ROOT_PASSWORD} -e "CHANGE MASTER TO MASTER_HOST='${MASTER_HOST}', MASTER_USER='repl', MASTER_PASSWORD='$slavepass', MASTER_AUTO_POSITION = 1; START SLAVE;"
