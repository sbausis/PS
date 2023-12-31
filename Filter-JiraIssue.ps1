
################################################################################

Param(
	[Parameter(Mandatory=$False)] [string] $username = "",
	[Parameter(Mandatory=$False)] [string] $token = "",
	[Parameter(Mandatory=$False)] [string] $query = "",
	[Parameter(Mandatory=$False)] [string] $filter = "",
	[Parameter(Mandatory=$False)] [switch] $RunStdQueries = $True,
	[Parameter(Mandatory=$False)] [switch] $DoNotSaveCred = $False
)

################################################################################

$Server = ''
$API = "$Server/rest/api/latest"

Write-Host -f Green "API: $API"

################################################################################

$LogFile = "$($PSScriptRoot)\.Filter-JiraIssue.log"

$CredPath = "$($PSScriptRoot)\.Filter-JiraIssue.cred"
if ($username -ne "" -AND $token -ne "" -AND $DoNotSaveCred -ne $True) {
	Write-Host -f yellow "- Saving Credentials to $CredPath"
	$creds = [PSCustomObject]@{
		username = $username
		token = $token
	}
	$creds | Export-Clixml -Path $CredPath
}

if ($username -eq "" -AND $token -eq "") {
	if (Test-Path -Path $CredPath) {
		Write-Host -f green "- Found Credentials in $CredPath"
		$creds = Import-Clixml -Path $CredPath
		$username = $creds.username
		$token = $creds.token
		Write-Host -f green "- username: $username"
		Write-Host -f green "- token: $($token.Substring(0,32))..."
	} else {
		Write-Host -f red "- Please provide Arguments: username, token"
		exit 1
	}
}

################################################################################

$auth = ([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${username}:${token}")))
$Headers = @{"Authorization" = "Basic $auth"}

$accountId = $null

################################################################################

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName System.Web

################################################################################

function Post-JiraAPI {
	Param(
		[Parameter(Mandatory=$True)] [string] $URI = "",
		[Parameter(Mandatory=$True)] [string] $Body = ''
	)
	Invoke-RestMethod -uri $URI -Method POST -ContentType "application/json" -Body $Body -Headers $Headers
}

function Put-JiraAPI {
	Param(
		[Parameter(Mandatory=$True)] [string] $URI = "",
		[Parameter(Mandatory=$True)] [string] $Body = ''
	)
	$rest = Invoke-RestMethod -uri $URI -Method PUT -ContentType "application/json" -Body $Body -Headers $Headers
	return $rest
}

function Get-JiraAPI {
	Param(
		[Parameter(Mandatory=$True)] [string] $URI = ""
	)
	Invoke-RestMethod -uri $URI -Method GET -ContentType "application/json" -Headers $Headers
}

################################################################################

function ConvertTo-JQL {
	Param(
		[Parameter(Mandatory=$True)] [string] $Query = ""
	)
    $umlauts = @(
        @('Ä',[char]0x00C4),
        @('Ö',[char]0x00D6),
        @('Ü',[char]0x00DC),
        @('ä',[char]0x00E4),
        @('ö',[char]0x00F6),
        @('ü',[char]0x00FC),
        @('\[','\\['),
        @('\]','\\]'),
		@('-','\\-'),
		@('ß',[char]0x00DF)
    )
    foreach ($umlaut in $umlauts) {
        $Query = $Query -replace $umlaut[0],$umlaut[1]
    }
    return $Query
}

################################################################################

function Search-JiraIssue {
	Param(
		[Parameter(Mandatory=$False)] [string] $Summary = ""
	)
	$s = ConvertTo-JQL -Query $Summary
	#$s = $Summary
	$q = 'project = HISHELP AND summary ~ "'+$s+'" AND assignee in (EMPTY) order by created DESC'
	Write-Host -f yellow "Query: $q"
	$URL = "$($API)/search?jql=" + [System.Web.HttpUtility]::UrlEncode($q)
	#Write-Host -f yellow $URL
	$issues = @()
	$issues = (Get-JiraAPI -URI $URL).issues
	return $issues
}

################################################################################

function Set-JiraIssueFields {
	Param(
		[Parameter(Mandatory=$True)] [string] $Key = "",
		[Parameter(Mandatory=$True)] [System.Collections.Hashtable] $Fields = ""
	)
	$Body = $Fields | ConvertTo-Json
	#Write-Host -f yellow $Body
	return Put-JiraAPI -URI "$API/issue/$Key" -Body $Body
}

################################################################################

function Set-JiraIssueAsignee {
	Param(
		[Parameter(Mandatory=$True)] [string] $Key = "",
		[Parameter(Mandatory=$True)] [string] $accountId = ""
	)
	#Write-Host -f yellow "URI: $API/issue/$Key"
	Write-Host -f yellow "Assignee: $accountId"
	$fields = @{
		fields = @{
			assignee = @{
				accountId = $accountId
			}
		}
	}
	return Set-JiraIssueFields -Key $Key -Fields $fields
}

function Set-JiraIssueComment {
	Param(
		[Parameter(Mandatory=$True)] [string] $Key = "",
		[Parameter(Mandatory=$True)] [string] $Comment = ""
	)
	#Write-Host -f yellow "URI: $API/issue/$Key/comment"
	Write-Host -f yellow "Comment: $Comment"
	$fields = @{
		body = $Comment
	}
	$Body = $Fields | ConvertTo-Json
	#Write-Host -f yellow $Body
	return Post-JiraAPI -URI "$API/issue/$Key/comment" -Body $Body
}

function Set-JiraIssueTransition {
	Param(
		[Parameter(Mandatory=$True)] [string] $Key = "",
		[Parameter(Mandatory=$True)] [int] $TransitionID = 0
	)
	#Write-Host -f yellow "URI: $API/issue/$Key/transitions"
	Write-Host -f yellow "TransitionID: $TransitionID"
	$fields = @{
		transition = @{
			id = $TransitionID
		}
	}
	$Body = $Fields | ConvertTo-Json
	#Write-Host -f yellow $Body
	return Post-JiraAPI -URI "$API/issue/$Key/transitions" -Body $Body
}

################################################################################

function Filter-JiraIssues {
	Param(
		[Parameter(Mandatory=$True)] [string] $Query = ""
		
	)
	$issues = Search-JiraIssue -Summary $Query
	$issues | ForEach-Object {
		$Key = $_.Key
		if (($Key)) {
			$timestamp = date
			$status = $_.fields.status.name
			Write-Output "[$timestamp] Issue: $Key Status: $status Query: $Query" | Tee-Object -FilePath $LogFile -Append
			$ret = Set-JiraIssueAsignee -Key $Key -accountId $accountId
			$ret = Set-JiraIssueComment -Key $Key -Comment "Wiederholender Alert. Wird ignoriert und automatisch erledigt."
			if ($status -ne "nicht Kundenrelevant") {
				$ret = Set-JiraIssueTransition -Key $Key -TransitionID 121
			}
		}
	}
}

################################################################################
################################################################################

function Get-JiraIssue {
	Param(
		[Parameter(Mandatory=$True)] [string] $Key = ""
		
	)
	return Get-JiraAPI -URI "$API/issue/$Key"
}

function New-JiraIssue {
	Param(
		[Parameter(Mandatory=$False)] [string] $Project = "HISHELP",
		[Parameter(Mandatory=$True)] [string] $Summary = "REST ye merry gentlemen.",
		[Parameter(Mandatory=$True)] [string] $Description = "Creating of an issue using project keys and issue type names using the REST API",
		[Parameter(Mandatory=$False)] [string] $IssueType = "10009"
	)
	#Write-Host -f yellow "TransitionID: $TransitionID"
	$Fields = @{
		fields = @{
			project = @{
				key = $Project
			};
			summary = $Summary;
			description = $Description;
			issuetype = @{
				id = $IssueType
			}
		}
	}
	$Body = $Fields | ConvertTo-Json
	Write-Host -f yellow $Body
	return Post-JiraAPI -URI "$API/issue/" -Body $Body
}

function Get-JiraUser {
	Param(
		[Parameter(Mandatory=$False)] [string] $UserName = "",
		[Parameter(Mandatory=$False)] [string] $AccountID = ""
	)
	if ($UserName -ne "") {
		return Get-JiraAPI -URI "$API/user/search?query=$UserName"
	} else {
		return Get-JiraAPI -URI "$API/user?accountId=$AccountID"
	}
}

################################################################################

Write-Host -f Yellow "- Getting AccountID for User $username"
$UserQuery = Get-JiraUser -UserName $username
if ($UserQuery -eq $null) {
	Write-Host -f red "- Failed to get AccountID"
	exit 1
}
$accountId = $UserQuery.accountId

################################################################################

if ($query -ne "") {
	$issues = Search-JiraIssue -Summary $Query
	$issues | ForEach-Object {
		$Key = $_.Key
		if (($Key)) {
			Write-Host -f green "- Found Issue: $Key Status: $status Query: $Query"
		}
	}
	exit 0
}

if ($filter -ne "") {
	Filter-JiraIssues -Query $filter
	exit 0
}

################################################################################
# Standard Ausnahmen

if ($RunStdQueries -eq $true) {
	Filter-JiraIssues -Query "EXAMPLE"
}

################################################################################

exit 0

################################################################################
#
#Write-Host -f yellow 'Get-JiraIssue -Key ""'
#Get-JiraIssue -Key ""
#
#Write-Host -f yellow 'New-JiraIssue -Summary "Neues automatisch erstelltes Ticket" -Description "Irgendeine Beschreibung hier"'
#New-JiraIssue -Summary "HIS | Neues automatisch erstelltes Ticket" -Description "Irgendeine Beschreibung hier"
#
#Write-Host -f yellow 'Get-JiraUser -AccountID $accountId'
#Get-JiraUser -AccountID $accountId
#
#Write-Host -f yellow 'Get-JiraUser -UserName $username'
#Get-JiraUser -UserName $username
#
#exit 0
#
################################################################################
