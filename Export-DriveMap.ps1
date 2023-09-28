################################################################################

param (
	[Parameter(Mandatory = $false)] [string] $NameGPO = 'Client-User-Settings-Shares', 
	[Parameter(Mandatory = $false)] [string] $SearchBase = (Get-ADDomain).DistinguishedName,
	[Parameter(Mandatory = $false)] [bool] $ShowDisabledUser = $false
)

################################################################################

function Check-PackageProvider {
	param(
		[Parameter (Mandatory = $false)] [string] $PackageProvider = "NuGet"
	)
	## GET PACKAGEPROVIDER
	if ((Get-PackageProvider -Name $PackageProvider -ErrorAction SilentlyContinue) -eq $null) {
		Write-Host -f yellow "- Installing PackageProvider $PackageProvider ..."
		if ((Install-PackageProvider -Name $PackageProvider -Force -ErrorAction SilentlyContinue) -eq $null) {
			Write-Host -f red "- Could not install PackageProvider $PackageProvider !!!"
			Write-Host -f red "ERROR"
			exit 1002
		}
	}
	else {
		Write-Host -f green "- PackageProvider $PackageProvider already installed ..."
	}
}

function Check-ImportModule {
	param(
		[Parameter (Mandatory = $true)] [string] $ModuleName,
		[Parameter (Mandatory = $false)] [switch] $UpdateFirst = $false
	)
	## GET MODULE
	if ((Get-Module -Name $ModuleName -ListAvailable -ErrorAction SilentlyContinue) -eq $null) {
		Write-Host -f yellow "- Installing Module $ModuleName ..."
		Install-Module -Name $ModuleName -Force
	}
	else {
		Write-Host -f green "- Module $ModuleName already installed ..."
		if ($UpdateFirst) {
			$InstalledModule = Get-InstalledModule -Name $ModuleName -ErrorAction SilentlyContinue
			$AvailableModule = Get-Module -Name $ModuleName -ListAvailable
			if ($InstalledModule -ne $null -AND $AvailableModule -ne $null) {
				if (($InstalledModule.Version[0]) -lt ($AvailableModule.Version[0])) {
					Write-Host -f yellow "- Updating Module $ModuleName $($InstalledModule.Version[0]) to $($AvailableModule.Version[0]) ..."
					Update-Module -Name $ModuleName -Force
				} else {
					Write-Host -f green "- Module $ModuleName $($InstalledModule.Version[0]) is already up to Date ..."
				}
			} else {
				Write-Host -f red " - ERROR : Failed to get Module Version !!!"
				#exit 1001
			}
		}
	}
	
	if ((Get-Module -Name $ModuleName -ErrorAction SilentlyContinue) -eq $null) {
		Write-Host -f yellow "- Importing Module $ModuleName ..."
		Import-Module -Name $ModuleName -ErrorAction SilentlyContinue
	}
	else {
		Write-Host -f green "- Module $ModuleName already loaded ..."
	}
	
	if ((Get-Module -Name $ModuleName -ErrorAction SilentlyContinue) -eq $null) {
		Write-Host -f red "- Could not load Module !!!"
		Write-Host -f red "ERROR"
		exit 1001
	}
}

function Check-Prerequirements {
	Check-PackageProvider
	Check-ImportModule -UpdateFirst -ModuleName "ImportExcel"
}

Check-Prerequirements

################################################################################

[xml]$GPO_Xml = Get-GPOReport -All -ReportType Xml
$GPOS = $GPO_Xml.GPOS.GPO
$GPOS | ForEach-Object {
	$GPOName = $_.Name
	if ($_.User.ExtensionData.Extension.DriveMapSettings -ne $null) {
		if ($_.User.ExtensionData.Extension.DriveMapSettings.GetType().Name -eq "XmlElement") {
			Write-Host -f yellow "- Found GPO $GPOName with User Drive Maps"
			$NameGPO = $GPOName
		}
	}
}

################################################################################

Write-Host -f Green "- NameGPO: $NameGPO"
Write-Host -f Green "- SearchBase: $SearchBase"
Write-Host -f Green "- ShowDisabledUser: $ShowDisabledUser"

################################################################################

$ADName = (Get-ADDomain).Name.ToUpper()
$FileName = "$($PSScriptRoot)\$($ADName)-DriveMap.xlsx"

Write-Host -f Yellow "- Search for Users in $SearchBase"
if ($ShowDisabledUser -eq $true) {
	$ADUsers = Get-ADUser -Filter * -SearchBase $SearchBase | Sort-Object -Property SamAccountName
} else {
	$ADUsers = Get-ADUser -Filter * -SearchBase $SearchBase | Where-Object { $_.Enabled -eq $true } | Sort-Object -Property SamAccountName
}
Write-Host -f Green "- Found "$ADUsers.count" Users"

################################################################################

$ObjectTemplate = New-Object -TypeName psobject
$ObjectTemplate | Add-Member -MemberType NoteProperty -Name Name -Value $null
$ObjectTemplate | Add-Member -MemberType NoteProperty -Name Label -Value $null
$ObjectTemplate | Add-Member -MemberType NoteProperty -Name Path -Value $null
$ObjectTemplate | Add-Member -MemberType NoteProperty -Name GroupName -Value $null
#$ObjectTemplate | Add-Member -MemberType NoteProperty -Name GroupSID -Value $null

$ADUsers | ForEach-Object {
	$ObjectTemplate | Add-Member -MemberType NoteProperty -Name $_.SamAccountName -Value ""
}
#$ObjectTemplate | Add-Member -MemberType NoteProperty -Name Administrator -Value ""

################################################################################
$DriveArray = [System.Collections.ArrayList]::new()

[xml]$GPO_Xml = Get-GPOReport -Name $NameGPO -ReportType XML
$GPO_Drives = $GPO_Xml.GPO.User.ExtensionData.Extension.DriveMapSettings.Drive
$GPO_Drives | Sort-Object -Property name | ForEach-Object {
	$Name = $_.name
	$Label = $_.Properties.label
	$Path = $_.Properties.path
	$Action = $_.Properties.action
	
	if ($Action -ne "D") {
		Write-Host -f Green "- $Name $Path $Action"
		$Filters = $_.Filters
		if ($Filters -ne $null -And ($Filters.GetType().Name) -eq "XmlElement") {
			Write-Host -f yellow "- Process Filters"
			$FilterGroup = $Filters.FilterGroup
			$FilterGroup | ForEach-Object {
				$GroupName = $_.name
				$GroupSID = $_.sid
				Write-Host -f yellow "- $GroupName $GroupSID"
				$GroupMembers = Get-ADGroupMember -Identity $GroupSID -ErrorAction SilentlyContinue
				
				#if ($GroupMembers) {
					$newObject = $ObjectTemplate.PsObject.Copy()
					$newObject.Name = $Name
					$newObject.Label = $Label
					$newObject.Path = $Path
					$newObject.GroupName = $GroupName
					#$newObject.GroupSID = $GroupSID
					$GroupMembers | ForEach-Object {
						if ( $newObject.($_.SamAccountName) -eq "" ) {
							$newObject.($_.SamAccountName) = "X"
						}
					}
					[void]$DriveArray.Add($newObject)
				#}
			}
			
		} else {
			Write-Host -f yellow "- No Filters"
			$GroupName = "-"
			$GroupMembers = $ADUsers
			
			#if ($GroupMembers) {
				$newObject = $ObjectTemplate.PsObject.Copy()
				$newObject.Name = $Name
				$newObject.Label = $Label
				$newObject.Path = $Path
				$newObject.GroupName = $GroupName
				#$newObject.GroupSID = $GroupSID
				$GroupMembers | ForEach-Object {
					if ( $newObject.($_.SamAccountName) -eq "" ) {
						$newObject.($_.SamAccountName) = "X"
					}
				}
				[void]$DriveArray.Add($newObject)
			#}
		}
		
	}
}

Write-Host -f Green "- Done"

Write-Host -f yellow "- Export to $FileName"
Remove-Item -Path $FileName -Force -ErrorAction SilentlyContinue
$DriveArray | Export-Excel -Path $FileName -TableStyle Medium16 -Title "Netzlaufwerke $ADName" -WorksheetName "Netzlaufwerke $ADName" -TitleBold -AutoSize -FreezeTopRow

exit 0

################################################################################
