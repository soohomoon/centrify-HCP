#!/bin/sh
# curl -O -L -H "Cache-Control: no-cache" https://raw.githubusercontent.com/marcozj/AWS-Automation/master/startup-userdata_abc0751.sh
# curl -O -L -H "Cache-Control: no-cache" https://raw.githubusercontent.com/marcozj/AWS-Automation/master/uninstallcc.sh

# Uninstall CentrifyCC
/usr/sbin/cunenroll -md
rpm -e CentrifyCC-19.5-119.x86_64

SYSTEMD_PATH="/lib"
if [ -d "/usr/lib/systemd/system" ]; then
	SYSTEMD_PATH="/usr/lib"
fi

systemctl stop centrifycc-enroll.service
systemctl stop centrifycc-unenroll.service
systemctl disable centrifycc-enroll.service
systemctl disable centrifycc-unenroll.service
[ -f $SYSTEMD_PATH/systemd/system/centrifycc-unenroll.service ] && rm $SYSTEMD_PATH/systemd/system/centrifycc-unenroll.service
[ -f $SYSTEMD_PATH/systemd/system/centrifycc-enroll.service ] && rm $SYSTEMD_PATH/systemd/system/centrifycc-enroll.service

[ -f /etc/ssh/pas_ca.pub ] && rm /etc/ssh/pas_ca.pub
[ -d "/var/centrify" ] && rm -rf /var/centrify
[ -d /tmp/auto_centrify_deployment ] && rm -rf /tmp/auto_centrify_deployment
mv /etc/ssh/sshd_config.centrify_backup /etc/ssh/sshd_config
systemctl restart sshd.service