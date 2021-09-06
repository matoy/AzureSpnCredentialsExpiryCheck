# AzureSpnCredentialsExpiryCheck
  
## Why this function app ?
Azure Active Directory provides Service Principal Names (SPNs) to delegate Identity and Access Management.  
These SPNs have secrets and/or certificates that expire and people in your company may forget to renew them.  
Azure AD doesn't provide any feature to monitor SPNs secrets and certificates expiry yet (at the time of this writing).  You have hundreds of accounts with potentially several secrets for each account, people leaving the company and others coming, it's pretty sure that one day you'll have a secret used on a production application getting expired and that will make your app fail.  
  
This function app automatically gathers and outputs secrets and certificates that will expires soon by calling Azure API.  
  
Coupled with a common monitoring system (nagios, centreon, zabbix, or whatever you use), you'll automatically get alerted as soon as you have SPN with secrets or certificates expiring soon.  
</br>
</br>

## Requirements
* An "app registration" account (client id, valid secret and tenant id).  
* Granted "Application.ReadAll" access for this account on Graph API  
</br>

## Installation
Once you have all the requirements, you can deploy the Azure function with de "Deploy" button below:  
  
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fmatoy%2FAzureSpnCredentialsExpiryCheck%2Fmain%2Farm-template%2FAzureSpnCredentialsExpiryCheck.json) [![alt text](http://armviz.io/visualizebutton.png)](http://armviz.io/#/?load=https://raw.githubusercontent.com/matoy/AzureSpnCredentialsExpiryCheck/main/arm-template/AzureSpnCredentialsExpiryCheck.json)  
  
</br>
This will deploy an Azure app function with its storage account, app insights and "consumption" app plan.  
A keyvault will also be deployed to securely store the secret of your app principal.  
  
![alt text](https://github.com/matoy/AzureSpnCredentialsExpiryCheck/blob/main/img/screenshot1.png?raw=true)  
  
Choose you Azure subscription, region and create or select a resource group.  
  
* App Name:  
You can customize a name for resources that will be created.  
  
* Tenant ID:  
If your subscription depends on the same tenant than the account used to retrieve subscriptions information, then you can use the default value.  
Otherwise, enter the tenant ID of the account.  
  
* Subscription Billing Reader Application ID:  
Client ID of the account used to retrieve subscriptions information.  
  
* Subscription Billing Reader Secret:  
Secret of the account used to retrieve subscriptions information.  
   
* Zip Release URL:  
For testing, you can leave it like it.  
For more serious use, I would advise you host your own zip file so that you wouldn't be subject to release changes done in this repository.  
See below for more details.  
  
* Azure AD PublisherDomain:  
Publisher domain for your SPN(s), should be your Azure AD tenant primary domain, ex: mycompany.onmicrosoft.com.  
If you go to the "manifest" section of any your SPN in Azure portal, this is what you should see for the attribute "publisherDomain".  
  
* Mail enabled:  
True if you want to enable email notification the day secret/cert expires.  
  
* Mail subject:  
Customize subject of emails you'll receive.  
  
* Mail introduction:  
Customize introduction message in emails.  
  
* Mail from / to:  
Seems pretty obvious.  
  
* Sendgrid API key:  
Sendgrid is used to send emails and a valid API key must be provided. Since the API key will be stored in the keyvault, even is you disable this feature, don't let this field empty because that would cause the build with ARM template to fail (a secret cannot have an empty value).  
  
* Signature:  
When this function will be called by your monitoring system, you likely might forget about it.  
The signature output will act a reminder since you'll get it in the results to your monitoring system.  
  
When deployment is done, you can get your Azure function's URL in the output variables.  
Trigger it manually in your favorite browser and eventually look at the logs in the function.  
After you execute the function for the first time, it might (will) need 5-10 minutes before it works because it has to install Az module. You even might get an HTTP 500 error. Give the function some time to initialize, re-execute it again if necessary and be patient, it will work.  
  
Even after that, you might experience issue if Azure takes time to resolve your newly created keyvault:  
![alt text](https://github.com/matoy/AzureSpnCredentialsExpiryCheck/blob/main/img/kv-down.png?raw=true)  
Wait a short time and then restart your Azure function, your should have something like:  
![alt text](https://github.com/matoy/AzureSpnCredentialsExpiryCheck/blob/main/img/kv-up.png?raw=true)  
</br>
</br>

## Monitoring integration  
From there, you just have to call your function's URL from your monitoring system.  
  
You can find a script example in "monitoring-script-example" folder which makes a GET request, outputs the result, looks for "CRITICAL" or "WARNING" in the text and use the right exit code accordingly.  
  
Calling the function once a day should be enough.  
  
You can modify "warning" and "critical" thresholds within the GET parameters of the URL (just add &warning=80&critical=90 for example).  
  
Default values are 30 and 10 days for warning and critical threshold respectively.  
  
Be sure to have an appropriate timeout (60s or more) because if you have many subscriptions, the function will need some time to execute.  
  
This is an example of what you'd get in Centreon:  
![alt text](https://github.com/matoy/AzureSpnCredentialsExpiryCheck/blob/main/img/screenshot2.png?raw=true)  
</br>
</br>

## How to stop relying on this repository's zip  
To make your function to stop relying on this repo's zip and become independant, follow these steps:  
* remove zipReleaseURL app setting and restart app  
* in "App files" section, edit "requirements.psd1" and uncomment the line: 'Az' = '6.*'  
* in "Functions" section, add a new function called "AzureSpnCredentialsExpiryCheck" and paste in it the content of the file release/AzureSpnCredentialsExpiryCheck/run.ps1 in this repository  
