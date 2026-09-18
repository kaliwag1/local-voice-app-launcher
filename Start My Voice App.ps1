$ErrorActionPreference = 'Stop'
$voiceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:ZD_VOICE_REASONING_ADAPTER = '1'
$env:PYTHONPATH = (Join-Path $voiceRoot 'qwen-audio-agent-editable\scripts\runtime\speech-adapter') + $(if ($env:PYTHONPATH) { [IO.Path]::PathSeparator + $env:PYTHONPATH } else { '' })
$env:NLTK_DATA = (Join-Path $voiceRoot 'nltk_data') + $(if ($env:NLTK_DATA) { [IO.Path]::PathSeparator + $env:NLTK_DATA } else { '' })
$statusPath = Join-Path $voiceRoot 'Last Voice App Start.txt'
Set-Content -LiteralPath $statusPath -Value 'Checking local voice app...' -Encoding UTF8
trap {
    Set-Content -LiteralPath $statusPath -Value ("Failed: " + $_.Exception.Message) -Encoding UTF8
    exit 1
}
$appExe = Join-Path $voiceRoot 'qwen-audio-agent-editable\dist\desktop-panel\win-unpacked\Qwen Audio Agent.exe'
$lmsExe = Join-Path $env:USERPROFILE '.lmstudio\bin\lms.exe'
$speechExe = Join-Path $voiceRoot '.voice-env\Scripts\speech-to-speech.exe'
$opencodeBin = 'C:\Users\JakeW\AppData\Roaming\npm\node_modules\opencode-ai\bin\opencode.exe'
$selectionFile = Join-Path $voiceRoot '.selected-voice-model'
# Context window for the local chat model. OpenCode agent tasks need well over 8k.
$modelContextLength = 32768
# The in-app "Context" picker writes this file; it wins over the default above.
$contextFile = Join-Path $voiceRoot '.selected-voice-context'
if (Test-Path -LiteralPath $contextFile) {
    $chosenContext = 0
    if ([int]::TryParse((Get-Content -LiteralPath $contextFile -Raw).Trim(), [ref]$chosenContext) -and $chosenContext -ge 8192) {
        $modelContextLength = $chosenContext
    }
}

function Get-Listener([int]$port) {
    Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
}

if (-not (Test-Path -LiteralPath $appExe)) { throw 'The editable desktop app has not been built yet.' }
if (-not (Test-Path -LiteralPath $lmsExe)) { throw 'LM Studio is missing.' }
if (-not (Test-Path -LiteralPath $speechExe)) { throw 'The local speech service is missing.' }
if (-not (Test-Path -LiteralPath $selectionFile)) { throw 'No local model has been selected yet.' }
$modelKey = (Get-Content -LiteralPath $selectionFile -Raw).Trim()
if (-not $modelKey) { throw 'The selected local model is empty.' }

$runningApp = Get-CimInstance Win32_Process -Filter "Name = 'Qwen Audio Agent.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $appExe } | Select-Object -First 1
if ($runningApp) {
    Set-Content -LiteralPath $statusPath -Value 'Bringing open voice app forward...' -Encoding UTF8
    Start-Process -FilePath $appExe -WorkingDirectory (Split-Path -Parent $appExe)
    Set-Content -LiteralPath $statusPath -Value 'Existing app window requested.' -Encoding UTF8
    return
}

$bonsaiSelected = $modelKey -in @('bonsai/official', 'bonsai/crack')
$modelEndpoint = 'http://127.0.0.1:1234/v1'
$speechModel = $modelKey
$bonsaiHelper = Join-Path $voiceRoot 'qwen-audio-agent-editable\desktop\src\bonsai-runtime.mjs'
$nodeExe = (Get-Command node.exe -ErrorAction Stop).Source
if ($bonsaiSelected) {
    Set-Content -LiteralPath $statusPath -Value 'Starting Bonsai (Prism)...' -Encoding UTF8
    $loaded = @((& $lmsExe ps --json | ConvertFrom-Json))
    if ($LASTEXITCODE -ne 0) { throw 'Could not check LM Studio VRAM use.' }
    if ($loaded.Count -gt 0) { throw 'Unload models in LM Studio before starting Bonsai to free VRAM.' }
    & $nodeExe $bonsaiHelper start $modelKey $modelContextLength $voiceRoot
    if ($LASTEXITCODE -ne 0) { throw 'Bonsai failed to start. Check .voice-bonsai-runtime.json.log in the app folder, or close another service on port 8080.' }
    $modelEndpoint = 'http://127.0.0.1:8080/v1'
    $speechModel = 'bonsai'
} else {
& $nodeExe $bonsaiHelper stop unused 0 $voiceRoot
if ($LASTEXITCODE -ne 0) { throw 'Could not release the Bonsai server. Check port 8080 before loading another model.' }
Set-Content -LiteralPath $statusPath -Value 'Starting LM Studio...' -Encoding UTF8
& $lmsExe server start | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'LM Studio server did not start.' }
$loaded = @((& $lmsExe ps --json | ConvertFrom-Json))
if ($LASTEXITCODE -ne 0) { throw 'Could not check loaded models.' }
# OpenCode's agent prompt (system prompt + tool schemas) is ~9k tokens before the
# user's request, so LM Studio's default 8192 context makes every agent task fail
# with "exceeds the available context size". Load with a larger window, and reload
# if the model is already loaded with a smaller one.
$existing = $loaded | Where-Object modelKey -EQ $modelKey | Select-Object -First 1
$existingContext = 0
if ($existing -and $existing.PSObject.Properties['contextLength']) { $existingContext = [int]$existing.contextLength }
if ($existing -and $existingContext -lt $modelContextLength) {
    Set-Content -LiteralPath $statusPath -Value 'Reloading local model with a larger context...' -Encoding UTF8
    & $lmsExe unload $modelKey | Out-Null
    $existing = $null
}
if (-not $existing) {
    Set-Content -LiteralPath $statusPath -Value 'Loading local model...' -Encoding UTF8
    & $lmsExe load $modelKey -y --context-length $modelContextLength | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The selected model did not load.' }
}

}

if (-not (Get-Listener 8765)) {
    Set-Content -LiteralPath $statusPath -Value 'Starting local speech...' -Encoding UTF8
    $speechArgs = @('serve', '--device', 'cpu', '--stt', 'parakeet-tdt', '--llm_backend', 'chat-completions', '--model_name', $speechModel, '--responses_api_base_url', $modelEndpoint, '--responses_api_api_key', 'lm-studio', '--tts', 'pocket')
    # The in-app "Voice" picker writes .selected-voice: a Pocket TTS preset name or the
    # bare file name of a clip in the voices folder. Keep in step with desktop/src/local-model-switch.mjs.
    $voiceFile = Join-Path $voiceRoot '.selected-voice'
    if (Test-Path -LiteralPath $voiceFile) {
        $voice = (Get-Content -LiteralPath $voiceFile -Raw).Trim()
        if ($voice -and $voice -notmatch '[\\/]') {
            $voiceClip = Join-Path (Join-Path $voiceRoot 'voices') $voice
            if (Test-Path -LiteralPath $voiceClip) { $speechArgs += @('--pocket_tts_voice', $voiceClip) }
            elseif ($voice -match '^[a-z]+$') { $speechArgs += @('--pocket_tts_voice', $voice) }
        }
    }
    $speechArgs += @('--responses_api_disable_thinking', 'false', '--no_smart_turn')
    Start-Process -FilePath $speechExe -ArgumentList $speechArgs -WorkingDirectory $voiceRoot -WindowStyle Hidden
}
for ($i = 0; $i -lt 120 -and -not (Get-Listener 8765); $i++) { Start-Sleep -Seconds 1 }
if (-not (Get-Listener 8765)) { throw 'The local speech service did not start.' }

# The old browser shortcut owns a separate gateway on this port. Release only
# that known process so the desktop app owns its gateway and can switch models.
$oldGateway = Get-Listener 3101
if ($oldGateway) {
    $oldProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $($oldGateway.OwningProcess)"
    if (-not $oldProcess -or $oldProcess.CommandLine -notmatch 'node_modules[\\/]qwen-audio-agent[\\/]server[\\/]src[\\/]index\.mjs') {
        throw 'Another app owns the Qwen gateway. Close it before starting this desktop app.'
    }
    Stop-Process -Id $oldGateway.OwningProcess -Force
    for ($i = 0; $i -lt 30 -and (Get-Listener 3101); $i++) { Start-Sleep -Milliseconds 500 }
    if (Get-Listener 3101) { throw 'The old Qwen gateway did not stop.' }
}

$env:QWEN_AUDIO_LOCAL_VOICE_ROOT = $voiceRoot
$env:QWEN_AUDIO_OPEN_CONVERSATION_ON_START = '1'
$env:OPENCODE_RUNTIME = 'binary'
$env:OPENCODE_BIN = $opencodeBin
Set-Content -LiteralPath $statusPath -Value 'Opening voice app...' -Encoding UTF8
Start-Process -FilePath $appExe -WorkingDirectory (Split-Path -Parent $appExe)
Set-Content -LiteralPath $statusPath -Value 'App launch requested.' -Encoding UTF8
