
################################################################################

# IP Configuration
$IP = "192.168.10.132"
$MaskBits = 24
$Gateway = "192.168.10.1"
$Dns = "192.168.10.101"

# Domain Configuration
$DomainName = "HIS.local"
$ComputerName = "HIS-CLIENT05"
$DomainAdmin = "HIS\Administrator"

################################################################################

# Get Network Adapter
$Adapter = Get-NetAdapter -Name Ethernet

################################################################################

# Set Network Profile to Private
Set-NetConnectionProfile -InterfaceIndex $Adapter.ifIndex -NetworkCategory "Private"

# Enable Network Discovery
Get-NetFirewallRule -DisplayGroup 'Netzwerkerkennung' | Set-NetFirewallRule -Profile 'Private, Domain' -Enabled true
#Get-NetFirewallRule -DisplayGroup 'Network Discovery' | Set-NetFirewallRule -Profile 'Private, Domain' -Enabled true

################################################################################

# Remove old IP Configuration
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\Parameters\Interfaces\$(($Adapter).InterfaceGuid)" -Name EnableDHCP -Value 0
$Adapter | Remove-NetIPAddress -AddressFamily "IPv4" -Confirm:$false -ErrorAction SilentlyContinue
$Adapter | Remove-NetIPAddress -AddressFamily "IPv6" -Confirm:$false -ErrorAction SilentlyContinue
$Adapter | Remove-NetRoute -AddressFamily "IPv4" -Confirm:$false -ErrorAction SilentlyContinue
$Adapter | Remove-NetRoute -AddressFamily "IPv6" -Confirm:$false -ErrorAction SilentlyContinue

# Set IP Settings
$Adapter | New-NetIPAddress `
	-AddressFamily "IPv4" `
	-IPAddress $IP `
	-PrefixLength $MaskBits `
	-DefaultGateway $Gateway

# Set DNS Settings
$Adapter | Set-DnsClientServerAddress -ServerAddresses $DNS

# Disable IPv6
Disable-NetAdapterBinding -Name $Adapter.Name -ComponentID 'ms_tcpip6'

# Register DNS Client
Register-DnsClient

################################################################################

# Join Domain
$Credential = Get-Credential -Message "Credentials" -UserName $DomainAdmin
Add-Computer -DomainName $DomainName -NewName $ComputerName -Credential $Credential #-Restart

# Allow Powershell Scripts
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue

################################################################################

# Enable RDP
Enable-NetFirewallRule -DisplayGroup "Remotedesktop"
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0

# Disable NLA
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -name "SecurityLayer" -value 0
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -name "UserAuthentication" -value 0

# Restart Remote Desktop Service
Get-Service -Name TermService | Stop-Service -Force -ErrorAction SilentlyContinue
Get-Service -Name TermService | Start-Service -ErrorAction SilentlyContinue

################################################################################

# Disable Windows Update
if (!(Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate')) { New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows' -Name WindowsUpdate }
if (!(Test-Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU')) { New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -Name AU }
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -name "AUOptions" -ErrorAction SilentlyContinue
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -name "AUOptions" -value 2

# Restart Windows Update Service
Get-Service -Name wuauserv | Stop-Service -Force -ErrorAction SilentlyContinue
Get-Service -Name wuauserv | Start-Service -ErrorAction SilentlyContinue

################################################################################

exit 0

################################################################################
