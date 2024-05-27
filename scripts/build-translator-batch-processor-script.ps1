[CmdletBinding()]
param (
    [Parameter(Mandatory, ValueFromRemainingArguments, ValueFromPipeline)]
    [string[]] $Files,
    [string] $OutputFile = ".\support\scripts\xTranslator-BatchProcessor.txt"
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
    if (-not (Test-Path -LiteralPath $OutputFile)) { New-Item $OutputFile | Out-Null }
    $file_out = Get-Item -LiteralPath $OutputFile
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
}

end {
    $content | Set-Content -LiteralPath $file_out -NoNewline
}
