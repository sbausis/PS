
################################################################################
# Arguments

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $false)] [Int] $CustomerID = 0,
    [Parameter(Mandatory = $false)] [String] $ServerHost = "manager.simple-services.ch",
    [Parameter(Mandatory = $false)] [String] $JWT = "",
	[Parameter(Mandatory = $false)] [Switch] $LegacyMode = $false,
	[Parameter(Mandatory = $false)] [Switch] $ForceInstall = $false,
    [Parameter(Mandatory = $false)] [String] $InstallerPath = "C:\Windows\Temp\WindowsAgentSetup.exe",
    [Parameter(Mandatory = $false)] [String] $LogFileName = "C:\Windows\Temp\WindowsAgentSetup.log"
)

################################################################################
# ENV

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$mypath = Split-Path $MyInvocation.MyCommand.Path -Parent

################################################################################
# Are we on a Legacy System

$RunInLegacyMode = $LegacyMode
if ($PSVersionTable.PSVersion.Major -lt 5) {
	Write-Host -f Yellow "- PowerShell Version 5 or higher needed. Switching to Legacy Mode"
	$RunInLegacyMode = $true
	Write-Host -f Green "- Legacy Mode"
} else {
	Write-Host -f Yellow "- Loading Module $mypath\PS-NCentral.psd1"
	Import-Module "$mypath\PS-NCentral.psd1" -Force
}

################################################################################
# Functions for LegacyMode

function Convert-EntityList {
	param(
		[Parameter (Mandatory = $true)] $EntityList
	)
	ForEach ($Entity in $EntityList) {
		$obj = [PSCustomObject]@{}
		ForEach ($item in $Entity.items) {
			$obj | Add-Member -MemberType NoteProperty -Name ($item.key).Substring(($item.key).IndexOf('.')+1) -Value ($item.Value)
		}
		$obj
	}
}

function Get-KeyPair {
	param(
		[Parameter (Mandatory = $true)] [String]$Key,
		[Parameter (Mandatory = $true)] $Value
	)
	[PSObject]@{Key=$Key; Value=$Value;}
}

function Get-NCData {
	param(
		[Parameter (Mandatory = $true)] $ServiceProxy,
		[Parameter (Mandatory = $true)] [String]$JWT,
		[Parameter (Mandatory = $true)] [String]$Method,
		[Parameter (Mandatory = $true)] [String]$Key,
		[Parameter (Mandatory = $true)] $Value
	)
	Try {
		$KeyPair = Get-KeyPair -Key $Key -Value $Value
		$NCData = $ServiceProxy.${Method}("", $JWT, $KeyPair)
		Convert-EntityList -EntityList $NCData
	}
	Catch {
		Write-Host -f Red "- Could not connect: $($_.Exception.Message)"
	}
}

################################################################################
# Do we have an JWT

$JWTFile = ""
if ($JWT -ne "" -AND (Test-Path $JWT)) {
	$JWTFile = $JWT
	$JWT = ""
}

if ($JWT -eq "") {
	if ($JWTFile -eq "") {
		$JWTFile = (Get-ChildItem "$mypath\JWT_*.jwt")[0]
	}
	
	if (Test-Path $JWTFile) {
		Write-Host -f Green "- Found JWT File $JWTFile"
		$JWT = Get-Content $JWTFile
	} else {
		Write-Host -f Red "- ERROR No JWT found !!!"
		exit 1
	}
}

if (($JWT.length) -lt 175) {
	Write-Host -f Red "- ERROR JWT is wrong !!!"
	exit 1
}

################################################################################
# Do we have a CustomerID

if ($CustomerID -eq 0) {
	
	$CustomerIDFile = (Get-ChildItem "$mypath\CustomerID_*.id")[0]
	Write-Host -f Green "- Found ID File $CustomerIDFile"
	
	$CustomerIDContent = Get-Content $CustomerIDFile
	$CustomerID = [int]::Parse($CustomerIDContent)
}

if ($CustomerID -lt 100) {
	Write-Host -f Red "- ERROR CustomerID is wrong !!!"
	exit 1
}

################################################################################
# Connect to NCentral

Write-Host -F Yellow "- Connecting to NCentral"
if ($RunInLegacyMode -eq $true) {
	Write-Host -f Green "- Legacy Mode"
	$NWSNameSpace = "NAble" + ([guid]::NewGuid()).ToString().Substring(25)
	$bindingURL = "http://" + $ServerHost + "/dms2/services2/ServerEI2?wsdl"
	$NWS = New-Webserviceproxy $bindingURL -Namespace ($NWSNameSpace)
	if ($NWS -eq $null) {
		Write-Host -F Red "- ERROR Connection to $ServerHost failed !!!"
		exit 1
	}
} else {
	$NCSession = New-NCentralConnection -ServerFQDN $ServerHost -JWT $JWT
	if ($NCSession.IsConnected -ne $true) {
		Write-Host -F Red "- ERROR Connection to $ServerHost failed !!!"
		exit 1
	}
}

################################################################################
# Get Customer Data

Write-Host -F Yellow "- Getting Customer Data ..."
if ($RunInLegacyMode -eq $true) {
	$CustomerList = Get-NCData -ServiceProxy $NWS -JWT $JWT -Method 'customerList' -Key 'listSOs' -Value 'False'
} else {
	$CustomerList = Get-NCCustomerList
}

Write-Host -F Green "  CustomerID: $CustomerID"
if (($Customer = $CustomerList | Where-Object customerid -eq $CustomerID) -eq $null) {
	Write-Host -F Red "- ERROR Customer with ID $CustomerID not found !!!"
	exit 1
}

if (($RetrievedCustomerName = $Customer.customername)) {
	Write-Host -F Green "  Customer Name ${CustomerID}:" $RetrievedCustomerName
} else {
	Write-Host -F Red "- ERROR Failed to get Customer Name !!!"
	exit 1
}

if (($RetrievedRegistrationToken = $Customer.RegistrationToken)) {
	Write-Host -F Green "  Registration Token ${CustomerID}:" $RetrievedRegistrationToken
} else {
	Write-Host -F Red "- ERROR Failed to get RegistrationToken !!!"
	exit 1
}

################################################################################
# Is the Agent installed already

$NotInstalled = $true
if (Test-Path -Path "C:\Program Files (x86)\N-able Technologies\Windows Agent\bin\agent.exe") {
    Write-Host -F Yellow "- The Agent is already installed."
	$NotInstalled = $false
}

$DifferentCustomer = $false
$XMLFile = "C:\Program Files (x86)\N-Able Technologies\Windows Agent\config\ApplianceConfig.xml"
if (Test-Path -Path $XMLFile) {
	Write-Host -F Yellow "- Testing current registrations Status"
	[xml]$Xml = Get-Content -Path $XMLFile -ErrorAction SilentlyContinue
	if ($Xml -ne $null -AND $Xml.ApplianceConfig -ne $null) {
		
		$CurrentCustomerID = $Xml.ApplianceConfig.CustomerID
		Write-Host -F Green "  CurrentCustomerID: $CurrentCustomerID"
		$CurrentRegStatus = ($Xml.ApplianceConfig.CompletedRegistration -eq "True")
		Write-Host -F Green "  CurrentRegStatus: $CurrentRegStatus"
		
		if ($CurrentRegStatus -eq $true -AND $CurrentCustomerID -ne $CustomerID) {
			Write-Host -F Red "- ERROR Device registered with different Customer $CurrentCustomerID !!!"
			$DifferentCustomer = $true
		} 
		
	}
}

################################################################################
# Installing the Agent

if ($ForceInstall -eq $true) {
	Write-Host -F Yellow "- Forcing Installation"
}

if ($ForceInstall -eq $true -Or ($DifferentCustomer -eq $false -AND $NotInstalled)) {
	
	Write-Host -F Green "- Installing the Agent"
	
	If ((Test-Path -Path $InstallerPath)) {
		Remove-Item -Path $InstallerPath -Force -ErrorAction SilentlyContinue
	}
	
	Write-Host -F Yellow "- Download Agent to $InstallerPath"
	$URI = "http://" + $ServerHost + "/download/current/winnt/N-central/WindowsAgentSetup.exe"
	Invoke-WebRequest -Uri $URI -OutFile $InstallerPath
	
	If (!(Test-Path -Path $InstallerPath)) {
		Write-Host -F Red "- ERROR Failed to download Setup to $InstallerPath !!!"
	}
	
	Write-Host -F Yellow "- Initiating the Agent Installer"
	Write-Host -F Yellow "- LogFile: $LogFileName"
	$proc = Start-Process -NoNewWindow -PassThru -Wait -FilePath $InstallerPath -ArgumentList "/s /v`" /qn /L*v $LogFileName CUSTOMERID=$CustomerID CUSTOMERSPECIFIC=1 REGISTRATION_TOKEN=$RetrievedRegistrationToken SERVERPROTOCOL=HTTPS SERVERADDRESS=$serverHost SERVERPORT=443 `""
	if (($proc.ExitCode) -eq 0) {
		Write-Host -F Green "- Agent installed successfully with Exitcode $($proc.ExitCode)"
	} else {
		Write-Host -F Red "- ERROR Agent installer failed with Exitcode $($proc.ExitCode) !!!"
		exit ($proc.ExitCode)
	}
}

################################################################################

Write-Host -F Green "- All done"
exit 0

################################################################################
