function Read-PrivateVariable {
<#
    .SYNOPSIS
        Function that allows to read the variables defined within the module to help with troubleshooting

    .DESCRIPTION
        Function that allows to read the variables defined within the module to help with troubleshooting

    .PARAMETER var
        Variable to check. Returns all variables in Script scope when empty.

    .EXAMPLE
        PS C:\> Read-PrivateVariable 

    .INPUTS
        System.String

    .OUTPUTS
        PowerShellObject

    .NOTES
        Cmdlet Version: 1.0 - Remove prior to publish

        Copyright (c) Topher Whitfield All rights reserved.

        Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
        source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
        own risk, and the author assumes no liability.

    .LINK
        https://mer-bach.org
    
    #>
    Param ( $var )

    if ( $var ) {
        Get-Variable -Name $var -Scope Script | Select -ExpandProperty Value
    } Else {
        Get-Variable -Scope Script
    }

}