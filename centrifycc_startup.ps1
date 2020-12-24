<powershell>
function Get-TimeStamp {   
    return "[{0:dd/MM/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

$startuplogfile = "C:\Centrify\centrifycc_startup.log"
Write-Output "$(Get-TimeStamp) Running startup script..." | Out-file $startuplogfile -append

$centrifycc_installed = ((gp HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*).displayname -Match "Centrify Client for Windows").Length -gt 0

# AWS Bucket Name.
$bucketName = "bucket-name"
# Name of package file.
$packageFilename = "cagentinstaller.msi"
# Registration code to use.
$regCode = 
# Tenant URL against which to enroll.
$cloudURL = 
# Connector proxy address used by cagent to connect to tenant
$proxyAddress = 
# System Set that the instance to be added
$systemSet = 
# Name of Connector the onboarded system will use
$connector = 
# Local group mapping to be configured in PAS
$groupMapping = 

# Optional - select the FQDN Type (PrivateIP, PublicIP, PrivateDNS, PublicDNS). Defaults to PublicDNS.
$addressType = ''
# Optional - select the Name Type (NameTag, LocalHostname, PublicHostname, InstanceID). Defaults to LocalHostname.
$nameType = ''
 
$system_name = Get-EC2InstanceMetadata -Category LocalHostname
$instid = Get-EC2InstanceMetadata -Category InstanceId
#$tagname = ((Get-EC2Instance -InstanceId $instid) | Select -ExpandProperty RunningInstance).tag

if (-NOT $centrifycc_installed) {
    Write-Output "$(Get-TimeStamp) Retreiving package..." | Out-file $startuplogfile -append
    if (-NOT (Test-Path "C:\Centrify")) {
        New-Item -ItemType Directory -Path C:\Centrify
    }
    #$url="https://raw.githubusercontent.com/marcozj/AWS-Automation/master/cagentinstaller.msi"
    $url="http://edge.centrify.com/products/cloud-service/WindowsAgent/Centrify/cagentinstaller.msi"
    $filepath="c:\Centrify\cagentinstaller.msi"
    $webclient = New-Object System.Net.WebClient
    $webclient.DownloadFile($url,$filepath)
    
    #$file = (Read-S3Object -BucketName $bucketName -Key $packageFilename -File C:\Centrify\$packageFilename)
    $file = Get-ChildItem "C:\Centrify\cagentinstaller.msi"
}

$shutdownScript = "C:\Centrify\centrifycc_shutdown.ps1"
if (-NOT (Test-Path $shutdownScript)) {
    Write-Output "$(Get-TimeStamp) Retreiving shutdown file..." | Out-file $startuplogfile -append
    $url="https://raw.githubusercontent.com/marcozj/AWS-Automation/master/centrifycc_shutdown.ps1"
    $webclient = New-Object System.Net.WebClient
    $webclient.DownloadFile($url,$shutdownScript)
}

$iniFile = "C:\Centrify\psscripts.ini"
if (-NOT (Test-Path $iniFile)) {
    Write-Output "$(Get-TimeStamp) Retreiving ini file..." | Out-file $startuplogfile -append
    $url="https://raw.githubusercontent.com/marcozj/AWS-Automation/master/psscripts.ini"
    $webclient = New-Object System.Net.WebClient
    $webclient.DownloadFile($url,$iniFile)
    $dir = "C:\Windows\system32\GroupPolicy\Machine\Scripts\"
    if (-NOT (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir
    }
    Copy-Item -Path $iniFile -Destination C:\Windows\system32\GroupPolicy\Machine\Scripts\psscripts.ini
}

$regFile = "C:\Centrify\centrifycc_shutdown.reg"
if (-NOT (Test-Path $regFile)) {
    Write-Output "$(Get-TimeStamp) Retreiving registry file..." | Out-file $startuplogfile -append
    $url="https://raw.githubusercontent.com/marcozj/AWS-Automation/master/centrifycc_shutdown.reg"
    $webclient = New-Object System.Net.WebClient
    $webclient.DownloadFile($url,$regFile)
    & reg import $regFile
}

# Retrieves the Name to be registered in PAS.
switch ($nameType.ToLower())
{
   "nametag"         {$system_name = $tagname.Item(0).Value}
   "localhostname"   {$system_name = Get-EC2InstanceMetadata -Category LocalHostname }
   "publichostname"  {$system_name = Get-EC2InstanceMetadata -Category PublicHostname }
   "instanceid"      {$system_name = $instid }
   default {$system_name = Get-EC2InstanceMetadata -Category LocalHostname}
}
$system_name = "aws-" + $system_name
  
# Retrieves the FQDN to be registered in PAS.
switch ($addressType.ToLower())
{
   "publicip"   {$ipaddr = Get-EC2InstanceMetadata -Category PublicIPv4 }
   "privateip"  {$ipaddr = Get-EC2InstanceMetadata -Category LocalIPv4 }
   "publicdns"  {$ipaddr = Get-EC2InstanceMetadata -Category PublicHostname }
   "privatedns" {$ipaddr = Get-EC2InstanceMetadata -Category LocalHostname }
   default {$ipaddr = Get-EC2InstanceMetadata -Category LocalIpv4 }
}
  
Write-Output "$(Get-TimeStamp) The system will be enrolled as $system_name with IP/FQDN $ipaddr." | Out-file $startuplogfile -append

$DataStamp = get-date -Format yyyyMMddTHHmmss
$logFile = '{0}-{1}.log' -f $file.fullname,$DataStamp
$MSIArguments = @(
"/i"
('"{0}"' -f $file.fullname)
"/qn"
"/norestart"
"/L*v"
$logFile
)
 
if (-NOT $centrifycc_installed) {
    Write-Output "$(Get-TimeStamp) Installing CentrifyCC..." | Out-file $startuplogfile -append
    Start-Process "msiexec.exe" -ArgumentList $MSIArguments   -Wait -NoNewWindow
}

Write-Output "$(Get-TimeStamp) Enrolling..." | Out-file $startuplogfile -append
& "C:\Program Files\Centrify\cagent\cenroll.exe" --force --tenant $cloudURL --code $regCode --features all --address=$ipaddr --name=$system_name --agentauth="LAB Cloud Local Admins,LAB Cloud Normal User" --resource-permission="role:LAB Cloud Local Admins:View" --resource-permission="role:LAB Cloud Normal User:View" --resource-set=$systemSet --http-proxy $proxyAddress -S CertAuthEnable:true -S Connectors:$connector --resource-permission="role:LAB Infrastructure Admins:View" --resource-permission="role:System Administrator:View" --groupmap=$groupMapping
Start-Sleep -s 10

Write-Output "$(Get-TimeStamp) Change administrator account password..." | Out-file $startuplogfile -append

# Generate random password
add-type -AssemblyName System.Web
$minLength = 12
$maxLength = 20
$nonAlphaChars = 2
$length = Get-Random -Minimum $minLength -Maximum $maxLength
$Password = [System.Web.Security.Membership]::GeneratePassword($length, $nonAlphaChars)
$Secure_String_Pwd = ConvertTo-SecureString $Password -AsPlainText -Force
$UserAccount = Get-LocalUser -Name "Administrator"
$UserAccount | Set-LocalUser -Password $Secure_String_Pwd
 
Write-Output "$(Get-TimeStamp) Vaulting account..." | Out-file $startuplogfile -append
& "C:\Program Files\Centrify\cagent\csetaccount.exe" --managed=false --password=$Password --permission='\"role:infra_admin_cset:View,Login\"' --permission='\"role:sysadmin_cset:View,Login\"' Administrator
</powershell>
<persist>true</persist>