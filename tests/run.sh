#!/usr/bin/env bash
# Roda todos os testes do gsb (tests/t*.sh). Precisa ser root.
# Uso: tests/run.sh [arquivo_de_teste ...]

cd "$(dirname "$0")" || exit 1
[ "$EUID" -eq 0 ] || { echo "Os testes precisam ser executados como root." >&2; exit 1; }

arquivos=("$@")
[ ${#arquivos[@]} -eq 0 ] && arquivos=(t*.sh)

falhas=0
for t in "${arquivos[@]}"; do
    echo "▶ $t"
    bash "$t" || falhas=$((falhas + 1))
    echo ""
done

if [ "$falhas" -eq 0 ]; then
    echo "TODOS OS TESTES PASSARAM (${#arquivos[@]} arquivo(s))"
else
    echo "$falhas ARQUIVO(S) COM FALHA"
    exit 1
fi
