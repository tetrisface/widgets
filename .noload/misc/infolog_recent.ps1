$pattern = "Loading:\s+LuaUI\\Widgets\\.*\.lua"
$file = "$env:USERPROFILE\AppData\Local\Programs\Beyond-All-Reason\data\infolog.txt"
$output = "$env:USERPROFILE\AppData\Local\Programs\Beyond-All-Reason\data\infolog_recent.txt"

# Find the last occurrence of any widget loading
Write-Host "Searching for pattern in log file..."
$lineNumber = (Select-String -Path $file -Pattern $pattern | Select-Object -Last 1).LineNumber

if ($lineNumber) {
    Write-Host "Found pattern at line $lineNumber. Extracting content..."

    # More memory-efficient approach using Get-Content with -TotalCount and -Tail
    $totalLines = (Get-Content $file | Measure-Object -Line).Lines
    $tailCount = $totalLines - $lineNumber + 1

    Write-Host "Extracting $tailCount lines from the end..."
    Get-Content $file -Tail $tailCount | Out-File $output -Encoding UTF8

    Write-Host "Done! Output saved to $output"
} else {
    Write-Host "Pattern not found in log file!"
}
