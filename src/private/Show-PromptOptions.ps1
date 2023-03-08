function Show-PromptOptions {
<#
    .SYNOPSIS
        Short description

    .DESCRIPTION
        Long description

    .PARAMETER exampleparam
        Description of parameter and required elements

    .EXAMPLE
        Example of how to use this cmdlet

    .EXAMPLE
        Another example of how to use this cmdlet

    .INPUTS
        Inputs to this cmdlet (if any)

    .OUTPUTS
        Output from this cmdlet (if any)

    .NOTES
        Help Last Updated: 10/24/2020

        Cmdlet Version: 1.0
        Cmdlet Status: Release

        Copyright (c) Deloitte. All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and Deloitte assumes no liability.

    .LINK
        https://deloitte.com
#>
    [CmdletBinding()]
    param (
        [string[]]$PromptInfo,
        [string[]]$Options,
        [int]$default = 0
    )

    begin {
        $PromptTitle = $PromptInfo[0]
        $PromptMessage = $PromptInfo[1]
    }

    process {
        [System.Management.Automation.Host.ChoiceDescription[]]$PromptOptions = $Options | ForEach-Object {
            New-Object System.Management.Automation.Host.ChoiceDescription "&$($_)", "Answer - $_"
        }
    }

    end {
        $Result = $Host.UI.PromptForChoice($PromptTitle, $PromptMessage, $PromptOptions, $default)

        return $Result
    }
}