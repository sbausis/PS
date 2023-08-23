# Filter-JiraIssue.ps1
Param(
	[Parameter(Mandatory=$False)] [string] $username = "",
	[Parameter(Mandatory=$False)] [string] $token = "",
	[Parameter(Mandatory=$False)] [string] $query = "",
	[Parameter(Mandatory=$False)] [switch] $RunStdQueries = $True,
	[Parameter(Mandatory=$False)] [switch] $DoNotSaveCred = $False
)

Filter-JiraIssue.ps1 `
  -username "abc@def.ghi" `
  -token "ATATT3xFfGF0Ku6zsqKSAC2M................................................" `
  -query "test"

Filter-JiraIssue.ps1 `
  -username "abc@def.ghi" `
  -token "ATATT3xFfGF0Ku6zsqKSAC2M................................................" `
  -query "test" `
  -DoNotSaveCred
  
Filter-JiraIssue.ps1 -query "test"

Filter-JiraIssue.ps1
