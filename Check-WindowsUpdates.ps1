
Param(
	[Parameter(Mandatory=$False)] [switch] $Install = $false
)

## TLS FIX
# For Windows 8.1/2012R2 enable TLS1.2
#If ((Get-WmiObject -class Win32_OperatingSystem).Caption -match "Windows Server 2012 R2" -OR (Get-WmiObject -class Win32_OperatingSystem).Caption -match "Windows 8.1") {
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#}

## CHECK DEPENCIES
If ([Environment]::OSVersion.Version -lt (new-object 'Version' 6,1)) {
	Write-Host -f red "- You need at least Windows 7 or Windows 2008 R2"
	Write-Host -f red "ERROR"
    exit 1099
}

If ([System.Version](Get-ItemProperty -Path 'HKLM:\Software\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Version -lt [System.Version]"4.5.2") {
	Write-Host -f red "- You need at least dotNET 4.5"
	Write-Host -f red "ERROR"
    exit 1099
}

if ($PSVersionTable.PSVersion.Major -lt 5) {
	
	Write-Host -f red "- You NEED PowerShell Version 5 or higher. Install Windows Management Framework 5+"
	
	If ((Get-WmiObject -class Win32_OperatingSystem).Caption -match "Windows Server 2012 R2" -AND [Environment]::Is64BitOperatingSystem) {
		$BaseURI = "http://tcpip.ch/WMF51/"
		$Filename = "Win8.1AndW2K12R2-KB3191564-x64.msu"
		$LocalFile = "C:\Windows\Temp\$Filename"
		Write-Host -f yellow "- We are on Win2012 R2 64Bit - Downloading $Filename"
		if (-NOT (Test-Path -Path $LocalFile)) {
			Invoke-WebRequest -Uri "$BaseURI$Filename" -outfile $LocalFile -ErrorAction SilentlyContinue
		}
		if (Test-Path -Path $LocalFile) {
			$MainDir = "C:\Windows\Temp"
			Write-Host -f yellow "- Installing WMF 5.1"
			$ret = (Start-Process -FilePath "C:\Windows\system32\wusa.exe" -ArgumentList "$LocalFile /quiet /norestart" -WorkingDirectory $MainDir -PassThru -WindowStyle Hidden -Wait).ExitCode
			# -IgnoreExitCodes "3010"
			
			Write-Host -f yellow "- WMF 5.1 Installation ExitCode: $ret"
			exit $ret
			
			
			#$waitTimeMilliseconds = 9 * 60 * 1000
			#$scriptBlock = {
			#	Write-Host "$($PSVersionTable.PSVersion)"
			#	#if ($PSVersionTable.PSVersion.Major -lt 5) {Write-Output "Noway"}
			#}
			#
			#$powershellPath = "$env:windir\system32\windowspowershell\v1.0\powershell.exe"
			#$process = Start-Process $powershellPath -NoNewWindow -ArgumentList ("-ExecutionPolicy Bypass -noninteractive -noprofile " + $scriptBlock) -PassThru -Wait
			#$ret = $process.WaitForExit($waitTimeMilliseconds)
			#
			#exit 0
			
		} else {
			Write-Host -f red "- Failed to download $Filename"
			Write-Host -f red "ERROR"
			exit 1099
		}
	}
	
	Write-Host -f red "  https://www.microsoft.com/en-us/download/details.aspx?id=54616"
	Write-Host -f red "ERROR"
    exit 1099
}

################################################################################

function Check-PackageProvider {
	param(
		[Parameter (Mandatory = $false)] [string] $PackageProvider = "NuGet"
	)
	## GET PACKAGEPROVIDER
	if ((Get-PackageProvider -Name $PackageProvider -ErrorAction SilentlyContinue) -eq $null) {
		Write-Host -f Yellow "- Installing PackageProvider $PackageProvider ..."
		if ((Install-PackageProvider -Name $PackageProvider -Force -ErrorAction SilentlyContinue) -eq $null) {
			Write-Host -f Red "- Could not install PackageProvider $PackageProvider !!!"
			Write-Host -f Red "ERROR"
			exit 1002
		}
	}
	else {
		Write-Host -f Green "- PackageProvider $PackageProvider already installed ..."
	}
}

function Check-ImportModule {
	param(
		[Parameter (Mandatory = $true)] [string] $ModuleName,
		[Parameter (Mandatory = $false)] [switch] $UpdateFirst = $false
	)
	## GET MODULE
	if ((Get-Module -Name $ModuleName -ListAvailable -ErrorAction SilentlyContinue) -eq $null) {
		Write-Host -f Yellow "- Installing Module $ModuleName ..."
		Install-Module -Name $ModuleName -Force
	}
	else {
		Write-Host -f Green "- Module $ModuleName already installed ..."
		if ($UpdateFirst) {
			$InstalledModule = Get-InstalledModule -Name $ModuleName -ErrorAction SilentlyContinue
			$AvailableModule = Get-Module -Name $ModuleName -ListAvailable
			if ($InstalledModule -ne $null -AND $AvailableModule -ne $null) {
				if (($InstalledModule.Version) -lt ($AvailableModule.Version)) {
					Write-Host -f Yellow "- Updating Module $ModuleName $($InstalledModule.Version) to $($AvailableModule.Version) ..."
					Update-Module -Name $ModuleName -Force
				} else {
					Write-Host -f Green "- Module $ModuleName $($InstalledModule.Version) is already up to Date ..."
				}
			} else {
				Write-Host -f Red " - ERROR : Failed to get Module Version !!!"
				#exit 1001
			}
		}
	}
	
	if ((Get-Module -Name $ModuleName -ErrorAction SilentlyContinue) -eq $null) {
		Write-Host -f Yellow "- Importing Module $ModuleName ..."
		Import-Module -Name $ModuleName -ErrorAction SilentlyContinue # -Verbose
	}
	else {
		Write-Host -f Green "- Module $ModuleName already loaded ..."
	}
	
	if ((Get-Module -Name $ModuleName -ErrorAction SilentlyContinue) -eq $null) {
		Write-Host -f Red "- Could not load Module !!!"
		Write-Host -f Red "ERROR"
		exit 1001
	}
}

function Check-Prerequirements {
	Check-PackageProvider
	Check-ImportModule -UpdateFirst -ModuleName "PSWindowsUpdate"
}

Check-Prerequirements

################################################################################

## SEARCH UPDATES
if ($Install -eq $true) {
	Write-Host "- Searching for Updates ..."
	$Updates = Get-WindowsUpdate -Install -AcceptAll -AutoReboot
} else {
	Write-Host "- Searching for Updates ..."
	$Updates = Get-WindowsUpdate
}
if ($Updates -ne $null) {
	$num = $Updates.count
	Write-Host -f yellow "- Found $num Updates to be Installed ..."
	$Updates | ForEach-Object {Write-Host $_.KB" "$_.Title}
	exit $num
} else {
	Write-Host -f green "- Found no Updates to be Installed ..."
	exit 0
}

exit 0

################################################################################