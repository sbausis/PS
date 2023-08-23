# Filter-JiraIssue.ps1

Arguments:
[string] $username = ""
[string] $token = ""
[string] $query = ""
[switch] $RunStdQueries = $True
[switch] $DoNotSaveCred = $False

Examples:
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
