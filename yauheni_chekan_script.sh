#!/bin/bash

disk_1=$1
disk_2=$2
disk_3=$3
mount_point=$4

LOG_FILE=/var/log/yauheni_chekan_script.log

# Test for right parameters number
if [[ $# != 4 ]]; then
	echo 'Script takes exactly 4 parameters [DISK1] [DISK2] [DISK3] [MOUNT_POINT]' >&2
	exit 1
fi

# Test for disks availability
if [[ ! -b /dev/$disk_1 ]]; then
	echo $disk_1 is not a block device. >&2
	exit 1
elif [[ ! -b /dev/$disk_2 ]]; then
	echo $disk_2 is not a block device. >&2
	exit 1
elif [[ ! -b /dev/$disk_3 ]]; then
	echo $disk_3 is not a block device. >&2
	exit 1
fi

 
echo "	SYSTEM CONFIGURATION START
	`date`" | tee -a $LOG_FILE 
echo '==============================================='
echo Starting SSH configuration... | tee -a $LOG_FILE 

# Restrict access for root user via ssh
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config

systemctl restart sshd

# Enable ssh access to port 22
echo Opening port 22 for ssh access... | tee -a $LOG_FILE
iptables -A INPUT -p tcp --dport 22 -j ACCEPT && echo SSH configuration successful... | tee -a $LOG_FILE 

# Mount DVD iso to mounting point
echo Mounting DVD iso into /media/CentOS... | tee -a $LOG_FILE 
mkdir /media/CentOS 2> /dev/null || echo The directory already exists! | tee -a $LOG_FILE
mount -o loop,ro /ISO/CentOS-7-x86_64-DVD-2009.iso /media/CentOS

# Disable all repos
echo All repos are disabled... | tee -a $LOG_FILE 
rm -rf /etc/yum.repos.d/CentOS-[!M]*

# Edit the DVD repository file to enable the repo
echo Enabling DVD iso repository... | tee -a $LOG_FILE 
sed -i 's/enabled=0/enabled=1/g' /etc/yum.repos.d/CentOS-Media.repo

# Clean up the yum cache
yum clean all &> /dev/null

# Partition new disks as Linux LVM
echo Starting $disk_1 disk partition... | tee -a $LOG_FILE
(echo n; echo p; echo 1; echo ; echo ; echo t; echo 8e; echo w) | fdisk /dev/$disk_1 2>> $LOG_FILE > /dev/null && echo success...
echo Starting $disk_2 disk partition... | tee -a $LOG_FILE 
(echo n; echo p; echo 1; echo ; echo ; echo t; echo 8e; echo w) | fdisk /dev/$disk_2 2>> $LOG_FILE > /dev/null && echo success...
echo Starting $disk_3 disk partition... | tee -a $LOG_FILE
(echo n; echo p; echo 1; echo ; echo ; echo t; echo 8e; echo w) | fdisk /dev/$disk_3 2>> $LOG_FILE > /dev/null && echo success...

# Inform the OS of partition table changes
partprobe && echo Partition table changed successfully... | tee -a $LOG_FILE

# Initialize physical volumes for use by LVM
pvcreate /dev/sd[${disk_1}${disk_2}${disk_3}]1 || echo Physical volume creating FAIL... | tee -a $LOG_FILE

# Create a volume group (my_vg - group name)
vgcreate my_vg /dev/${disk_1}1 /dev/${disk_2}1 /dev/${disk_3}1 | tee -a $LOG_FILE

# Create logical volume of raid5 type.
lvcreate -n my_array --type raid5 -l 100%FREE -i 2 my_vg | tee -a $LOG_FILE

# Make filesystem of xfs type for ??my_array?? logical volume.
mkfs -t xfs /dev/my_vg/my_array && echo XFS filesystem successfully created for logical volume... | tee -a $LOG_FILE

# Add new info to /etc/fstab
echo /dev/my_vg/my_array $mount_point xfs defaults 0 0 >> /etc/fstab

# Make new directory for mounting ??my_array??lv
mkdir $mount_point 2> /dev/null || echo The directory already exists! | tee -a $LOG_FILE

# Mount lv into a newly created directory
mount -t xfs /dev/my_vg/my_array $mount_point

echo "	RAID5 array created successfully...
	Logical volume mounted successfully..." | tee -a $LOG_FILE
lsblk | tee -a $LOG_FILE
lvs | tee -a $LOG_FILE

echo NFS server setup...
# Installing NFS server soft
echo y | yum install nfs-utils &> /dev/null && echo NFS server installed successfully... | tee -a $LOG_FILE

# Starting services
systemctl enable rpcbind nfs-server
systemctl start rpcbind nfs-server

# Adding "my_array" share directory to exports file
echo "$mount_point 192.168.56.1/24(rw,sync,no_root_squash,no_all_squash)" >> /etc/exports
exportfs -r

# Adding firewall configurations
echo Setting up firewall configurations... | tee -a $LOG_FILE
firewall-cmd --permanent --zone=public --add-service=nfs
firewall-cmd --permanent --zone=public --add-service=mountd
firewall-cmd --permanent --zone=public --add-service=rpc-bind
firewall-cmd --reload

# Create directory for mounting shared dirs. Normally made on the client side
mkdir /mnt/nfs_shared_my_array 2> /dev/null || echo The directory already exists! | tee -a $LOG_FILE

# Mounting directory for share on the server to local sharing directory on the client
mount -t nfs 192.168.56.107:$mount_point /mnt/nfs_shared_my_array/

# Enabling auto-mounting after system reboot on the client side
echo 192.168.56.107:$mount_point /mnt/nfs_shared_my_array/ nfs defaults 0 0 >> /etc/fstab
echo '==============================================='

if [[ $? == 0 ]]; then
echo "	SYSTEM CONFIGURATION COMPLETED SUCCESSFULLY
	LOGICAL VOLUME: /dev/my_vg/my_array/
	SHARING DIRECTORY: $mount_point
	`date` " | tee -a $LOG_FILE
exit 0
fi

