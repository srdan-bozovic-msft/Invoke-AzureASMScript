# Invoking Azure Service Manager (ASM) comdlets using Invoke-AzureASMScript

Although Azure Resource Manager (ARM) is preferred model of interacting in Azure there are still some classic scenarios, mainly around [Azure Cloud Services](https://azure.microsoft.com/en-us/services/cloud-services/), that might require you to run Azure Service Manager (ASM) PowerShell commands.

This process is tedious as it requires creating and associating management certificate to your subscription and cleaning things up afterwards.

Invoke-AzureASMScript makes things easier for you by doing all this stuff in a background for you by using security best practices for certificate management.

```powershell

Login-AzureRmAccount

Invoke-AzureASMScript {
        Get-AzureService
}

```
