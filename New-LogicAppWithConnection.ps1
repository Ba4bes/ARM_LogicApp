function New-LogicAppWithConnection {

#Variables to use for the deployment:
param(
    # Name of the Resourcegroup where the Logic App wil be deployed to
    [Parameter(Mandatory=$true)]
    [String]$ResourceGroupName,
    # Name of the resourcegroup where the automation account that needs to be connected resides
    [Parameter(Mandatory=$true)]
    [String]$AUTResourceGroupName,
    # Name of the automation account where the runbook is.
    [Parameter(Mandatory=$true)]
    [String]$AutomationAccount,
    # Path to the ARMtemplate
    [Parameter(Mandatory=$true)]
    [String]$TemplateFile,
    # Path to the ARM template parameter file
    [Parameter(Mandatory=$true)]
    [String]$TemplateParameterFile
)
try {
 Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction Stop | Out-Null
}
catch{
    New-AzureRmResourceGroup -Name $ResourceGroupName -Location 'West Europe' | Out-Null
    Write-Output "Resourcegroup created"
}

# [String]$ResourceGroupName = "PSLogic"
# [String]$AUTResourceGroupName = "AUT"
# [String]$AutomationAccount = "AutA01"
# [String]$TemplateFile = ".\LogicApp\LogicAppmail-runbook\azuredeploy.json"
# [String]$TemplateParameterFile = ".\LogicApp\LogicAppmail-runbook\azuredeploy.parameters.json"


Function Show-OAuthWindow {
    # mini window, made by Scripting Guy Blog
    # Taken directly from https://github.com/logicappsio/LogicAppConnectionAuth
    Add-Type -AssemblyName System.Windows.Forms

    $Form = New-Object -TypeName System.Windows.Forms.Form -Property @{Width = 600; Height = 800}
    $web = New-Object -TypeName System.Windows.Forms.WebBrowser -Property @{Width = 580; Height = 780; Url = ($url -f ($Scope -join "%20")) }
    $DocComp = {
        $Global:uri = $web.Url.AbsoluteUri
        if ($Global:uri -match "error=[^&]*|code=[^&]*") {$form.Close() }
    }
    $web.ScriptErrorsSuppressed = $true
    $web.Add_DocumentCompleted($DocComp)
    $form.Controls.Add($web)
    $form.Add_Shown( {$form.Activate()})
    $form.ShowDialog() | Out-Null
}

Function Set-Connection {
    # Function based on https://github.com/logicappsio/LogicAppConnectionAuth/blob/master/LogicAppConnectionAuth.ps1
    # It has been shortened and made into a function to use within a script.
    Param(
        # Parameter help description
        [Parameter(Mandatory = $true)]
        [String]$ResourceGroupName,
        [Parameter(Mandatory = $true)]
        [string] $ConnectionName
    )
    $Connection = Get-AzureRmResource -ResourceType "Microsoft.Web/connections" -ResourceGroupName $ResourceGroupName -ResourceName $ConnectionName

    Write-Output "Starting with $($Connection.Name)"
    Write-Output "Status: $($Connection.Properties.Statuses[0].status)"
    if ($Connection.Properties.Statuses[0].status -eq "Connected"){
        Write-Output "$($Connection.Name) is already connected"
        Continue
    }

    $parameters = @{
        "parameters" = , @{
            "parameterName" = "token";
            "redirectUrl"   = "https://ema1.exp.azure.com/ema/default/authredirect"
        }
    }
    #get the links needed for consent
    $consentResponse = Invoke-AzureRmResourceAction -Action "listConsentLinks" -ResourceId $Connection.ResourceId -Parameters $parameters -Force

    $url = $consentResponse.Value.Link
    #prompt user to login and grab the code after auth
    Show-OAuthWindow -URL $url
    $regex = '(code=)(.*)$'
    $code = ($uri | Select-String -pattern $regex).Matches[0].Groups[2].Value
    #     Write-Output "Received an accessCode: $code"

    if (-Not [string]::IsNullOrEmpty($code)) {
        $parameters = @{ }
        $parameters.Add("code", $code)
        # NOTE: errors ignored as this appears to error due to a null response

        #confirm the consent code
        Invoke-AzureRmResourceAction -Action "confirmConsentCode" -ResourceId $Connection.ResourceId -Parameters $parameters -Force -ErrorAction Ignore
    }
    else {
        Write-Error "Authorization failed."
    }

    #retrieve the connection
    $Connection = Get-AzureRmResource -ResourceType "Microsoft.Web/connections" -ResourceGroupName $ResourceGroupName -ResourceName $ConnectionName
    Write-Output "New status $($Connection.Name)"
    Write-Output "Status: $($Connection.Properties.Statuses[0].status)"


}

# Variables for the deployment
$subscriptionId = (Get-AzureRmContext).Subscription
# $ResourceGroupLocation = (Get-AzureRmResourceGroup -Name PSLogic).Location
$WorkFlowPath = "/subscriptions/@{encodeURIComponent('$subscriptionId')}/resourceGroups/@{encodeURIComponent('$AUTResourcegroupName')}/providers/Microsoft.Automation/automationAccounts/@{encodeURIComponent('$automationAccount')}/jobs"
Write-Output "starting deployment"

    $Parameters = @{
        ResourceGroupName = $ResourceGroupName
        TemplateFile = $TemplateFile
        TemplateParameterFile = $TemplateParameterFile
        WorkFlowPath = $WorkFlowPath
    }
try{
    New-AzureRmResourceGroupDeployment @Parameters
    Write-Output "Deployment succeeded"
}
catch {
    $_
    throw "Deployment failed"
}
Write-Output "Deployment succeeded, starting authentication"
#use the functions to authorize the connections connections.
$Connections = Get-AzureRmResource -ResourceType "Microsoft.Web/connections" -ResourceGroupName $ResourceGroupName
foreach ($Connection in $Connections){
    try {
    Set-Connection -ResourceGroupName $ResourceGroupName -ConnectionName $Connection.Name
    }
    catch{
        throw "Authorization of $($Connection.name) failed"
    }
}


}

New-LogicAppWithConnections -ResourceGroupName PSLogic2 -AUTResourceGroupName AUT -AutomationAccount AUTa01 -TemplateFile .\LogicApp\LogicAppmail-runbook\azuredeploy.json -TemplateParameterFile .\LogicApp\LogicAppmail-runbook\azuredeploy.parameters.json
