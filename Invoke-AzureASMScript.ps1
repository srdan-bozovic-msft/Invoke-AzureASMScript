function Invoke-AzureASMScript
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]
        $ScriptBlock
    )

    #Begin local functions

    function CreateTempAccessCertificate 
    {
        $expires = (Get-Date).AddHours(1)
        $subject = 'DO_NOT_REMOVE_BEFORE_{0}:{1}:{2}.{3}_on_{4}/{5}/{6}_TEMP_ACCESS_CERTIFICATE' -f $expires.Hour, $expires.Minute, $expires.Second, $expires.Millisecond, $expires.Month, $expires.Day, $expires.Year
    
        New-SelfSignedCertificate -Subject $subject -NotAfter $expires -KeyLength 4096 -KeyExportPolicy NonExportable -CertStoreLocation 'Cert:\CurrentUser\My'
    }
    
    function RemoveTempAccessCertificate 
    {
        param(
            [System.Security.Cryptography.X509Certificates.X509Certificate]
            $certificate
        )   
        $certificate | Remove-Item 
    }

    function FormatAddCertificateBody
    {
        param(
            [System.Security.Cryptography.X509Certificates.X509Certificate]
            $certificate
        )   
        $publicKeyBase64 = [System.Convert]::ToBase64String($certificate.PublicKey.EncodedKeyValue.RawData)
        $thumbprint = $certificate.Thumbprint
        $dataBase64 = [System.Convert]::ToBase64String($certificate.RawData)
@"
        <SubscriptionCertificate xmlns="http://schemas.microsoft.com/windowsazure" xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
        	<SubscriptionCertificatePublicKey>$($publicKeyBase64)</SubscriptionCertificatePublicKey>
        	<SubscriptionCertificateThumbprint>$($thumbprint)</SubscriptionCertificateThumbprint>
        	<SubscriptionCertificateData>$($dataBase64)</SubscriptionCertificateData>
        </SubscriptionCertificate>
"@
    }

    function GetAuthHeader
    {
        $context = Get-AzureRmContext
    
        $azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile;
        $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile);
        $accessToken = $profileClient.AcquireAccessToken($context.Subscription.TenantId).AccessToken;
        
        @{
            'Content-Type' = 'application/xml'
            'x-ms-aad-authorization' = "Bearer $accessToken"
            'x-ms-version' = '2014-11-01'
        }
    }
    
    function AddSubscriptionCertificate
    {
        param(
            [System.Security.Cryptography.X509Certificates.X509Certificate]
            $certificate
        ) 
        
        $context = Get-AzureRmContext
        $subscriptionId = $context.Subscription.Id
    
        $uri = "https://management.core.windows.net/$subscriptionId/certificates"        
    
        $headers = GetAuthHeader
    
        $body = FormatAddCertificateBody $certificate
    
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body
    }

    function DeleteSubscriptionCertificate
    {
        param(
            [System.Security.Cryptography.X509Certificates.X509Certificate]
            $certificate
        ) 
        
        $context = Get-AzureRmContext
        $subscriptionId = $context.Subscription.Id
        $thumbprint = $certificate.Thumbprint
    
        $uri = "https://management.core.windows.net/$subscriptionId/certificates/$thumbprint"        
    
        $headers = GetAuthHeader
    
        Invoke-RestMethod -Uri $uri -Method Delete -Headers $headers
    }

    #End local functions

    $context = Get-AzureRmContext
    $subscriptionId = $context.Subscription.Id
    $subscriptionName = $context.Subscription.Name
    
    if($null -eq $context.Subscription)
    {
        Write-Host "You need to login first." -ForegroundColor Red
        return
    }

    try
    {
        $certificate = CreateTempAccessCertificate
        $thumbprint = $certificate.Thumbprint
        Write-Host "Temporary certificate created <$thumbprint>" -ForegroundColor Yellow
        Write-Host

        $certificateAdded = AddSubscriptionCertificate -certificate $certificate
        Write-Host "Temporary certificate associated with subscription <$subscriptionId>" -ForegroundColor Yellow
        Write-Host

        Set-AzureSubscription -SubscriptionName $subscriptionName -Certificate $certificate -SubscriptionID $subscriptionId
        Select-AzureSubscription -SubscriptionName $subscriptionName
        Write-Host "Azure ASM context set." -ForegroundColor Yellow
        Write-Host
        
        Write-Host "Running script." -ForegroundColor Cyan
        Write-Host

        . $ScriptBlock
        
        Write-Host
        Write-Host "Script completed." -ForegroundColor Cyan
        Write-Host

    }
    catch
    {
        if($null -eq $certificateAdded)
        {
            Write-Host "Certificate not added, check if you have proper permissions on subscription." -ForegroundColor Red
        }
        else
        {
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }
    finally
    {
        if($null -ne $certificate)
        {
            RemoveTempAccessCertificate -certificate $certificate
            Write-Host "Temporary certificate deleted." -ForegroundColor Yellow
        }
        if($null -ne $certificateAdded)
        {
            DeleteSubscriptionCertificate -certificate $certificate
            Write-Host "Temporary certificate dissasociated from subscription." -ForegroundColor Yellow
        }
    }
}
