[CmdletBinding()]
param (
    [Parameter(Mandatory, ValueFromRemainingArguments, ValueFromPipeline)]
    [string[]] $Files
)

begin {
    $language_source = "en"
    $language_destinations = @(
        "de"
        "es"
        "fr"
        "it"
        "ja"
        "pl"
        "ptbr"
        "zhhans"
    )
    $file_out = Split-Path -Parent $($Global:MyInvocation.MyCommand.Definition)
    $file_out = Join-Path $file_out "xTranslator-BatchProcessor.txt"
    if (-not (Test-Path -LiteralPath $file_out)) { New-Item $file_out | Out-Null }
    $file_out = Get-Item -LiteralPath $file_out
    $content = ""
}

process {
    $Files | ForEach-Object {
        $plugin_file_name = $_
        $plugin_name = $plugin_file_name.Substring(0, $plugin_file_name.Length - 4)
        $language_destinations | ForEach-Object {
            $content += "StartRule
LangSource=${language_source}
LangDest=${_}
UseDataDir=1
Command=LoadFile:${plugin_file_name}
Command=ApplySst:0:1:${plugin_name}
Command=ApiTranslation:5:1
Command=Finalize
Command=SaveDictionary
Command=CloseAll
EndRule

"
        }
    }
    $content | Set-Content -LiteralPath $file_out -NoNewline
}
