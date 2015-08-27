#!/bin/bash

source ./conf
source ./vars

installMariadb () 
{
    yum -y install mariadb mariadb-server MySQL-python

    cat > /etc/my.cnf.d/mariadb_openstack.cnf << EOF
[mysqld]
bind-address = $IPADDR
default-storage-engine = innodb
innodb_file_per_table
collation-server = utf8_general_ci
init-connect = 'SET NAMES utf8'
character-set-server = utf8
EOF

    systemctl enable mariadb.service
    systemctl start mariadb.service

    #mysql_secure_installation

	mysqladmin -u root password "$MARIA_PASS"
	mysql -u root -p"$MARIA_PASS" -e "UPDATE mysql.user SET Password=PASSWORD('$MARIA_PASS') WHERE User='root'"
	mysql -u root -p"$MARIA_PASS" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
	mysql -u root -p"$MARIA_PASS" -e "DELETE FROM mysql.user WHERE User=''"
	mysql -u root -p"$MARIA_PASS" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%'"
	mysql -u root -p"$MARIA_PASS" -e "FLUSH PRIVILEGES"
}

installRabbitmq () 
{
    yum -y install rabbitmq-server
    systemctl enable rabbitmq-server.service
    systemctl start rabbitmq-server.service

    rabbitmqctl add_user openstack $RABBIT_PASS
    rabbitmqctl set_permissions openstack ".*" ".*" ".*"
}

configureKeystone () 
{
	TOKEN=$(openssl rand -hex 10)
	sed -i.bak "/\[DEFAULT\]\$/a admin_token = $TOKEN" /etc/keystone/keystone.conf
	sed -i "/\[database\]\$/a connection = mysql:\/\/keystone:$KEYSTONE_DBPASS@controller\/keystone" /etc/keystone/keystone.conf
	sed -i "/\[memcache\]\$/a servers = localhost:11211" /etc/keystone/keystone.conf
	sed -i "/\[token\]\$/a driver = keystone.token.persistence.backends.memcache.Token" /etc/keystone/keystone.conf
	sed -i "/\[token\]\$/a provider = keystone.token.provider.uuid.Provider" /etc/keystone/keystone.conf
	sed -i "/\[revoke\]\$/a driver = keystone.contrib.revoke.backends.sql.Revoke" /etc/keystone/keystone.conf
	sed -i "/\[DEFAULT]\$/a verbose = True" /etc/keystone/keystone.conf

	su -s /bin/sh -c "keystone-manage db_sync" keystone

	# export the token so it can be used during the Apache configuration
	export OS_TOKEN=$TOKEN
	echo $TOKEN >> /root/token
}

installKeystone () 
{
    mysql -u root -p"$MARIA_PASS" -e "CREATE DATABASE keystone;"
    mysql -u root -p"$MARIA_PASS" -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';"
    mysql -u root -p"$MARIA_PASS" -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';"

	yum -y install openstack-keystone httpd mod_wsgi python-openstackclient memcached python-memcached

	systemctl enable memcached.service
	systemctl start memcached.service
}

configureApache () {
	sed -i.bak "/^ServerName/d" /etc/httpd/conf/httpd.conf
	sed -i "/^#ServerName/a ServerName $OS_SERVERNAME" /etc/httpd/conf/httpd.conf

	cat > /etc/httpd/conf.d/wsgi-keystone.conf << EOF
Listen 5000
Listen 35357

<VirtualHost *:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /var/www/cgi-bin/keystone/main
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    LogLevel info
    ErrorLogFormat "%{cu}t %M"
    ErrorLog /var/log/httpd/keystone-error.log
    CustomLog /var/log/httpd/keystone-access.log combined
</VirtualHost>

<VirtualHost *:35357>
    WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-admin
    WSGIScriptAlias / /var/www/cgi-bin/keystone/admin
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    LogLevel trace8
    ErrorLogFormat "%{cu}t %M"
    ErrorLog /var/log/httpd/keystone-error.log
    CustomLog /var/log/httpd/keystone-access.log combined
</VirtualHost>
EOF

	mkdir -p /var/www/cgi-bin/keystone
	curl http://git.openstack.org/cgit/openstack/keystone/plain/httpd/keystone.py?h=stable/kilo | tee /var/www/cgi-bin/keystone/main /var/www/cgi-bin/keystone/admin

	chown -R keystone:keystone /var/www/cgi-bin/keystone
	chmod 755 /var/www/cgi-bin/keystone/*

	systemctl enable httpd.service
	systemctl start httpd.service
}

createServiceEntityAndEndpoint () 
{
	export "OS_URL=http://$OS_SERVERNAME:35357/v2.0"

	openstack service create --name keystone --description "OpenStack Identity" identity

	openstack endpoint create --publicurl http://$OS_SERVERNAME:5000/v2.0 --internalurl http://$OS_SERVERNAME:5000/v2.0 --adminurl http://$OS_SERVERNAME:35357/v2.0 --region RegionOne identity
}



#yum -y install python-pip
#pip install uuid

yum -y upgrade
yum -y install openstack-selinux

installMariadb
installRabbitmq

installKeystone
configureKeystone

configureApache

#createServiceEntityAndEndpoint

