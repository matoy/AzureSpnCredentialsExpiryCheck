using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

#####
#
# TT 20210406 AzureSpnCredentialsExpiryCheck
# This script is executed by an Azure Function App
# It checks the expiry of Azure AD SPNs secrets & certificates
# It can be triggered by any monitoring system to get the results and status
#
# warning and critical thresholds can be passed in the GET parameters
# and are expressed in days before expiry
#
# Used SPN for quering AAD should have Graph API Application.ReadAll access
# API ref: https://docs.microsoft.com/en-us/graph/api/application-list
#####

# for each secret/cert, check expiry date, determine state and get owner if expired
function CheckCred {
	Param (
        $cred,
        $spn,
        $warning,
        $critical,
		$headers,
		$type
    )

	if ((Get-Date).AddDays($critical) -ge $cred.endDateTime) {
		$uri = "https://graph.microsoft.com/v1.0/applications/$($spn.id)/owners"
		$owner = (Invoke-RestMethod -Method Get -Uri $uri -Headers $headers).value.userPrincipalName
		if (!$owner) {$owner = "???"}
		$expiryDate = $cred.endDateTime.ToString("yyyy-MM-dd")
		if ((Get-Date) -gt $cred.endDateTime) {
			return "CRITICAL: $type '$($cred.displayName)' has expired on $expiryDate for SPN $($spn.displayName) (owned by $owner)`n"
		}
        elseif ((Get-Date).ToString("yyyy-MM-dd") -eq $expiryDate) {
            return "CRITICAL: $type '$($cred.displayName)' expires today for SPN $($spn.displayName) (owned by $owner)`n"
        }
		else {
			 return "CRITICAL: $type '$($cred.displayName)' will expire on $expiryDate for SPN $($spn.displayName) (owned by $owner)`n"
		}
	}
	elseif ((Get-Date).AddDays($warning) -gt $cred.endDateTime) {
		$uri = "https://graph.microsoft.com/v1.0/applications/$($spn.id)/owners"
		$owner = (Invoke-RestMethod -Method Get -Uri $uri -Headers $headers).value.userPrincipalName
		if (!$owner) {$owner = "???"}
		$expiryDate = $cred.endDateTime.ToString("yyyy-MM-dd")
		return "WARNING: $type '$($cred.displayName)' will expire on $expiryDate for SPN $($spn.displayName) (owned by $owner)`n"
	}
	return $null
}
function Send-EmailWithSendGrid {
     Param
    (
        [Parameter(Mandatory=$true)]
        [string] $From,
        [Parameter(Mandatory=$true)]
        [String] $To,
        [Parameter(Mandatory=$true)]
        [string] $ApiKey,
        [Parameter(Mandatory=$true)]
        [string] $Subject,
        [Parameter(Mandatory=$true)]
        [string] $Body
    )

    $headers = @{}
    $headers.Add("Authorization","Bearer $apiKey")
    $headers.Add("Content-Type", "application/json")
    $body_regex    = [Regex]::new("^[\x00-\x7F]*")
    # avoid sendgrid message:"Invalid UTF8"
    $Body = [regex]::match($Body, $body_regex).Value
    $jsonRequest = [ordered]@{
                            personalizations= @(@{to = @(@{email =  "$To"})
                                subject = "$SubJect" })
                                from = @{email = "$From"}
                                content = @( @{ type = "text/plain"
                                            value = "$Body" }
                                )} | ConvertTo-Json -Depth 10
    Invoke-RestMethod   -Uri "https://api.sendgrid.com/v3/mail/send" -Method Post -Headers $headers -Body $jsonRequest
}

$warning = [int] $Request.Query.Warning
if (-not $warning) {
    $warning = 30
}

$critical = [int] $Request.Query.Critical
if (-not $critical) {
    $critical = 10
}

# init variables
$tenantId = $env:TenantId
$applicationId = $env:AzureSpnCredentialsExpiryCheckApplicationID
$password = $env:AzureSpnCredentialsExpiryCheckSecret
$publisherDomain = $env:AzureSpnCredentialsExpiryCheckPublisherDomain
$signature = $env:Signature
$from = $env:AzureSpnCredentialsExpiryCheckMailFrom
$to = $env:AzureSpnCredentialsExpiryCheckMailTo
$subject = $env:AzureSpnCredentialsExpiryCheckMailSubject
$sendgridApiKey = $env:AzureSpnCredentialsExpiryCheckSendgridKey
$mailEnabled = $env:AzureSpnCredentialsExpiryCheckMailEnabled
$out = ""
$outMail = ""
$alerts = @{}
$warningCount = 0
$criticalCount = 0

# get auth token for MS Graph API
$Scope = "https://graph.microsoft.com/.default"
$Url = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
Add-Type -AssemblyName System.Web
$Body = @{
    client_id = $applicationId
	client_secret = $password
	scope = $Scope
	grant_type = 'client_credentials'
}
$PostSplat = @{
    ContentType = 'application/x-www-form-urlencoded'
    Method = 'POST'
    Body = $Body
    Uri = $Url
}
$Request = Invoke-RestMethod @PostSplat
$headers = @{
    Authorization = "$($Request.token_type) $($Request.access_token)"
}

# retrieve SPNs data
$uri = "https://graph.microsoft.com/v1.0/applications"
$spns = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
$spnsFiltered = $spns.value | where {$_.publisherDomain -eq $publisherDomain}
while ($spns.'@odata.nextLink') {
	$uri = $spns.'@odata.nextLink'
	$spns = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
	$spnsFiltered += $spns.value | where {$_.publisherDomain -eq $publisherDomain}
}

# browse SPNs and check for secret/cert expiry
foreach ($spn in $spnsFiltered) {
	$secrets = $spn.PasswordCredentials
	foreach ($secret in $secrets) {
		$checkCredResult = CheckCred -cred $secret -spn $spn -warning $warning -critical $critical -headers $headers -type "secret"
		if ($checkCredResult) {
			$alerts[$secret.endDateTime] += $checkCredResult
		}
	}
	$certs = $spn.KeyCredentials
	foreach ($cert in $certs) {
		$checkCredResult = CheckCred -cred $cert -spn $spn -warning $warning -critical $critical -headers $headers -type "certificate"
		if ($checkCredResult) {
			$alerts[$cert.endDateTime] += $checkCredResult
		}
	}
}

# allows to get alerts sorted by expiry date in output
foreach ($alert in ($alerts.GetEnumerator() | Sort-Object -Property name)) {
    $out += $alert.value
    if ($alert.value -match "CRITICAL") {
		$criticalCount++
	}
	if ($alert.value -match "WARNING") {
		$warningCount++
	}
    if ($alert.value -match "expires today") {
        $outMail += $alert.value
    }
}

if ($spnsFiltered.count -eq 0) {
	$warningCount++
	$body += "No SPN found, permission might be missing on used SPN`n"
}

if ($mailEnabled -eq "true" -and $outMail -ne "") {
    $outMail = "Dear OPS team,`n`nPlease know that secret/cert expires today for following SPN(s):`n$outMail`n-- `n$signature"
    Send-EmailWithSendGrid -from $from -to $to -ApiKey $sendgridApiKey -Body $outMail -Subject $subject
}

# add ending status and signature to results
$body = $out + "`n$signature"
if ($criticalCount -ne 0) {
    $body = "Status CRITICAL - Alert on $($criticalCount+$warningCount) of $($spnsFiltered.count) SPN(s)`n" + $body
}
elseif ($warningCount -ne 0) {
    $body = "Status WARNING - Alert on $warningCount of $($spnsFiltered.count) SPN(s)`n" + $body
}
else {
    $body = "Status OK - No alert on any $($spnsFiltered.count) SPN(s)`n" + $body
}
Write-Host $body

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
})
