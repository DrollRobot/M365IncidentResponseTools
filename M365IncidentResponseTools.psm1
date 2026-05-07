
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if ($Global:IRT_OriginalPrompt) {
        ${function:global:prompt} = $Global:IRT_OriginalPrompt
    }
}

# Load user config on module import
Import-IRTConfig

# FIXME switch to importing functions here?
