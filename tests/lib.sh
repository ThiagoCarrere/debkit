#!/usr/bin/env bash
# Biblioteca mínima de testes do debkit (sem dependências externas).
#
# Cada arquivo tests/t*.sh carrega esta biblioteca, chama "sandbox"
# e usa as afirmações abaixo. Os testes NUNCA tocam no que já existe no
# servidor: log, trava e configuração ficam numa pasta temporária.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034  # usado pelos arquivos de teste que carregam esta biblioteca
DEBKIT="$REPO/debkit"

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

# Arquivos REAIS do debkit no servidor. Podem existir (servidor já
# preparado pelo debkit) ou não; os testes só exigem que não mudem.
ARQUIVOS_REAIS=(/etc/debkit /etc/debkit/debkit.conf /var/log/debkit.log /run/debkit.lock
                /etc/samba/smb.conf /etc/samba/debkit-shares.conf /etc/samba/conf-bkp
                /etc/ssh/sshd_config.d/debkit.conf /var/backups/debkit /etc/logrotate.d/debkit-samba-auth)

# Uma linha por arquivo real: "caminho conteúdo/permissão" ou "caminho ausente"
estado_real() {
    local p
    for p in "${ARQUIVOS_REAIS[@]}"; do
        if [ -d "$p" ]; then
            echo "$p dir $(stat -c '%a %u:%g' "$p") $(ls -A "$p" | md5sum)"
        elif [ -e "$p" ]; then
            echo "$p $(stat -c '%a %u:%g' "$p") $(md5sum < "$p")"
        else
            echo "$p ausente"
        fi
    done
}

# Afirmação: nenhum arquivo real do debkit mudou desde a sandbox
real_intacto() {
    caso "nada fora do sandbox"
    igual "$_ESTADO_REAL_INICIO" "$(estado_real)" "arquivos reais do debkit iguais ao início"
}

# Cópia do smb.conf real para <destino>, SEM as linhas do "include" antigo
# do debkit (marca + include): elas apontam para o arquivo REAL, que a
# preparação removeria. Os testes do include antigo montam o seu, no sandbox.
# A base de senhas e as pastas de estado do Samba apontam para <destino>.samba/
# (logo depois do [global]): um smbpasswd/pdbedit de teste NUNCA grava na
# base real.
copiar_smb_conf() {
    local base="$1.samba"
    mkdir -p "$base/private" "$base/state" "$base/lock" "$base/cache"
    if [ -f /etc/samba/smb.conf ]; then
        awk '$0 == "# debkit - Gerenciador Samba: compartilhamentos do debkit (não remova esta linha)" { pula = 1; next }
             pula && /^[ \t]*include[ \t]*=/ { pula = 0; next } { pula = 0; print }' /etc/samba/smb.conf > "$1"
        chmod --reference=/etc/samba/smb.conf "$1"
    else
        printf '[global]\n   server role = standalone server\n' > "$1"
    fi
    isolar_smb_conf "$1"
    # Log de autenticação (tarefa 3.0) como no servidor real, mas no sandbox:
    # log e regra do logrotate ao lado da cópia
    local d
    d=$(dirname -- "$1")
    sed -i "s|auth_json_audit:3@/var/log/samba/debkit-auth.json|auth_json_audit:3@$d/debkit-auth.json|" "$1"
    rm -f -- "$d/logrotate-debkit-samba-auth"
    if [ -f /etc/logrotate.d/debkit-samba-auth ]; then
        sed "s|/var/log/samba/debkit-auth.json|$d/debkit-auth.json|" /etc/logrotate.d/debkit-samba-auth > "$d/logrotate-debkit-samba-auth"
    fi
}

# Faz o smb.conf <arquivo> usar a base de senhas e as pastas do Samba em
# <arquivo>.samba/ (insere logo depois do primeiro [global]; cria o
# [global] se não houver)
isolar_smb_conf() {
    local base="$1.samba"
    mkdir -p "$base/private" "$base/state" "$base/lock" "$base/cache"
    grep -qiE '^[[:space:]]*\[global\]' "$1" || sed -i '1i [global]' "$1"
    awk -v b="$base" '!feito && tolower($0) ~ /^[ \t]*\[global\]/ {
            print; print "   passdb backend = tdbsam:" b "/passdb.tdb"; print "   private dir = " b "/private"
            print "   state directory = " b "/state"; print "   lock directory = " b "/lock"
            print "   cache directory = " b "/cache"; feito = 1; next } { print }' "$1" > "$1.tmp" && cat "$1.tmp" > "$1" && rm -f "$1.tmp"
}

# Pasta temporária com configuração própria. TUDO que o debkit pode alterar
# aponta para dentro dela: log, trava, backups, uma CÓPIA do smb.conf, os
# backups do smb.conf e um grupo de teste. Assim nenhum teste consegue
# mexer no Samba real, nem respondendo "s" ao assistente.
sandbox() {
    _ESTADO_REAL_INICIO=$(estado_real)
    SANDBOX=$(mktemp -d /tmp/debkit-teste.XXXXXX)
    chmod 755 "$SANDBOX"
    copiar_smb_conf "$SANDBOX/smb.conf"
    {
        echo "LOG=$SANDBOX/debkit.log"
        echo "TRAVA=$SANDBOX/debkit.lock"
        echo "BACKUP_DIR=$SANDBOX/backups"
        echo "SMB_CONF=$SANDBOX/smb.conf"
        echo "SMB_BACKUP_DIR=$SANDBOX/conf-bkp"
        echo "AUTH_LOG=$SANDBOX/debkit-auth.json"
        echo "AUTH_LOGROTATE=$SANDBOX/logrotate-debkit-samba-auth"
        echo "GRUPO_USUARIOS=$GRUPO_TESTE"
        # Fora do Include do sshd_config real: a proteção SSH nunca é
        # aplicada no SSH de verdade pelos testes comuns
        echo "SSH_DROPIN=$SANDBOX/sshd_debkit.conf"
    } > "$SANDBOX/debkit.conf"
    chmod 644 "$SANDBOX/debkit.conf"
    export DEBKIT_CONF_ARQUIVO="$SANDBOX/debkit.conf"
    # apt e base do dpkg do sandbox: nenhum teste instala ou remove pacote de
    # verdade (o apt do sandbox recusa tudo e anota a tentativa; a base vazia
    # = nada instalado). Testes de pacotes usam o seu apt falso.
    printf '#!/bin/sh\necho "apt-get $*" >> "%s/apt-bloqueado.log"\necho "apt bloqueado nos testes" >&2\nexit 100\n' "$SANDBOX" > "$SANDBOX/apt-bloqueado"
    chmod 755 "$SANDBOX/apt-bloqueado"
    mkdir -p "$SANDBOX/dpkg/info"; : > "$SANDBOX/dpkg/status"
    export DEBKIT_APT="$SANDBOX/apt-bloqueado" DEBKIT_DPKG_ADMIN="$SANDBOX/dpkg"
    export NO_COLOR=1
    trap 'rm -rf -- "${SANDBOX:?}"; getent group "$GRUPO_TESTE" >/dev/null && groupdel "$GRUPO_TESTE"' EXIT
}

# Prepara o ambiente DO SANDBOX (para testar o menu sem cair no assistente)
preparar_sandbox() {
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
