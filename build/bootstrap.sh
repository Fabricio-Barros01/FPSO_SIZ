#!/usr/bin/env bash
#
# bootstrap.sh — do zero ao executável, numa máquina Linux ou macOS.
#
#   ./build/bootstrap.sh          # pergunta antes de baixar qualquer coisa
#   ./build/bootstrap.sh --yes    # não pergunta (CI)
#   ./build/bootstrap.sh --yes deps
#
# Faz uma coisa que o build.jl não pode fazer: garantir que existe um Julia para rodar
# o build.jl. O resto é dele.

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

SIM=0
COMANDO="tudo"
for arg in "$@"; do
    case "$arg" in
        --yes|-y) SIM=1 ;;
        deps|teste|app|pacote|tudo) COMANDO="$arg" ;;
        *) echo "argumento desconhecido: $arg"; exit 2 ;;
    esac
done

echo
echo "═══ FPSO_Siz — bootstrap ($(uname -s) $(uname -m)) ═══"
echo

# ---------------------------------------------------------------------------
# 1. Julia
# ---------------------------------------------------------------------------

# Se o juliaup já instalou numa sessão anterior, o PATH desta sessão pode não saber.
[ -d "$HOME/.juliaup/bin" ] && PATH="$HOME/.juliaup/bin:$PATH"

if command -v julia >/dev/null 2>&1; then
    echo "✅ Julia encontrado: $(julia --version)"
else
    echo "⚠️  O Julia não está instalado nesta máquina."
    echo
    echo "    Posso instalá-lo com o juliaup, o instalador oficial:"
    echo "      origem:  https://install.julialang.org"
    echo "      destino: ~/.juliaup  (não precisa de administrador)"
    echo "      tamanho: ~30 MB de download"
    echo

    if [ "$SIM" -ne 1 ]; then
        read -rp "    Baixar e instalar agora? [s/N] " resposta
        case "$resposta" in
            s|S|sim|y|Y) ;;
            *) echo
               echo "    Cancelado. Instale o Julia à mão e rode este script de novo:"
               echo "      https://julialang.org/downloads/"
               exit 1 ;;
        esac
    fi

    command -v curl >/dev/null 2>&1 || {
        echo "❌ preciso do 'curl' para baixar o instalador."; exit 1; }

    curl -fsSL https://install.julialang.org | sh -s -- --yes
    PATH="$HOME/.juliaup/bin:$PATH"

    command -v julia >/dev/null 2>&1 || {
        echo "❌ o juliaup instalou, mas 'julia' não apareceu no PATH."
        echo "   Abra um terminal novo e rode este script de novo."
        exit 1; }
    echo "✅ Julia instalado: $(julia --version)"
fi

# ---------------------------------------------------------------------------
# 2. O build
# ---------------------------------------------------------------------------

echo
exec julia --startup-file=no "$RAIZ/build/build.jl" "$COMANDO"
