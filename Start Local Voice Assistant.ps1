param([switch]$ListModels, [switch]$NoLaunch, [switch]$NoWindow)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$lms = Join-Path $env:USERPROFILE '.lmstudio\bin\lms.exe'
$qwen = Join-Path $env:APPDATA 'npm\qwenaudio.cmd'
$speech = Join-Path $root '.voice-env\Scripts\speech-to-speech.exe'
$config = Join-Path $env:USERPROFILE '.config\opencode\opencode.json'
$selectionFile = Join-Path $root '.selected-voice-model'

function Get-Listener($port) {
    Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Stop-LocalService($port, $expected) {
    $listener = Get-Listener $port
    if (-not $listener) { return }
    $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
    if (-not $processInfo.CommandLine.Contains($expected)) {
        throw "Port $port is in use by another program. Close it before changing models."
    }
    Stop-Process -Id $listener.OwningProcess -Force
    for ($i = 0; $i -lt 30 -and (Get-Listener $port); $i++) { Start-Sleep -Milliseconds 500 }
    if (Get-Listener $port) { throw "The old local service did not stop." }
}

if (-not (Test-Path $lms)) { throw 'LM Studio is not installed at the expected location.' }
$models = @((& $lms ls --llm --json | ConvertFrom-Json))
if ($LASTEXITCODE -ne 0 -or $models.Count -eq 0) { throw 'No chat models are downloaded in LM Studio.' }

Write-Host "`nChoose a model for your local voice assistant:`n"
for ($i = 0; $i -lt $models.Count; $i++) {
    Write-Host ('  {0}. {1}' -f ($i + 1), $models[$i].displayName)
}
if ($ListModels) { exit 0 }

$previous = if (Test-Path $selectionFile) { (Get-Content $selectionFile -Raw).Trim() } else { 'google/gemma-4-26b-a4b-qat' }
$defaultIndex = 1
for ($i = 0; $i -lt $models.Count; $i++) { if ($models[$i].modelKey -eq $previous) { $defaultIndex = $i + 1; break } }
$answer = Read-Host "`nEnter a number (Enter keeps $defaultIndex)"
if ([string]::IsNullOrWhiteSpace($answer)) { $answer = [string]$defaultIndex }
$number = 0
if (-not [int]::TryParse($answer, [ref]$number) -or $number -lt 1 -or $number -gt $models.Count) { throw 'That model number is not in the list.' }
$model = $models[$number - 1].modelKey
Write-Host "Starting $($models[$number - 1].displayName)..."
if ($NoLaunch) { exit 0 }

& $lms server start | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'LM Studio server did not start.' }
$loaded = @((& $lms ps --json | ConvertFrom-Json))
if ($LASTEXITCODE -ne 0) { throw 'Could not check loaded models.' }
if (-not ($loaded | Where-Object modelKey -EQ $model)) {
    foreach ($old in $loaded) { & $lms unload $old.identifier | Out-Null }
    & $lms load $model -y
    if ($LASTEXITCODE -ne 0) { throw 'The chosen model did not load.' }
}

if (-not (Test-Path $config)) { throw 'OpenCode model settings are missing.' }
$settings = Get-Content $config -Raw | ConvertFrom-Json
$settings.model = "lmstudio/$model"
$modelSettings = $settings.provider.lmstudio.models
foreach ($property in @($modelSettings.PSObject.Properties)) { $modelSettings.PSObject.Properties.Remove($property.Name) }
$modelSettings | Add-Member -NotePropertyName $model -NotePropertyValue ([pscustomobject]@{ name = $models[$number - 1].displayName })
$settings | ConvertTo-Json -Depth 20 | Set-Content $config -Encoding UTF8

if ($model -ne $previous) {
    Stop-LocalService 8765 'speech-to-speech'
    Stop-LocalService 3101 'qwen-audio-agent'
}

if (-not (Get-Listener 8765)) {
    if (-not (Test-Path $speech)) { throw 'The local speech program is missing.' }
    $speechArgs = @('serve', '--device', 'cpu', '--stt', 'parakeet-tdt', '--llm_backend', 'chat-completions', '--model_name', $model, '--responses_api_base_url', 'http://127.0.0.1:1234/v1', '--responses_api_api_key', 'lm-studio', '--tts', 'pocket', '--no_smart_turn')
    Start-Process -FilePath $speech -ArgumentList $speechArgs -WorkingDirectory $root -WindowStyle Hidden
}
for ($i = 0; $i -lt 120 -and -not (Get-Listener 8765); $i++) { Start-Sleep -Seconds 1 }
if (-not (Get-Listener 8765)) { throw 'The local speech service did not start.' }

if (-not (Get-Listener 3101)) { Start-Process -FilePath $qwen -WorkingDirectory $root -WindowStyle Hidden }
for ($i = 0; $i -lt 30 -and -not (Get-Listener 3101); $i++) { Start-Sleep -Seconds 1 }
if (-not (Get-Listener 3101)) { throw 'Qwen Audio Agent did not start.' }

Set-Content $selectionFile $model -Encoding UTF8
if (-not $NoWindow) {
    $chrome = Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'
    if (Test-Path $chrome) {
        Start-Process -FilePath $chrome -ArgumentList '--app=http://127.0.0.1:3101/'
    } else {
        Start-Process 'http://127.0.0.1:3101/'
    }
}
Write-Host 'Ready. Keep only one Qwen window open for voice.'
