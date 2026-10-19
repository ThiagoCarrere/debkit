#!/usr/bin/env bash
# Prova REAL de excluir usuário com o Samba e o SSH de verdade.
#
# ATENÇÃO: cria dois usuários de teste no Linux e na base REAL do Samba
# (pelo debkit, com a configuração real), abre uma sessão no Samba e uma no
# SSH e exclui pelo debkit: a sessão do Samba é encerrada e o login passa a
# ser recusado; com o SSH aberto a exclusão é recusada (o debkit não mata o
# SSH). Por isso só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t14b_excluir_real.sh
# Precisa do ambiente real já preparado pelo debkit. Ao final não sobra
# nenhum usuário nem conta Samba de teste; o smb.conf real não é alterado.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba e o SSH reais - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
caixa_de_areia

ARQ=dkt_xarq; SRV=dkt_xsrv; SENHA="Excluir#Teste1"
for x in "$ARQ" "$SRV"; do
    if getent passwd "$x" >/dev/null || getent group "$x" >/dev/null || pdbedit -u "$x" >/dev/null 2>&1; then echo "  $x já existe - abortando"; exit 1; fi
done
MD5_SMB=$(md5sum < /etc/samba/smb.conf)

limpar_real() {
    local x i
    [ -n "${PID_SESSAO:-}" ] && kill "$PID_SESSAO" 2>/dev/null
    [ -n "${PID_SSH:-}" ] && kill "$PID_SSH" 2>/dev/null
    exec 3>&- 2>/dev/null
    pkill -u "$ARQ" 2>/dev/null; pkill -u "$SRV" 2>/dev/null
    for (( i = 0; i < 20; i++ )); do pgrep -u "$ARQ,$SRV" >/dev/null 2>&1 || break; sleep 0.5; done
    for x in "$ARQ" "$SRV"; do
        pdbedit -u "$x" >/dev/null 2>&1 && smbpasswd -x "$x" >/dev/null 2>&1
        id "$x" >/dev/null 2>&1 && userdel "$x"
        getent group "$x" >/dev/null && groupdel "$x"
    done
    rm -rf -- "${AREIA:?}"
}
trap limpar_real EXIT
trap '' PIPE

( umask 027; : > "$AREIA/debkit.log" )   # senão o plano pediria para criá-lo
s() { env -u DEBKIT_APT -u DEBKIT_DPKG_ADMIN bash -c "source '$DEBKIT'; debkit_conf_carregar /etc/debkit/debkit.conf >/dev/null; debkit_ler_login_defs; DEBKIT_LOG='$AREIA/debkit.log'; $1" 2>&1; }
smb_login() {
    printf 'username = %s\npassword = %s\n' "$1" "$SENHA" > "$AREIA/auth"; chmod 600 "$AREIA/auth"
    timeout 20 smbclient -L //127.0.0.1 -A "$AREIA/auth" 2>&1; echo "RC=$?"
}
SSH_OPCOES=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no
            -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 -o ConnectTimeout=5 -o LogLevel=ERROR)
# Com quem o Samba abre a sessão quando se entra com <usuário>? Imprime os
# usuários das sessões abertas (com "map to guest = bad user", padrão do
# Debian, quem não existe viraria convidado, nobody; a preparação do debkit
# muda para "never" e o login é recusado).
quem_entra() {
    printf 'username = %s\npassword = %s\n' "$1" "$SENHA" > "$AREIA/auth"; chmod 600 "$AREIA/auth"
    rm -f "$AREIA/q"; mkfifo "$AREIA/q"
    ( timeout 20 smbclient '//127.0.0.1/IPC$' -A "$AREIA/auth" < "$AREIA/q" > /dev/null 2>&1 ) &
    local pid=$!
    exec 4> "$AREIA/q"; echo "help" >&4; sleep 2
    LC_ALL=C smbstatus -p 2>/dev/null | awk '$1 ~ /^[0-9]+$/ {print $2}' | sort -u
    echo "quit" >&4; exec 4>&-; wait "$pid" 2>/dev/null
}
ssh_cmd() {  # ssh_cmd <usuário> <comando>
    printf '#!/bin/sh\necho "%s"\n' "$SENHA" > "$AREIA/askpass"; chmod 700 "$AREIA/askpass"
    SSH_ASKPASS="$AREIA/askpass" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
        timeout 40 setsid -w ssh "${SSH_OPCOES[@]}" "$1@127.0.0.1" "$2" </dev/null 2>&1
    echo "RC=$?"
}

caso "ambiente real preparado pelo debkit"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
_passou "pronto"

caso "criar pelo debkit: usuário de arquivos e com acesso ao servidor"
contem "RC=0" "$(s "DEBKIT_U_NOME=$ARQ; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=(); DEBKIT_U_HOME=0; DEBKIT_U_SENHA='$SENHA'; debkit_usuario_criar; echo RC=\$?")"
contem "RC=0" "$(s "DEBKIT_U_NOME=$SRV; DEBKIT_U_TIPO=servidor; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=(); DEBKIT_U_HOME=0; DEBKIT_U_SENHA='$SENHA'; DEBKIT_U_SENHA_LINUX='$SENHA'; debkit_usuario_criar; echo RC=\$?")"
contem "RC=0" "$(smb_login "$ARQ")" "login no Samba antes"

caso "usuário conectado ao Samba: a sessão é encerrada e ele é excluído"
rm -f "$AREIA/sessao"; mkfifo "$AREIA/sessao"
( timeout 60 smbclient '//127.0.0.1/IPC$' -A "$AREIA/auth" < "$AREIA/sessao" > "$AREIA/sessao.out" 2>&1 ) &
PID_SESSAO=$!
exec 3> "$AREIA/sessao"; echo "help" >&3; sleep 2
SMBD=$(s "debkit_samba_sessoes $ARQ")
verdadeiro "sessão aberta encontrada" test -n "$SMBD"
saida=$(s "debkit_usuario_excluir $ARQ; echo RC=\$?")
contem "RC=0" "$saida"; contem "1 sessão(ões) do Samba encerrada(s)" "$saida"; contem "Usuário $ARQ excluído" "$saida"
verdadeiro "o smbd da sessão acabou" bash -c "! kill -0 $SMBD"
exec 3>&-; wait "$PID_SESSAO" 2>/dev/null; PID_SESSAO=""
saida=$(quem_entra "$ARQ")
nao_contem "$ARQ" "$saida" "o Samba não autentica mais o usuário"
contem "NT_STATUS_LOGON_FAILURE" "$(smb_login "$ARQ")" "login recusado (map to guest = never, preparado pelo debkit; ver t16b)"
verdadeiro "sumiu do Linux e da base REAL do Samba" bash -c "! getent passwd $ARQ && ! pdbedit -u $ARQ && ! getent group $ARQ"
nao_contem "$ARQ" "$(getent group debkit_usuarios)" "saiu do grupo de proteção real"

caso "SSH aberto: a exclusão é recusada e nada é apagado"
( ssh_cmd "$SRV" "sleep 25" > "$AREIA/ssh.out" ) &
PID_SSH=$!
for (( i = 0; i < 20; i++ )); do pgrep -u "$SRV" >/dev/null && break; sleep 0.5; done
verdadeiro "sessão SSH aberta" pgrep -u "$SRV"
saida=$(s "debkit_usuario_excluir $SRV; echo RC=\$?")
contem "RC=1" "$saida"; contem "tem processos em execução fora do Samba" "$saida"
verdadeiro "intacto" bash -c "getent passwd $SRV && pdbedit -u $SRV"
kill "$PID_SSH" 2>/dev/null; pkill -u "$SRV"; wait "$PID_SSH" 2>/dev/null; PID_SSH=""
for (( i = 0; i < 20; i++ )); do pgrep -u "$SRV" >/dev/null || break; sleep 0.5; done
caso "SSH fechado: excluído; login no SSH e no Samba recusados"
contem "RC=0" "$(s "debkit_usuario_excluir $SRV; echo RC=\$?")"
contem "RC=255" "$(ssh_cmd "$SRV" true)" "SSH recusa"
saida=$(quem_entra "$SRV"); nao_contem "$SRV" "$saida" "Samba não autentica mais"

# ── Limpeza ──────────────────────────────────────────────────────────────────
limpar_real; trap - EXIT
caso "limpeza"
igual "$MD5_SMB" "$(md5sum < /etc/samba/smb.conf)" "smb.conf real não mudou"
verdadeiro "usuários de teste removidos" bash -c "! id $ARQ && ! id $SRV"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
resumo
