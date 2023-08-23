# Filter-JiraIssue.ps1<br />

Arguments:<br />
string $username = ""<br />
string $token = ""<br />
string $query = ""<br />
switch $RunStdQueries = $True<br />
switch $DoNotSaveCred = $False<br />

Examples:<br />
Filter-JiraIssue.ps1 `<br />
  -username "abc@def.ghi" `<br />
  -token "ATATT3xFfGF0Ku6zsqKSAC2M................................................" `<br />
  -query "test"<br />

Filter-JiraIssue.ps1 `<br />
  -username "abc@def.ghi" `<br />
  -token "ATATT3xFfGF0Ku6zsqKSAC2M................................................" `<br />
  -query "test" `<br />
  -DoNotSaveCred<br />
  
Filter-JiraIssue.ps1 -query "test"<br />

Filter-JiraIssue.ps1<br />
