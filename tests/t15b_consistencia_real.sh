#!/usr/bin/env bash
# Prova REAL de "verificar e corrigir contas" com o SSH e o Samba de verdade.
#
# ATENÇÃO: cria dois usuários de teste no Linux (e um na base REAL do
# Samba) fora do padrão e corrige pelo debkit, com a configuração real:
#   - shell sem login fora do grupo de proteção: o SSH aceita a senha;
#     depois da correção, recusa;
#   - usuário só no Linux: o Samba não o reconhece; depois, reconhece.
# Por isso só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t15b_consistencia_real.sh
# Ao final os usuários e as contas Samba de teste são removidos.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o SSH e o Samba reais - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

TUN=dkt_ctun; LIN=dkt_clin; SENHA="Consist#Teste1"
for x in "$TUN" "$LIN"; do
    if getent passwd "$x" >/dev/null || getent group "$x" >/dev/null || pdbedit -u "$x" >/dev/null 2>&1; then echo "  $x já existe - abortando"; exit 1; fi
done
limpar_real() {
    local x i
    exec 4>&- 2>/dev/null
    pkill -u "$TUN" 2>/dev/null; pkill -u "$LIN" 2>/dev/null
    for (( i = 0; i < 20; i++ )); do pgrep -u "$TUN,$LIN" >/dev/null 2>&1 || break; sleep 0.5; done
    for x in "$TUN" "$LIN"; do
        pdbedit -u "$x" >/dev/null 2>&1 && smbpasswd -x "$x" >/dev/null 2>&1
        id "$x" >/dev/null 2>&1 && userdel "$x"
        getent group "$x" >/dev/null && groupdel "$x"
    done
    rm -rf -- "${SANDBOX:?}"
}
trap limpar_real EXIT
trap '' PIPE

( umask 027; : > "$SANDBOX/debkit.log" )
s() { env -u DEBKIT_APT -u DEBKIT_DPKG_ADMIN bash -c "source '$DEBKIT'; debkit_conf_carregar /etc/debkit/debkit.conf >/dev/null; debkit_ler_login_defs; DEBKIT_LOG='$SANDBOX/debkit.log'; $1" 2>&1; }
SSH_OPCOES=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no
            -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 -o ConnectTimeout=5 -o LogLevel=ERROR)
ssh_tentar() {
    printf '#!/bin/sh\necho "%s"\n' "$SENHA" > "$SANDBOX/askpass"; chmod 700 "$SANDBOX/askpass"
    SSH_ASKPASS="$SANDBOX/askpass" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
        timeout 20 setsid -w ssh "${SSH_OPCOES[@]}" "$1@127.0.0.1" true </dev/null 2>&1
    echo "RC=$?"
}
# Usuários das sessões abertas no Samba ao entrar com <usuário> (ver t14b)
quem_entra() {
    printf 'username = %s\npassword = %s\n' "$1" "$SENHA" > "$SANDBOX/auth"; chmod 600 "$SANDBOX/auth"
    rm -f "$SANDBOX/q"; mkfifo "$SANDBOX/q"
    ( timeout 20 smbclient '//127.0.0.1/IPC$' -A "$SANDBOX/auth" < "$SANDBOX/q" > /dev/null 2>&1 ) &
    local pid=$!
    exec 4> "$SANDBOX/q"; echo "help" >&4; sleep 2
    LC_ALL=C smbstatus -p 2>/dev/null | awk '$1 ~ /^[0-9]+$/ {print $2}' | sort -u
    echo "quit" >&4; exec 4>&-; wait "$pid" 2>/dev/null
}

caso "ambiente real preparado pelo debkit"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
_passou "pronto"

# Fora do padrão, feitos à mão (como num servidor antigo)
useradd -M -s /usr/sbin/nologin "$TUN"; printf '%s:%s\n' "$TUN" "$SENHA" | chpasswd
useradd -M -s /bin/bash "$LIN"; printf '%s:%s\n' "$LIN" "$SENHA" | chpasswd
caso "detecção com a configuração real"
saida=$(s "debkit_samba_inconsistencias")
contem "tunel|$TUN" "$saida"; contem "so_linux|$LIN" "$saida"

caso "túnel: antes da correção o SSH aceita a senha (só o nologin barra o shell)"
saida=$(ssh_tentar "$TUN")
nao_contem "Permission denied" "$saida" "autenticou"; contem "Could not chdir to home directory" "$saida" "a sessão SSH chegou a abrir"
caso "túnel: corrigido pelo debkit, o SSH recusa"
contem "RC=0" "$(s "debkit_consist_tunel $TUN; echo RC=\$?")"
contem "debkit_usuarios" "$(id -nG "$TUN")"
contem "Permission denied" "$(ssh_tentar "$TUN")"

caso "só no Linux: antes, o Samba não reconhece o usuário (vira convidado)"
nao_contem "$LIN" "$(quem_entra "$LIN")"
caso "só no Linux: corrigido pelo debkit, o Samba reconhece com a senha nova"
contem "RC=0" "$(s "DEBKIT_U_SENHA='$SENHA'; debkit_consist_so_linux $LIN; echo RC=\$?")"
contem "$LIN" "$(quem_entra "$LIN")"
verdadeiro "conta na base real" pdbedit -u "$LIN"

limpar_real; trap - EXIT
caso "limpeza"
verdadeiro "usuários de teste removidos" bash -c "! id $TUN && ! id $LIN"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
nao_contem "dkt_" "$(getent group debkit_usuarios)"
resumo
