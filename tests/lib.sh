#!/usr/bin/env bash
# Biblioteca mínima de testes do gsb (sem dependências externas).
#
# Cada arquivo tests/t*.sh carrega esta biblioteca, chama "caixa_de_areia"
# e usa as afirmações abaixo. Os testes NUNCA tocam no que já existe no
# servidor: log, trava e configuração ficam numa pasta temporária.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # usado pelos arquivos de teste que carregam esta biblioteca
GSB="$REPO/gsb.sh"

_T_OK=0
_T_FALHA=0
_T_CASO=""

# Começa um caso de teste (só para identificar nas mensagens)
caso() { _T_CASO="$*"; }

_passou() { _T_OK=$((_T_OK + 1)); printf '  \033[0;32mok\033[0m    %s\n' "$_T_CASO${1:+ - $1}"; }
_falhou() { _T_FALHA=$((_T_FALHA + 1)); printf '  \033[0;31mFALHA\033[0m %s\n' "$_T_CASO${1:+ - $1}"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/          /' | head -20; }

# igual <esperado> <obtido> [descrição]
igual() {
    if [ "$1" == "$2" ]; then _passou "${3:-}"; else _falhou "${3:-}" "esperado: [$1]"$'\n'"obtido:   [$2]"; fi
}

# contem <texto> <saída> [descrição]
contem() {
    if [[ "$2" == *"$1"* ]]; then _passou "${3:-}"; else _falhou "${3:-}" "não contém: [$1]"$'\n'"saída: $2"; fi
}

# nao_contem <texto> <saída> [descrição]
nao_contem() {
    if [[ "$2" != *"$1"* ]]; then _passou "${3:-}"; else _falhou "${3:-}" "não deveria conter: [$1]"$'\n'"saída: $2"; fi
}

# verdadeiro <descrição> <comando...>
verdadeiro() {
    local d="$1"; shift
    if "$@"; then _passou "$d"; else _falhou "$d" "comando falhou: $*"; fi
}

# Pasta temporária com configuração própria (log, trava e backups dentro dela)
caixa_de_areia() {
    AREIA=$(mktemp -d /tmp/gsb-teste.XXXXXX)
    chmod 755 "$AREIA"
    cat > "$AREIA/gsb.conf" <<EOF
LOG=$AREIA/gsb.log
TRAVA=$AREIA/gsb.lock
BACKUP_DIR=$AREIA/backups
EOF
    chmod 644 "$AREIA/gsb.conf"
    export GSB_CONF_ARQUIVO="$AREIA/gsb.conf"
    export NO_COLOR=1
    trap 'rm -rf -- "$AREIA"' EXIT
}

# Tira cores e \r de uma saída
limpa() { sed 's/\r//g; s/\x1b\[[0-9;]*[a-zA-Z]//g'; }

# Roda o gsb num terminal simulado enviando as entradas com pausa
# (como uma pessoa digitando). Uso: pty <atraso> <comando> [entradas...]
pty() {
    local atraso="$1" cmd="$2" l
    shift 2
    { for l in "$@"; do sleep "$atraso"; printf '%s\n' "$l"; done; sleep 1; } \
        | timeout 60 script -qec "$cmd" /dev/null 2>&1 | limpa
}

# Mostra o resumo e define o código de saída do arquivo de teste
resumo() {
    echo "  ── $(basename "$0"): $_T_OK ok, $_T_FALHA falha(s)"
    [ "$_T_FALHA" -eq 0 ]
}
