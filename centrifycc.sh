#!/bin/bash

################################################################################
#
# Copyright 2017-2018 Centrify Corporation
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#    http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Sample script for AWS automation orchestration with CentrifyCC
#
#
# This sample script is to demonstrate how AWS instances can be orchestrated to
# cenroll Centrify identity platform through Centrify agent for Linux.
#
# This script is tested on AWS Autoscaling using the following EC2 AMIs:
# - Red Hat Enterprise Linux 7.5                        x86_64
# - Ubuntu Server 16.04 LTS (HVM)                       x86_64
# - Ubuntu Server 18.04 LTS (HVM)                       x86_64
# - Amazon Linux AMI 2018.03.0 (HVM)                    x86_64
# - Amazon Linux 2 LTS Candidate AMI (HVM)              x86_64
# - CentOS 7 HVM                                        x86_64
# - SUSE Linux Enterprise Server 12 SP4 (HVM)           x86_64
#


function prerequisite()
{
   common_prerequisite
   r=$?
   if [ $r -ne 0 ];then
       echo "$CENTRIFY_MSG_PREX: prerequisite check failed"
   fi
   return $r
}

function check_config()
{
    if [ "$ENABLE_SSM_AGENT" != "yes" -a "$ENABLE_SSM_AGENT" != "no" ];then
        echo "$CENTRIFY_MSG_PREX: invalid ENABLE_SSM_AGENT: $ENABLE_SSM_AGENT" && return 1
    fi
  
    if [ "$CENTRIFYCC_TENANT_URL" = "" ];then
        echo "$CENTRIFY_MSG_PREX: must specify CENTRIFYCC_TENANT_URL!" 
        return 1
    fi

    if [ "$CENTRIFYCC_ENROLLMENT_CODE" = "" ];then
        echo "$CENTRIFY_MSG_PREX: must specify CENTRIFYCC_ENROLLMENT_CODE!" 
        return 1
    fi

    if [ "$CENTRIFYCC_FEATURES" = "" ];then
        echo "$CENTRIFY_MSG_PREX: must specify CENTRIFYCC_FEATURES!" 
        return 1
    fi

    if [[ "$CENTRIFYCC_AGENT_AUTH_ROLES" = "" && "$CENTRIFYCC_AGENT_SETS" = "" ]];then
        echo "$CENTRIFY_MSG_PREX: must specify CENTRIFYCC_AGENT_AUTH_ROLES or CENTRIFY_CC_AGENT_SETS!" 
        return 1
    fi

    CENTRIFYCC_NETWORK_ADDR_TYPE=${CENTRIFYCC_NETWORK_ADDR_TYPE:-PublicIP}
    case "$CENTRIFYCC_NETWORK_ADDR_TYPE" in
      PublicIP|PrivateIP|HostName)
        :
        ;;
      *)
        echo "$CENTRIFY_MSG_PREX: invalid CENTRIFYCC_NETWORK_ADDR_TYPE: $CENTRIFYCC_NETWORK_ADDR_TYPE " 
        return 1
        ;;
    esac

}

function generate_computer_name()
{
    case "$CENTRIFYCC_COMPUTER_NAME_FORMAT" in
    HOSTNAME)
        #host_name=`hostname`
        existing_hostname=`hostname`
        host_name="`echo $existing_hostname | cut -d. -f1`"
        if [ "$CENTRIFYCC_COMPUTER_NAME_PREFIX" = "" ];then
            COMPUTER_NAME="$host_name"
        else
            COMPUTER_NAME="$CENTRIFYCC_COMPUTER_NAME_PREFIX-$host_name"
        fi
        ;;
    INSTANCE_ID)
        instance_id=`curl --fail -s http://169.254.169.254/latest/meta-data/instance-id`
        r=$?
        if [ $r -ne 0 ];then
            echo "$CENTRIFY_MSG_PREX: cannot get instance id" && return $r
        fi
        if [ "$CENTRIFYCC_COMPUTER_NAME_PREFIX" = "" ];then
            COMPUTER_NAME="$instance_id"
        else
            COMPUTER_NAME="$CENTRIFYCC_COMPUTER_NAME_PREFIX-$instance_id"
        fi
        ;;
    *)
        echo "$CENTRIFY_MSG_PREX: invalid computer name format: $CENTRIFYCC_COMPUTER_NAME_FORMAT" && return 1
        ;;
    esac
    return 0
}

function install_packages()
{
    r=1
    centrify_packages=""
    case "$OS_NAME" in
    rhel|amzn|centos|sles)
        centrify_packages=CentrifyCC
        r=0
        ;;
    ubuntu)
        centrify_packages=centrifycc
        r=0
        ;;
    *)
        echo "$CENTRIFY_MSG_PREX doesn't supported for OS $OS_NAME"
        r=1
    esac
    [ $r -ne 0 ] && return $r
  
    install_packages_from_repo $centrify_packages
    r=$? 
  
    return $r
}


function prepare_for_cenroll()
{
    r=1
    case "$CENTRIFYCC_NETWORK_ADDR_TYPE" in
    PublicIP)
        CENTRIFYCC_NETWORK_ADDR=`curl --fail -s http://169.254.169.254/latest/meta-data/public-ipv4`
        r=$?
        ;; 
    PrivateIP)
        CENTRIFYCC_NETWORK_ADDR=`curl --fail -s http://169.254.169.254/latest/meta-data/local-ipv4`
        r=$?
        ;;
    HostName)
        CENTRIFYCC_NETWORK_ADDR=`hostname --fqdn`
		if [ "$CENTRIFYCC_NETWORK_ADDR" = "" ] ; then
			CENTRIFYCC_NETWORK_ADDR=`hostname`
		fi
        r=$?
        ;;
    esac
    if [ $r -ne 0 ];then
        echo "$CENTRIFY_MSG_PREX: cannot get network address for cenroll" && return $r
    fi
    return $r
}

function vault_accounts()
{
    r=0
    if [ "$CENTRIFYCC_VAULTED_ACCOUNTS" != "" ] ; then
        mkdir -p -m=755 /var/centrify/tmp
        VAULT_SCRIPT=/var/centrify/tmp/vaultaccount.sh
        VAULT_SCRIPT_LOG=/var/centrify/tmp/vaultaccount.log
        if [ -f $VAULT_SCRIPT ] ; then
            rm $VAULT_SCRIPT
        fi

        if [ "$CENTRIFYCC_MANAGE_PASSWORD" == "" ] ; then
            CENTRIFYCC_MANAGE_PASSWORD = "true"
        fi

        IFS=","
        # Create script
        echo '#!/bin/bash' > $VAULT_SCRIPT
        if [ "$DEBUG_SCRIPT" = "yes" ];then
            echo "set -x" >> $VAULT_SCRIPT
        fi
        echo "export VAULTED_ACCOUNTS=$CENTRIFYCC_VAULTED_ACCOUNTS" >> $VAULT_SCRIPT
        echo "export LOGIN_ROLES=\"$CENTRIFYCC_LOGIN_ROLES\"" >> $VAULT_SCRIPT
        echo "echo \"post hook script started.\" >> $VAULT_SCRIPT_LOG" >> $VAULT_SCRIPT
        echo "Permissions=()" >> $VAULT_SCRIPT
        echo "Field_Separator=\$IFS" >> $VAULT_SCRIPT
        echo "IFS=\",\"" >> $VAULT_SCRIPT
        echo "read -a roles <<< \$LOGIN_ROLES" >> $VAULT_SCRIPT
        echo "IFS=" >> $VAULT_SCRIPT
        echo "for role in \${roles[@]} " >> $VAULT_SCRIPT
        echo "  do " >> $VAULT_SCRIPT
        #echo "     Permissions=(\"\${Permissions[@]}\" \"-p\" \"\\\"role:\$role:Edit,Checkout,View,Login\\\"\" )" >> $VAULT_SCRIPT
        echo "     Permissions=(\"\${Permissions[@]}\" \"-p\" \"\\\"role:\$role:View,Login\\\"\" )" >> $VAULT_SCRIPT
        echo "done" >> $VAULT_SCRIPT
        echo "IFS=\",\"" >> $VAULT_SCRIPT
        echo "sleep 10" >> $VAULT_SCRIPT
        echo "for account in \$VAULTED_ACCOUNTS; do" >> $VAULT_SCRIPT
        echo "   export PASS=\`openssl rand -base64 16\`" >> $VAULT_SCRIPT
        echo "   if id -u \$account > /dev/null 2>&1; then" >> $VAULT_SCRIPT
        echo "      echo \$PASS | passwd --stdin \$account" >> $VAULT_SCRIPT
        echo "   else" >> $VAULT_SCRIPT
        echo "      useradd -m \$account -g sys" >> $VAULT_SCRIPT
        echo "      echo \$PASS | passwd --stdin \$account" >> $VAULT_SCRIPT
        echo "   fi" >> $VAULT_SCRIPT
        echo "   IFS=" >> $VAULT_SCRIPT
        echo "   echo \"Vaulting password for \$account\" >> $VAULT_SCRIPT_LOG 2>&1" >> $VAULT_SCRIPT
        echo "   echo \$PASS | /usr/sbin/csetaccount -V --stdin -m $CENTRIFYCC_MANAGE_PASSWORD \${Permissions[@]} \$account >> $VAULT_SCRIPT_LOG 2>&1" >> $VAULT_SCRIPT
        echo "done" >> $VAULT_SCRIPT
        echo "IFS=\$Field_Separator" >> $VAULT_SCRIPT

        chmod 700 $VAULT_SCRIPT

        # set up post-enroll hook
        if [ -f /usr/sbin/cedit ] ; then
            cedit --set cli.hook.cenroll:$VAULT_SCRIPT
        fi
        r=$?
        if [ $r -ne 0 ];then
            echo "$CENTRIFY_MSG_PREX: failed to set up post-enroll hook" && return $r
        fi
    fi

    return $r
}

function do_cenroll()
{
	# set up optional parameter string.
	# Note that login roles and sets are optional, but at least one must be required
	#
	CMDPARAM=()
	if [ "$CENTRIFYCC_AGENT_AUTH_ROLES" != "" ] ; then
	  CMDPARAM=("--agentauth" "$CENTRIFYCC_AGENT_AUTH_ROLES")
	  # grant permssion to view
	  IFS=","
	  for role in $CENTRIFYCC_AGENT_AUTH_ROLES
	  do
	    CMDPARAM=("${CMDPARAM[@]}" "--resource-permission" "role:$role:View")
	  done
	fi
	
	# set up add to set
	if [ "$CENTRIFYCC_AGENT_SETS" != "" ] ; then 
	   CMDPARAM=("${CMDPARAM[@]}" "--resource-set" "${CENTRIFYCC_AGENT_SETS[@]}")
	fi
	
	# for additional options, need to parse into array
	if [ "$CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS" != "" ] ; then
	  IFS=' ' read -a tempoption <<< "${CENTRIFYCC_CENROLL_ADDITIONAL_OPTIONS}"
	  CMDPARAM=("${CMDPARAM[@]}" "${tempoption[@]}")
	fi
	
    # Add Use My Account option
    if [ "$CENTRIFYCC_USE_MY_ACCOUNT" = "yes" ];then
        CMDPARAM=("${CMDPARAM[@]}" "-S" "CertAuthEnable:true")
    fi

    # Assigned PAS connector
    if [ "$CENTRIFYCC_ASSIGNED_CONNECTORS" != "" ] ; then
        CMDPARAM=("${CMDPARAM[@]}" "-S" "Connectors:${CENTRIFYCC_ASSIGNED_CONNECTORS}")
    fi

    # For each role that can login as vaulted account, grant them view permission to the resource 
    if [ "$CENTRIFYCC_VAULTED_ACCOUNTS" != "" ] || [ "$CENTRIFYCC_LOGIN_ROLES" != "" ] ; then
        IFS=","
        for role in $CENTRIFYCC_LOGIN_ROLES
        do
            CMDPARAM=("${CMDPARAM[@]}" "--resource-permission" "role:$role:View")
        done
    fi

	echo "cenroll parameters: [${CMDPARAM[@]}]"
	  
     /usr/sbin/cenroll  \
          --tenant "$CENTRIFYCC_TENANT_URL" \
          --code "$CENTRIFYCC_ENROLLMENT_CODE" \
          --features "$CENTRIFYCC_FEATURES" \
          --name "$COMPUTER_NAME" \
          --address "$CENTRIFYCC_NETWORK_ADDR" \
          "${CMDPARAM[@]}"
    r=$?
    #r=0
    if [ $r -ne 0 ];then
        echo "$CENTRIFY_MSG_PREX: cenroll failed!" 
        #return $r
	return 0
    fi
    /usr/bin/cinfo
    r=$?
    if [ $r -ne 0 ];then 
        echo "$CENTRIFY_MSG_PREX: cinfo failed after cenroll!" 
    fi

    return $r
}

function resolve_rpm_name()
{
    r=0
    case "$OS_NAME" in
    rhel|amzn|centos)
        if [ "$CENTRIFYCC_DISABLE_SELINUX" = "yes" ];then
            CENTRIFYCC_RPM_NAME="CentrifyCC-rhel6.x86_64.rpm"
        else
        # Revert to older version
            #CENTRIFYCC_RPM_NAME="CentrifyCC-19.5-119-rhel6.x86_64.rpm"
            CENTRIFYCC_RPM_NAME="CentrifyCC-rhel6.x86_64.rpm"
        fi
        ;;
    ubuntu)
        CENTRIFYCC_RPM_NAME="centrifycc-deb8-x86_64.deb"
        ;;
    sles)
        CENTRIFYCC_RPM_NAME="CentrifyCC-suse12.x86_64.rpm"
        ;;
    *)
        echo "$CENTRIFY_MSG_PREX: cannot resolve rpm package name for centrifycc on current OS $OS_NAME"
        r=1
        ;;
    esac
    return $r
}

function install_unenroll_enroll_service()
{
    # save the cenroll info so it can be used by the centrifycc-enroll service
    ENV_FILE="/etc/centrifycc/cenroll.env"
    
    # Special handling for array element with space
    IFS=" "
    re="[[:space:]]+"
    VAR="CMDPARAM="
    for i in $(echo ${!CMDPARAM[@]}); do
        if [ "$i" -gt 0 ]; then
            VAR+="|"
        fi
        VAR+=${CMDPARAM[$i]}
        #if [[ ${CMDPARAM[$i]} =~ $re ]]; then
        #    VAR+=\"${CMDPARAM[$i]}\"
        #else
        #    VAR+=${CMDPARAM[$i]}
        #fi
    done
    echo $VAR >> $ENV_FILE
    #echo "CMDPARAM=\"${CMDPARAM[@]}\"" >> $ENV_FILE
    echo "TENANT_URL=$CENTRIFYCC_TENANT_URL" >> $ENV_FILE
    echo "ENROLLMENT_CODE=$CENTRIFYCC_ENROLLMENT_CODE" >> $ENV_FILE
    echo "FEATURES=$CENTRIFYCC_FEATURES" >> $ENV_FILE
    echo "COMPUTER_NAME_PREFIX=$CENTRIFYCC_COMPUTER_NAME_PREFIX" >> $ENV_FILE
    echo "NETWORK_ADDR_TYPE=$CENTRIFYCC_NETWORK_ADDR_TYPE" >> $ENV_FILE
    echo "COMPUTER_NAME_FORMAT=$CENTRIFYCC_COMPUTER_NAME_FORMAT" >> $ENV_FILE
    
    chmod 644 $ENV_FILE
    
    CENROLL_SCRIPT_PATH="/etc/centrifycc/scripts"
    mkdir -p $CENROLL_SCRIPT_PATH
    
    # needed by centrifycc-enroll.service
    cp -f $centrifycc_deploy_dir/cenroll.sh $CENROLL_SCRIPT_PATH/cenroll.sh
    chmod 744 $CENROLL_SCRIPT_PATH/cenroll.sh
    
    SYSTEMD_PATH="/lib"
    if [ -d "/usr/lib/systemd/system" ]; then
        SYSTEMD_PATH="/usr/lib"
    fi

    cp -f $centrifycc_deploy_dir/centrifycc-unenroll.service $SYSTEMD_PATH/systemd/system/centrifycc-unenroll.service
    cp -f $centrifycc_deploy_dir/centrifycc-enroll.service $SYSTEMD_PATH/systemd/system/centrifycc-enroll.service
    
    chmod 644 $SYSTEMD_PATH/systemd/system/centrifycc-unenroll.service
    chmod 644 $SYSTEMD_PATH/systemd/system/centrifycc-enroll.service
    
    # need to start the centrifycc-unenroll.service immediately so when stop instance, cunenroll will be executed.
    systemctl enable centrifycc-unenroll.service --now
    systemctl enable centrifycc-enroll.service
}

function handle_ignore_users_groups()
{
    USER_IGNORE_FILE="/etc/centrifycc/user.ignore"
    GROUP_IGNORE_FILE="/etc/centrifycc/group.ignore"

    IFS=","
    for user in $CENTRIFYCC_USER_IGNORE; do
        echo $user >> $USER_IGNORE_FILE
    done

    for group in $CENTRIFYCC_GROUP_IGNORE; do
        echo $group >> $GROUP_IGNORE_FILE
    done
}

function start_deploy()
{ 
    resolve_rpm_name
    r=$? && [ $r -ne 0 ] && return $r

    download_install_rpm $CENTRIFYCC_DOWNLOAD_PREFIX $CENTRIFYCC_RPM_NAME
    r=$? && [ $r -ne 0 ] && return $r
  
    disable_selinux
    r=$? && [ $r -ne 0 ] && return $r

    enable_sshd_password_auth
    r=$? && [ $r -ne 0 ] && return $r

    enable_sshd_challenge_response_auth
    r=$? && [ $r -ne 0 ] && return $r
  
    enable_use_my_account
    r=$? && [ $r -ne 0 ] && return $r

    vault_accounts
    r=$? && [ $r -ne 0 ] && return $r

    prepare_for_cenroll
    r=$? && [ $r -ne 0 ] && return $r
  
    do_cenroll
    r=$? && [ $r -ne 0 ] && return $r
  
    install_unenroll_enroll_service
    
    handle_ignore_users_groups
    
    return 0
}

if [ "$DEBUG_SCRIPT" = "yes" ];then
    set -x
fi

file_parent=`dirname $0`
source $file_parent/common.sh
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: cannot source common.sh [exit code=$r]" && exit $r

detect_os
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: detect OS failed  [exit code=$r]" && exit $r

check_supported_os centrifycc not_support_ssm
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: current OS is not supported [exit code=$r]" && exit $r

check_config
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: error in configuration parameter settings [exit code=$r]" && exit $r

generate_computer_name
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: error in generating computer name [exit code=$r]" && exit $r

prerequisite
r=$? 
[ $r -ne 0 ] && echo "$CENTRIFY_MSG_PREX: cannot set up pre-requisites [Exit code=$r]" && exit $r

start_deploy
r=$?
if [ $r -eq 0 ];then
  echo "$CENTRIFY_MSG_PREX: CentrifyCC successfully deployed!"
else
  echo "$CENTRIFY_MSG_PREX: Error in CentrifyCC deployment [exit code=$r]!"
fi

exit $r
