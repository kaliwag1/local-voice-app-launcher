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
# The live pick is machine-local and not in Git. A fresh clone or a restore has only
# the tracked seed, so fall back to it rather than refusing to start.
$selectionDefaultFile = Join-Path $voiceRoot '.selected-voice-model.default'
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
$activeSelectionFile = if (Test-Path -LiteralPath $selectionFile) { $selectionFile } else { $selectionDefaultFile }
if (-not (Test-Path -LiteralPath $activeSelectionFile)) {
    throw 'No local model has been selected yet, and .selected-voice-model.default is missing.'
}
$modelKey = (Get-Content -LiteralPath $activeSelectionFile -Raw).Trim()
if (-not $modelKey) { throw "The selected local model is empty ($activeSelectionFile)." }

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

# Settings -> Application -> Conversation writes .selected-app-mode. Text mode still starts
# the speech service - typed chat reaches the model through it - but with stand-ins for
# its speech models (speech-adapter\text_only.py), so nothing is transcribed or spoken.
$appModeFile = Join-Path $voiceRoot '.selected-app-mode'
$textMode = (Test-Path -LiteralPath $appModeFile) -and ((Get-Content -LiteralPath $appModeFile -Raw).Trim() -eq 'text')

$speechProcess = $null
if (-not (Get-Listener 8765)) {
    $sttBackend = if ($textMode) { 'text-only' } else { 'parakeet-tdt' }
    $ttsBackend = if ($textMode) { 'text-only' } else { 'pocket' }
    Set-Content -LiteralPath $statusPath -Value $(if ($textMode) { 'Starting local chat (text only)...' } else { 'Starting local speech...' }) -Encoding UTF8
    $speechArgs = @('serve', '--device', 'cpu', '--stt', $sttBackend, '--llm_backend', 'chat-completions', '--model_name', $speechModel, '--responses_api_base_url', $modelEndpoint, '--responses_api_api_key', 'lm-studio', '--tts', $ttsBackend)
    # The in-app "Voice" picker writes .selected-voice: a Pocket TTS preset name or the
    # bare file name of a clip in the voices folder. Keep in step with desktop/src/local-model-switch.mjs.
    $voiceFile = Join-Path $voiceRoot '.selected-voice'
    if (-not $textMode -and (Test-Path -LiteralPath $voiceFile)) {
        $voice = (Get-Content -LiteralPath $voiceFile -Raw).Trim()
        if ($voice -and $voice -notmatch '[\\/]') {
            $voiceClip = Join-Path (Join-Path $voiceRoot 'voices') $voice
            if (Test-Path -LiteralPath $voiceClip) { $speechArgs += @('--pocket_tts_voice', $voiceClip) }
            elseif ($voice -match '^[a-z]+$') { $speechArgs += @('--pocket_tts_voice', $voice) }
        }
    }
    $speechArgs += @('--responses_api_disable_thinking', 'false', '--no_smart_turn')
    # Stderr only: stdout carries the spoken transcript and replies, which stay unlogged.
    $speechProcess = Start-Process -FilePath $speechExe -ArgumentList $speechArgs -WorkingDirectory $voiceRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardError (Join-Path $voiceRoot 'Last Speech Service.log')
    # Holding the handle keeps ExitCode readable once it exits; without it PowerShell reports none.
    $null = $speechProcess.Handle
}
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

# Speech takes 25-50 s to load and the app needs none of it to open, so it is no longer
# waited for before the app starts: the Gateway retries the speech link (backing off to
# ~10 s) until it answers. A service that never comes up is still reported here, and one
# that has already exited is reported at once rather than after the full two minutes.
for ($i = 0; $i -lt 120 -and -not (Get-Listener 8765); $i++) {
    if ($speechProcess -and $speechProcess.HasExited) {
        throw "The local speech service stopped while starting (exit code $($speechProcess.ExitCode)). See Last Speech Service.log."
    }
    Start-Sleep -Seconds 1
}
if (-not (Get-Listener 8765)) { throw 'The local speech service did not start. See Last Speech Service.log.' }
Set-Content -LiteralPath $statusPath -Value 'Speech ready.' -Encoding UTF8
