
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    if ($Global:IRT_OriginalPrompt) {
        ${function:global:prompt} = $Global:IRT_OriginalPrompt
    }

#     Get-Variable -Scope Global -Name 'IRT_*' -ErrorAction SilentlyContinue |
#         Remove-Variable -Scope Global -ErrorAction SilentlyContinue
}
