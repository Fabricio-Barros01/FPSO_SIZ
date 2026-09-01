<#
    bootstrap.ps1 — do zero ao executável, numa máquina Windows.

        .\build\bootstrap.ps1              # pergunta antes de baixar qualquer coisa
        .\build\bootstrap.ps1 -Yes         # não pergunta (CI)
        .\build\bootstrap.ps1 -Yes deps

    Se o PowerShell recusar por política de execução, rode uma vez:

        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

    Faz uma coisa que o build.jl não pode fazer: garantir que existe um Julia para
    rodar o build.jl. O resto é dele.
#>

[CmdletBinding()]
param(
    [switch]$Yes,
    [ValidateSet('deps', 'teste', 'app', 'pacote', 'tudo')]
    [string]$Comando = 'tudo'
)

$ErrorActionPreference = 'Stop'
$Raiz = Split-Path -Parent $PSScriptRoot
Set-Location $Raiz

Write-Host ''
Write-Host "═══ FPSO_Siz — bootstrap (Windows $env:PROCESSOR_ARCHITECTURE) ═══"
Write-Host ''

# ---------------------------------------------------------------------------
# 1. Julia
# ---------------------------------------------------------------------------

# O juliaup instala aqui; uma sessão aberta antes da instalação não conhece o caminho.
$JuliaupBin = Join-Path $env:USERPROFILE '.julia\juliaup\bin'
if (Test-Path $JuliaupBin) { $env:PATH = "$JuliaupBin;$env:PATH" }

$julia = Get-Command julia -ErrorAction SilentlyContinue

if ($julia) {
    Write-Host "OK  Julia encontrado: $(julia --version)"
} else {
    Write-Host "!!  O Julia nao esta instalado nesta maquina."
    Write-Host ''
    Write-Host '    Posso instala-lo com o juliaup, o instalador oficial:'
    Write-Host '      origem:  https://install.julialang.org'
    Write-Host '      destino: %USERPROFILE%\.julia\juliaup  (nao precisa de administrador)'
    Write-Host '      tamanho: ~30 MB de download'
    Write-Host ''

    if (-not $Yes) {
        $resposta = Read-Host '    Baixar e instalar agora? [s/N]'
        if ($resposta -notmatch '^(s|sim|y|yes)$') {
            Write-Host ''
            Write-Host '    Cancelado. Instale o Julia a mao e rode este script de novo:'
            Write-Host '      https://julialang.org/downloads/'
            exit 1
        }
    }

    # O instalador oficial para Windows é um script PowerShell servido pelo mesmo host.
    Invoke-RestMethod https://install.julialang.org -OutFile "$env:TEMP\install-julia.ps1"
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\install-julia.ps1" --yes

    if (Test-Path $JuliaupBin) { $env:PATH = "$JuliaupBin;$env:PATH" }
    if (-not (Get-Command julia -ErrorAction SilentlyContinue)) {
        Write-Host 'ERRO  o juliaup instalou, mas "julia" nao apareceu no PATH.'
        Write-Host '      Abra um PowerShell novo e rode este script de novo.'
        exit 1
    }
    Write-Host "OK  Julia instalado: $(julia --version)"
}

# ---------------------------------------------------------------------------
# 2. O build
# ---------------------------------------------------------------------------

Write-Host ''
& julia --startup-file=no (Join-Path $Raiz 'build\build.jl') $Comando
exit $LASTEXITCODE
