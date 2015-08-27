#!/bin/bash

##########################
######################
# openstack-prereq.sh
# Post OS install, this will do pre-requisite set-up for installing DevStack
#
# Marcus Spain
# marcus_spain@cable.comcast.com
#################

set -x  #echo on

source ./conf
source ./vars

# Install net-tools and git
# Net-Tools supplies the ifconfig command.
# We'll need git to pull down the DevStack repo
yum -y install net-tools git

# Without this line, you'll get a Peer Certificate error when attempting to
# clone repos via HTTPS.
git config --global http.sslVerify false

# Remove any existing IPChains
# We may want to implement our on rules in the future.
# The default CentOS 7 rules will block incoming HTTP.
if [ $OS == 'centos7' ]
    then
        # SECURITY
        systemctl stop iptables
        systemctl disable iptables
        systemctl stop firewalld
        systemctl disable firewalld

        # HOSTNAME
        hostnamectl set-hostname $HOSTNAME

    else
        # SECURITY
        mv /etc/sysconfig/iptables /etc/sysconfig/iptables.orig
        service iptables restart
        iptables -F

        # HOSTNAME
        hostname $HOSTNAME

fi

# Update the HOSTNAME
echo HOSTNAME=$HOSTNAME >> /etc/sysconfig/network

# Update the DOMAINNAME
echo kernel.domainname=sys.comcast.net >> /etc/sysctl.conf

# Update the HOSTS file
cat > /etc/hosts << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4 $HOSTNAME.$DOMAIN $HOSTNAME
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

#165.137.32.181  os-pi-01.sys.comcast.net    os-pi-01
#165.137.32.56   os-pi-02.sys.comcast.net    os-pi-02

192.168.0.119   os-pi-01.sys.comcast.net    os-pi-01    os1
192.168.0.118   os-pi-02.sys.comcast.net    os-pi-02    os2
10.31.50.143    os-pi-01.sys.comcast.net    os-pi-03    os3
165.137.32.119  os-pi-02.sys.comcast.net    os-pi-04    os4

192.168.42.11   oscontroller    os-pi-01
192.168.42.12   oscompute0      os-pi-02
192.168.42.13   oscompute1      os-pi-03
192.168.42.14   oscompute2      os-pi-04
EOF

# Adding the stack user.  This is the user that will install DevStack.
groupadd stack
useradd -g stack -s /bin/bash -d /opt/stack -m stack
echo "stack ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Disable SELinux
# This will require a reboot.
sed -i.bak 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

sed -i 's/BOOTPROTO=dhcp/BOOTPROTO=static/g' /etc/sysconfig/network-scripts/ifcfg-$IF
sed -i 's/DEFROUTE=yes/DEFROUTE=no/g' /etc/sysconfig/network-scripts/ifcfg-$IF
sed -i 's/PEERDNS=yes/PEERDNS=no/g' /etc/sysconfig/network-scripts/ifcfg-$IF
sed -i 's/PEERROUTES=yes/PEERROUTES=no/g' /etc/sysconfig/network-scripts/ifcfg-$IF
sed -i 's/ONBOOT=no/ONBOOT=yes/g' /etc/sysconfig/network-scripts/ifcfg-$IF
echo IPADDR=$IPADDR >> /etc/sysconfig/network-scripts/ifcfg-$IF
echo NETMASK=255.255.255.0 >> /etc/sysconfig/network-scripts/ifcfg-$IF

# Add my ssh key
mkdir ~/.ssh
echo ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQC74qsK4yNWs4Ah9TmijFgEG1kF0+Gw5/qZQtK06bCClQAKIVy26Wz6KuvyJ1KmZYyVGdKfO117Mk4TYbDBubWLsl42ciUZuTWoienwLIuNZ0BaglqkX22ywBEZ+x9cFZW4X5tp1UNEglbPRNWbzFTsVxl9LQa9Yk7EkAXHk2KZhQ== mspain >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh/
chmod 600 ~/.ssh/authorized_keys

# Add aliases
echo "alias nn='netstat -an | grep LISTEN | grep tcp'" >> /etc/profile.d/aliases.sh
echo "alias na='netstat -an'" >> /etc/profile.d/aliases.sh

# Install NTP
yum -y install ntp
systemctl enable ntpd.service
systemctl start ntpd.service

# Enable EPEL
yum -y install epel-release
yum -y install http://rdo.fedorapeople.org/openstack-kilo/rdo-release-kilo.rpm



if [ $PROJECT == 'DevStack' ]
then
	cd /opt/stack
	git clone https://git.openstack.org/openstack-dev/devstack
	sleep 2

	cd /opt/stack/devstack
	if [ $NODETYPE == 'controller' ]
	then
    	cat > local.conf << EOF
[[local|localrc]]
HOST_IP=$IPADDR
FLAT_INTERFACE=eno2
FIXED_RANGE=10.4.128.0/20
FIXED_NETWORK_SIZE=4096
FLOATING_RANGE=192.168.42.128/25
MULTI_HOST=1
LOGFILE=/opt/stack/logs/stack.sh.log
ADMIN_PASSWORD=labstack
MYSQL_PASSWORD=supersecret
RABBIT_PASSWORD=supersecrete
SERVICE_PASSWORD=supersecrete
SERVICE_TOKEN=xyzpdqlazydog
EOF

	elif [ $NODETYPE == 'compute' ]
	then
    	cat > local.conf << EOF
[[local|localrc]]
HOST_IP=$IPADDR
FLAT_INTERFACE=$IF
FIXED_RANGE=10.4.128.0/20
FIXED_NETWORK_SIZE=4096
FLOATING_RANGE=192.168.42.128/25
MULTI_HOST=1
LOGFILE=/opt/stack/logs/stack.sh.log
ADMIN_PASSWORD=labstack
MYSQL_PASSWORD=supersecret
RABBIT_PASSWORD=supersecrete
SERVICE_PASSWORD=supersecrete
SERVICE_TOKEN=xyzpdqlazydog
DATABASE_TYPE=mysql
SERVICE_HOST=$CONTROLLERIP
MYSQL_HOST=\$SERVICE_HOST
RABBIT_HOST=\$SERVICE_HOST
GLANCE_HOSTPORT=\$SERVICE_HOST:9292
ENABLED_SERVICES=n-cpu,n-net,n-api-meta,c-vol
NOVA_VNC_ENABLED=True
NOVNCPROXY_URL="http://\$SERVICE_HOST:6080/vnc_auto.html"
VNCSERVER_LISTEN=\$HOST_IP
VNCSERVER_PROXYCLIENT_ADDRESS=\$VNCSERVER_LISTEN
EOF

	fi

	sed -i.bak 's/git:/http:/g' stackrc
	
	cd /opt/stack
	chown -R stack:stack *

#elif [ $PROJECT == 'OpenStack' ]
#then
fi

echo Done!
echo Kindly reboot.

