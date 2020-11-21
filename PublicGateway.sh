#!/bin/bash
#
# Setup Gateway with Public/Private Interface in a cluster
# for CentOs or RedHat version 7.0
# Usage:
#   To set up gateway: ./PublicGateway.sh -g -u xxx -r yyy
#   To set up client:  ./PublicGateway.sh -c -u xxx -r yyy -m zzz
# for RedHat 7.x by Zilin @2016.01
#

PUBLIC_INTERFACE="eth1"
PRIVATE_INTERFACE="eth0"
MASTER_PRIVATE_IP=""
LOG_FILE="/var/log/gateway/PublicGateway.log"
LOG_HISTORY_FILE="/var/log/gateway/PublicGateway_history.log"
set_up_gateway()
{
  echo "enable iptables" >>$LOG_FILE
  systemctl mask firewalld
  systemctl stop firewalld
  yum -y localinstall /tmp/iptables-services-1.4.21-13.el7.x86_64.rpm >> $LOG_FILE
  yum -y localinstall /tmp/net-tools-2.0-0.17.20131004git.el7.x86_64.rpm
  systemctl enable iptables
  systemctl start iptables >> $LOG_FILE

  echo "Setting up Gateway " >> $LOG_FILE
  echo "Detected Public Interface $PUBLIC_INTERFACE" >> $LOG_FILE
  echo "Detected Private Interface $PRIVATE_INTERFACE" >> $LOG_FILE
  iptables -I FORWARD 1 -i $PUBLIC_INTERFACE -j ACCEPT
  iptables -I FORWARD 1 -o $PRIVATE_INTERFACE -j ACCEPT
  yes | cp -rf /etc/sysctl.conf /etc/sysctl.conf.$NOW.$CURTIME.backup
  sed -i -e "s@\(net.ipv4.ip_forward\) .*@\1 = 1@" /etc/sysctl.conf
  iptables -t nat -A POSTROUTING -o $PRIVATE_INTERFACE -j MASQUERADE >> $LOG_FILE
  iptables -t nat -A POSTROUTING -o $PUBLIC_INTERFACE -j MASQUERADE >> $LOG_FILE
  sed --in-place '/REJECT/d' /etc/sysconfig/iptables
  service iptables save >> $LOG_FILE
  systemctl restart  iptables.service
  
  #enable ip forwarding
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
  echo "net.ipv4.ip_nonlocal_bind = 1" >> /etc/sysctl.conf
  /usr/sbin/sysctl net.ipv4.ip_forward >> $LOG_FILE
  
  #service network restart >> $LOG_FILE
  systemctl restart network >> $LOG_FILE
  echo "Sleeping 60 seconds" >> $LOG_FILE
  
  lineno=$(iptables -L FORWARD --line-numbers | grep REJECT | cut -d' ' -f1)
  echo "Foeward reject at $lineno" >> $LOG_FILE
  if [ "X$lineno" != "X" ]; then
    echo "exec iptables -D FORWARD $lineno" >> $LOG_FILE    
    iptables -D FORWARD $lineno
    lineno2=$(iptables -L INPUT --line-numbers | grep REJECT | cut -d' ' -f1)
    if [ "X$lineno2" != "X" ]; then
      iptables -D INPUT $lineno2
    fi
    service iptables save >> $LOG_FILE
    systemctl restart  iptables.service
  fi
  
  sleep 60
  echo "Completed setting up gateway" >> $LOG_FILE
}

set_up_client()
{
  echo "enable iptables" >>$LOG_FILE
  systemctl mask firewalld
  systemctl stop firewalld
  yum -y localinstall /tmp/iptables-services-1.4.21-13.el7.x86_64.rpm >> $LOG_FILE
  yum -y localinstall /tmp/net-tools-2.0-0.17.20131004git.el7.x86_64.rpm
  systemctl enable iptables
  systemctl start iptables >> $LOG_FILE
 
  echo "Setting up Client " >> $LOG_FILE 
  if [[ -z "$MASTER_PRIVATE_IP" ]];then
  	MASTER_PRIVATE_IP=$(cat /etc/hosts | grep mastermanager | awk '{ print $1 }')
  fi
  echo "Master Private IP for gateway: $MASTER_PRIVATE_IP " >> $LOG_FILE 
  MOD_FILE=/etc/sysconfig/network-scripts/ifcfg-$PRIVATE_INTERFACE
  yes | cp -rf $MOD_FILE $MOD_FILE.$NOW.$CURTIME.backup
  TEMP=$(grep "^GATEWAY=" $MOD_FILE)
  if [[ -z $TEMP ]]; then
     echo "GATEWAY=$MASTER_PRIVATE_IP" >> $MOD_FILE
  else
     sed -i -e "s@\(GATEWAY=\).*@\1$MASTER_PRIVATE_IP@" $MOD_FILE
  fi
  
  # get ipaddr
  IP_ADDRESS=$(ip addr show $PRIVATE_INTERFACE | awk '$1 == "inet" {print $2}' | sed 's/\.[0-9]*$/.1/')
  echo "IP Address: $IP_ADDRESS" >> $LOG_FILE
  # get subnet id
  SUBNET_ID_CAL=$(/bin/ipcalc -n $IP_ADDRESS | cut -d '=' -f 2)
  echo "SUBNET_ID_CAL: $SUBNET_ID_CAL" >> $LOG_FILE
  
  # Returns the integer representation of sub net id as (x.x.x.x)
  IPNUM=0
  for (( i=0 ; i<4 ; ++i )); do
    ((IPNUM+=${SUBNET_ID_CAL%%.*}*$((256**$((3-${i}))))))
    SUBNET_ID_CAL=${SUBNET_ID_CAL#*.}
  done
  
  # add +1 to get the host minimun range
  IPNUM=$(($IPNUM + 1))
  echo "Integer: $IPNUM" >> $LOG_FILE

  # returns the dotted-decimal ascii form of integer format
  hostmin1=$(($(($(($(($IPNUM/256))/256))/256))%256)).
  hostmin2=$(($(($(($IPNUM/256))/256))%256)).
  hostmin3=$(($(($IPNUM/256))%256)).
  hostmin4=$(($IPNUM%256))
  HOSTMIN="$hostmin1$hostmin2$hostmin3$hostmin4"
  echo "HOSTMIN: $HOSTMIN" >> $LOG_FILE
  
  # ip route add {NETWORK} via {IP} dev {DEVICE}
  # Make sure node communicates with other nodes through the router, not the gateway.
  ip route add 10.0.0.0/8 via $HOSTMIN dev $PRIVATE_INTERFACE &>> /dev/null
  ip route add 172.16.0.0/8 via $HOSTMIN dev $PRIVATE_INTERFACE &>> /dev/null
  ip route add 192.168.0.0/8 via $HOSTMIN dev $PRIVATE_INTERFACE &>> /dev/null
  service iptables save >> $LOG_FILE
  
  #A restart on the private interface is required to reconfigure the interface to pick up the newly added gateway
  echo "rebooting $PRIVATE_INTERFACE" >> $LOG_FILE 
  ifdown $PRIVATE_INTERFACE >> $LOG_FILE
  ifup   $PRIVATE_INTERFACE >> $LOG_FILE
  ip route add 10.0.0.0/8 via $HOSTMIN dev $PRIVATE_INTERFACE &>> /dev/null
  ip route add 172.16.0.0/8 via $HOSTMIN dev $PRIVATE_INTERFACE &>> /dev/null
  ip route add 192.168.0.0/8 via $HOSTMIN dev $PRIVATE_INTERFACE &>> /dev/null
  echo "Completed Setting up Client " >> $LOG_FILE 
}

set_master_ip()
{
  MASTER_PRIVATE_IP=$1
  echo "Master Private IP : $MASTER_PRIVATE_IP" >> $LOG_FILE
}

set_public_interface()
{
  TEMP_VAL=$1
  PUBLIC_INTERFACE=$(ip addr | grep $TEMP_VAL | cut -d' ' -f11)
  #$(netstat -ie | grep -B1 $TEMP_VAL | head -n1 | awk '{print $1}')
  echo "Public Interface : $PUBLIC_INTERFACE" >> $LOG_FILE 
}

start_public()
{
  echo "Starting public Interface : $PUBLIC_INTERFACE" >> $LOG_FILE
  ifup   $PUBLIC_INTERFACE >> $LOG_FILE
  echo "Public interface started successfully " >> $LOG_FILE
}

set_private_interface()
{
  TEMP_VAL=$1
  PRIVATE_INTERFACE=$(ip addr | grep $TEMP_VAL | cut -d' ' -f11)
  #=$(netstat -ie | grep -B1 $TEMP_VAL | head -n1 | awk '{print $1}')
  echo "Private Interface : $PRIVATE_INTERFACE" >> $LOG_FILE
}

usage() { echo "Usage: wrong args" 1>&2; exit 1; }

if [ "$(id -u)" != "0" ]; then  echo "Error: Please setup with root or sudo."
  exit 1
fi

mkdir -p "/var/log/gateway/"

if [ -f $LOG_FILE ];
then
   cat $LOG_FILE >> $LOG_HISTORY_FILE
   rm -f $LOG_FILE &>> /dev/null
else
   echo "$LOG_FILE  does not exist. Will be created"
fi

NOW=$(date +"%m-%d-%Y")
CURTIME=$(date +"%T") 
echo "-----------------------------------------------------------" >> $LOG_FILE 
echo "Started @ $NOW - $CURTIME" >> $LOG_FILE 
  

# Get opts loop to handle initial configuration flags
while getopts ":gcpm:u:v:z" opt; do
  case $opt in
    g) continue
       ;;
    c) continue
       ;;
    p) continue
       ;;
    m) set_master_ip $OPTARG
       ;;
    v) set_private_interface $OPTARG
       ;;
    u) set_public_interface $OPTARG
       ;;
    esac
done
# Reset opt argument index.
OPTIND=1

while getopts ":gcpm:u:v:z" opt; do
  case $opt in
    g) set_up_gateway
       ;;
    c) set_up_client
       ;;
    p) start_public
       ;;
   esac
done