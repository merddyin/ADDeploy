function Prompt-Options {
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