function New-ADDGPPlaceHolder {
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
            Help Last Updated: 08/20/2019

            Cmdlet Version: 0.1
            Cmdlet Status: (Alpha/Beta/Release-Functional/Release-FeatureComplete)

            Copyright (c) Topher Whitfield All rights reserved.

            Use of this source code is subject to the terms of use as outlined in the included LICENSE.RTF file, or elsewhere within this file. This
            source code is provided 'AS IS', with NO WARRANTIES either expressed or implied. Use of this code within your environment is done at your
            own risk, and the author assumes no liability.

        .LINK
            https://mer-bach.org
    #>
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
    Param (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [Alias("DistinguishedName","OrgDN")]
        $SourceDN
    )

    Begin {

    }

    Process {

    }

    End {

    }

}