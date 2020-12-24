function Get-TimeStamp {   
    return "[{0:dd/MM/yy} {0:HH:mm:ss}]" -f (Get-Date)
}

$shutdownlogfile = "C:\Centrify\centrifycc_shutdown.log"
Write-Output "$(Get-TimeStamp) Running shutdown script..." | Out-file $shutdownlogfile -append

Write-Output "$(Get-TimeStamp) Unenroll from PAS..." | Out-file $shutdownlogfile -append
& 'C:\Program Files\Centrify\cagent\cunenroll.exe' -md