# Recipe to install mysql, setup ambari db on mysql

#Install mysql and java connector on master manager node

# Setup mysql
mysql_admin_user = $1
mysql_admin_pwd = $2
data_dir = $3
ambari_db = $4
ambari_user = $5
ambari_pwd = $6

    yum install mysql-connector-java-5.1.17-6.el6.noarch -y
    yum install mysql-server-5.1.73-3.el6_5.x86_64 -y 2> /dev/null
    if [ $? -eq 0 ]
    then
      echo "Installation succeeded when mysql version was specified." >> /tmp/msql.log
    else
      echo "Installation failed when mysql version was specified. Trying the non versioned install." >> /tmp/msql.log
      yum erase mysql* -y
      rm -rf /var/mysqldata
      rm -rf /var/lib/mysql
      yum install mysql-connector-java -y
      yum install mysql-server -y
    fi


sleep 2

echo "start and setup mysql instance." >> /tmp/msql.log  

    # start the service
    service mysqld start
    
    # set admin user's password
    /usr/bin/mysqladmin -u #{mysql_admin_user} password '#{mysql_admin_pwd}'
    
    # start mysql on boot
    chkconfig mysqld on 
    
    # change default data directory
    service mysqld stop
    cp -rap /var/lib/mysql #{data_dir}
    chown -R mysql:mysql #{data_dir}
    
    sed -i '1 a\max_allowed_packet=128M' /etc/my.cnf
    sed -i -e "s|datadir=.*|datadir=#{data_dir}|" -e "s|socket=.*|socket=#{data_dir}/mysql.sock|" "/etc/my.cnf"
    
    echo "[client]" >> "/etc/my.cnf"
    echo "socket=#{data_dir}/mysql.sock" >> "/etc/my.cnf"
    
    service mysqld start

sleep 2

echo "setup mysql admin user." >> /tmp/msql.log 
# Steps to secure initial MySQL accounts
# Reference: http://dev.mysql.com/doc/refman/5.1/en/default-privileges.html

# Update admin password for <admin>@hostname and <admin>@127.0.0.1

 mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"UPDATE mysql.user SET Password = PASSWORD('#{mysql_admin_pwd}') WHERE User = '#{mysql_admin_user}'\";
 mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"FLUSH PRIVILEGES\";

 mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"DROP USER ''@'localhost'\";
 mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"DROP USER ''@'#{mysql_host}'\";
 mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"FLUSH PRIVILEGES\";


#Remove access to test db

mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"DELETE FROM mysql.db WHERE Db LIKE 'test%'\";
mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"DROP DATABASE test\";
mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"FLUSH PRIVILEGES\";

echo "create and setup ambari db and user." >> /tmp/msql.log
#  Create ambari user and set privileges
    # Turn off globbing
    set -f
    
    # create user and grant privilege
    mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"CREATE USER '#{ambari_user}'@'%' IDENTIFIED BY '#{ambari_pwd}'\";
    mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"GRANT ALL PRIVILEGES ON *.* TO '#{ambari_user}'@'%'\";
    
    mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"CREATE USER '#{ambari_user}'@'localhost' IDENTIFIED BY '#{ambari_pwd}'\";
    mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"GRANT ALL PRIVILEGES ON *.* TO '#{ambari_user}'@'localhost'\";
    
    mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"CREATE USER '#{ambari_user}'@'#{mysql_host}' IDENTIFIED BY '#{ambari_pwd}'\";
    mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"GRANT ALL PRIVILEGES ON *.* TO '#{ambari_user}'@'#{mysql_host}'\";
    
    mysql -u #{mysql_admin_user} -p#{mysql_admin_pwd} -e \"FLUSH PRIVILEGES\";
    
    # Turn on globbing
    set +f


#create ambari database and run Ambari-DDL-MySQL-CREATE.sql
    mysql -u #{ambari_user} -p#{ambari_pwd} -e \"CREATE DATABASE #{ambari_db}\";
    mysql -u #{ambari_user} -p#{ambari_pwd} -e \"USE #{ambari_db}; SOURCE /var/lib/ambari-server/resources/Ambari-DDL-MySQL-CREATE.sql;\";

echo "Well Done!" >> /tmp/msql.log
