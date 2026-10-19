<#
Instalador do Jarvis (OpenJarvis) com a voz pm_alex em portugues.

Uso (PowerShell, nao precisa ser administrador):
  irm https://raw.githubusercontent.com/ezequiaslucas6-rgb/OpenJarvis/main/instalar-jarvis.ps1 | iex

O que faz:
  1. Instala as ferramentas de compilacao da Microsoft (MSVC), se faltarem.
  2. Roda o instalador oficial (deploy/windows/install.ps1) usando ESTE
     repositorio: instala Python, Git, uv, Ollama, um modelo inicial e o
     comando `jarvis`.
  3. Instala o espeak-ng e o pacote de voz (Kokoro).
  4. Copia a configuracao da voz pm_alex para ~/.openjarvis/config.toml.
  5. Roda `jarvis doctor`.

Mensagens sem acento de proposito: o PowerShell 5.1 do Windows pode
embaralhar acentos em scripts.
#>

$ErrorActionPreference = 'Stop'
$repo = 'https://github.com/ezequiaslucas6-rgb/OpenJarvis'
$raw  = 'https://raw.githubusercontent.com/ezequiaslucas6-rgb/OpenJarvis/main'

function Passo ($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok    ($msg) { Write-Host "[ok]   $msg" -ForegroundColor Green }
function Aviso ($msg) { Write-Host "[aviso] $msg" -ForegroundColor Yellow }
function Falha ($msg) {
    Write-Host "[erro] $msg" -ForegroundColor Red
    throw [System.InvalidOperationException]::new([string] $msg)
}

function Update-PathFromRegistry {
    $m = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = [System.Environment]::ExpandEnvironmentVariables("$m;$u")
}

function Test-Msvc {
    if (-not ${env:ProgramFiles(x86)}) { return $false }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return $false }
    $found = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -find 'VC\Tools\MSVC\**\bin\Host*\*\link.exe' 2>$null
    return [bool]($found | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Falha "winget nao encontrado. Instale o 'App Installer' pela Microsoft Store e rode de novo."
}

# ---------------------------------------------------------------------------
Passo "1/5 Ferramentas de compilacao da Microsoft (MSVC)"
if (Test-Msvc) {
    Ok "MSVC ja instalado"
} else {
    Aviso "Vai baixar alguns GB e o Windows vai pedir permissao (clique Sim). Pode demorar."
    & winget install --id Microsoft.VisualStudio.2022.BuildTools --accept-source-agreements --accept-package-agreements `
        --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    if (-not (Test-Msvc)) {
        Falha "MSVC nao ficou instalado. Reinicie o PC e rode este comando de novo."
    }
    Ok "MSVC instalado"
}

# ---------------------------------------------------------------------------
Passo "2/5 Instalador oficial do OpenJarvis (usando o seu repositorio)"
$env:OPENJARVIS_REPO_URL     = "$repo.git"
$env:OPENJARVIS_SKIP_SERVICE = '1'
$oficial = Join-Path $env:TEMP 'openjarvis-install.ps1'
Invoke-WebRequest -UseBasicParsing -Uri "$raw/deploy/windows/install.ps1" -OutFile $oficial
& powershell -NoProfile -ExecutionPolicy Bypass -File $oficial -SkipService
if ($LASTEXITCODE -ne 0) { Falha "O instalador oficial falhou. Copie as linhas vermelhas acima e mande para o Claude." }
Update-PathFromRegistry
$src = Join-Path $env:LOCALAPPDATA 'OpenJarvis\src'
if (-not (Test-Path (Join-Path $src 'pyproject.toml'))) { Falha "Codigo nao encontrado em $src" }
Ok "OpenJarvis instalado em $src"

# ---------------------------------------------------------------------------
Passo "3/5 Voz: espeak-ng + Kokoro"
if (-not (Test-Path "$env:ProgramFiles\eSpeak NG\espeak-ng.exe") -and -not (Get-Command espeak-ng -ErrorAction SilentlyContinue)) {
    & winget install --id eSpeak-NG.eSpeak-NG --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & winget install --name espeak-ng --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    }
    Update-PathFromRegistry
    if ((Test-Path "$env:ProgramFiles\eSpeak NG\espeak-ng.exe") -or (Get-Command espeak-ng -ErrorAction SilentlyContinue)) {
        Ok "espeak-ng instalado"
    } else {
        Aviso "Nao consegui instalar o espeak-ng. Baixe o .msi em https://github.com/espeak-ng/espeak-ng/releases e instale."
    }
} else {
    Ok "espeak-ng ja instalado"
}
Push-Location $src
try {
    & uv sync --extra desktop --group desktop-native --extra voice
    if ($LASTEXITCODE -ne 0) { Falha "uv sync com o pacote de voz falhou. Copie o erro acima e mande para o Claude." }
} finally { Pop-Location }
Ok "Pacote de voz instalado"

# ---------------------------------------------------------------------------
Passo "4/5 Configurando a voz pm_alex"
$cfgDir = Join-Path $HOME '.openjarvis'
$cfg    = Join-Path $cfgDir 'config.toml'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
$voz = Join-Path $src 'configs\openjarvis\examples\voz-pm-alex.toml'
if (Test-Path $cfg) {
    Copy-Item $cfg "$cfg.bak" -Force
    if (Select-String -Path $cfg -Pattern '^\s*\[speech\]' -Quiet) {
        Aviso "Ja existe [speech] em $cfg. Ajuste voice_id = ""pm_alex"" la manualmente (backup em config.toml.bak)."
    } else {
        Add-Content -Path $cfg -Value ("`n" + (Get-Content $voz -Raw))
        Ok "Voz adicionada ao seu config.toml (backup em config.toml.bak)"
    }
} else {
    Copy-Item $voz $cfg
    Ok "Config criado em $cfg"
}

# ---------------------------------------------------------------------------
Passo "5/5 Verificando"
$jarvis = Join-Path $env:LOCALAPPDATA 'OpenJarvis\bin\jarvis.cmd'
& $jarvis doctor

Write-Host ""
Ok "Pronto! Feche e abra o PowerShell e digite:  jarvis"
Write-Host "   Na primeira fala o Kokoro baixa o modelo de voz (~330 MB)." -ForegroundColor Gray
