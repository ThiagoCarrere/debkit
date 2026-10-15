#!/usr/bin/env bash
# Biblioteca mínima de testes do debkit (sem dependências externas).
#
# Cada arquivo tests/t*.sh carrega esta biblioteca, chama "caixa_de_areia"
# e usa as afirmações abaixo. Os testes NUNCA tocam no que já existe no
# servidor: log, trava e configuração ficam numa pasta temporária.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # usado pelos arquivos de teste que carregam esta biblioteca
DEBKIT="$REPO/debkit.sh"

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

# verdadeiro <descrição> <comando...>  (a saída do comando é descartada)
verdadeiro() {
    local d="$1"; shift
    if "$@" >/dev/null 2>&1; then _passou "$d"; else _falhou "$d" "comando falhou: $*"; fi
}

# Grupo de teste (nunca o debkit_usuarios real)
GRUPO_TESTE="dkt_usuarios"

# Pasta temporária com configuração própria. TUDO que o debkit pode alterar
# aponta para dentro dela: log, trava, backups, uma CÓPIA do smb.conf, o
# arquivo de compartilhamentos e um grupo de teste. Assim nenhum teste
# consegue mexer no Samba real, nem respondendo "s" ao assistente.
caixa_de_areia() {
    AREIA=$(mktemp -d /tmp/debkit-teste.XXXXXX)
    chmod 755 "$AREIA"
    if [ -f /etc/samba/smb.conf ]; then
        cp -p /etc/samba/smb.conf "$AREIA/smb.conf"
    else
        printf '[global]\n   server role = standalone server\n' > "$AREIA/smb.conf"
    fi
    {
        echo "LOG=$AREIA/debkit.log"
        echo "TRAVA=$AREIA/debkit.lock"
        echo "BACKUP_DIR=$AREIA/backups"
        echo "SMB_CONF=$AREIA/smb.conf"
        echo "SHARES_CONF=$AREIA/debkit-shares.conf"
        echo "GRUPO_USUARIOS=$GRUPO_TESTE"
        # Fora do Include do sshd_config real: a proteção SSH nunca é
        # aplicada no SSH de verdade pelos testes comuns
        echo "SSH_DROPIN=$AREIA/sshd_debkit.conf"
    } > "$AREIA/debkit.conf"
    chmod 644 "$AREIA/debkit.conf"
    export DEBKIT_CONF_ARQUIVO="$AREIA/debkit.conf"
    export NO_COLOR=1
    trap 'rm -rf -- "${AREIA:?}"; getent group "$GRUPO_TESTE" >/dev/null && groupdel "$GRUPO_TESTE"' EXIT
}

# Prepara o ambiente DA AREIA (para testar o menu sem cair no assistente)
preparar_areia() {
    printf 's\n' | bash "$DEBKIT" --preparar >/dev/null 2>&1
}

# Tira cores e \r de uma saída
limpa() { sed 's/\r//g; s/\x1b\[[0-9;]*[a-zA-Z]//g'; }

# Roda o debkit num terminal simulado enviando as entradas com pausa
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
