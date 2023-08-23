# Filter-JiraIssue.ps1<br />

# Arguments:<br />

string $username = ""<br />
string $token = ""<br />
string $query = ""<br />
switch $RunStdQueries = $True<br />
switch $DoNotSaveCred = $False<br />

# Examples:<br />

Filter-JiraIssue.ps1 -username "abc@def.ghi" -token "ATATT3xFfGF0Ku6zsqKSAC2M............" -query "test"<br />

Filter-JiraIssue.ps1 -username "abc@def.ghi" -token "ATATT3xFfGF0Ku6zsqKSAC2M............" -query "test" -DoNotSaveCred<br />
  
Filter-JiraIssue.ps1 -query "test"<br />

Filter-JiraIssue.ps1<br />
