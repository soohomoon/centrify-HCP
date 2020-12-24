#!/bin/sh
# curl -O -L -H "Cache-Control: no-cache" https://raw.githubusercontent.com/marcozj/AWS-Automation/master/startup-userdata_abc0751.sh
# curl -O -L -H "Cache-Control: no-cache" https://raw.githubusercontent.com/marcozj/AWS-Automation/master/uninstalldc.sh

LOGIN_KEYTAB=/etc/centrifydc/login.keytab
ADJOINER=`/usr/share/centrifydc/kerberos/bin/klist -k $LOGIN_KEYTAB | grep @ | awk '{print $2}' | sed -n '1p'`
/usr/share/centrifydc/kerberos/bin/kinit -kt $LOGIN_KEYTAB -C $ADJOINER
/usr/sbin/adleave -I -r

# Uninstall CentrifyDC
rpm -e CentrifyDC-5.6.1-330.x86_64 CentrifyDC-openssl-5.6.1-330.x86_64 CentrifyDC-openldap-5.6.1-330.x86_64 CentrifyDC-curl-5.6.1-330.x86_64

SYSTEMD_PATH="/lib"
if [ -d "/usr/lib/systemd/system" ]; then
        SYSTEMD_PATH="/usr/lib"
fi

systemctl stop centrifydc-adjoin.service
systemctl stop centrifydc-adleave.service
systemctl disable centrifydc-adjoin.service
systemctl disable centrifydc-adleave.service

[ -f $SYSTEMD_PATH/systemd/system/centrifydc-adleave.service ] && rm $SYSTEMD_PATH/systemd/system/centrifydc-adleave.service
[ -f $SYSTEMD_PATH/systemd/system/centrifydc-adjoin.service ] && rm $SYSTEMD_PATH/systemd/system/centrifydc-adjoin.service

[ -d /etc/centrifydc ] && rm -rf /etc/centrify
[ -d /tmp/auto_centrify_deployment ] && rm -rf /tmp/auto_centrify_deployment
mv /etc/ssh/sshd_config.centrify_backup /etc/ssh/sshd_config
systemctl restart sshd.service