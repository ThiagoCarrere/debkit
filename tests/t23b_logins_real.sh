#!/usr/bin/env bash
# Prova REAL dos logins (Fase 3, tarefa 3.2) com o Samba de verdade.
#
# ATENÇÃO: cria usuários e um grupo de teste (Linux e base REAL do Samba,
# pelo debkit) e um compartilhamento no smb.conf REAL (pasta em
# /srv/dkt-teste.*; recarrega o smbd); faz logins de verdade (sucesso,
# senha errada, usuário inexistente, conta desativada), que ficam no log de
# autenticação real, e confere a leitura pelo debkit. Por isso só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t23b_logins_real.sh
# Ao final o smb.conf real volta idêntico (e é recarregado), e os usuários,
# as contas Samba, o grupo e a pasta são removidos.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

UA=dkt_la; UB=dkt_lb; GA=dkt_lga; GB=dkt_lgb; SHARE=dkt-teste-log; SENHA="Log#Teste1"
for x in "$UA" "$UB" "$GA" "$GB"; do
    if getent passwd "$x" >/dev/null || getent group "$x" >/dev/null || pdbedit -u "$x" >/dev/null 2>&1; then echo "  $x já existe - abortando"; exit 1; fi
done
T=$(mktemp -d /srv/dkt-teste.XXXXXX); chmod 755 "$T"
SMB_ANTES="$SANDBOX/smb.conf.real"; cp -p /etc/samba/smb.conf "$SMB_ANTES"; MD5_ANTES=$(md5sum < /etc/samba/smb.conf)
limpar_real() {
    local x i
    [ -n "${PID_SESSAO:-}" ] && kill "$PID_SESSAO" 2>/dev/null
    exec 3>&- 2>/dev/null
    pkill -u "$UA" 2>/dev/null; pkill -u "$UB" 2>/dev/null
    for (( i = 0; i < 20; i++ )); do pgrep -u "$UA,$UB" >/dev/null 2>&1 || break; sleep 0.5; done
    for x in "$UA" "$UB"; do
        pdbedit -u "$x" >/dev/null 2>&1 && smbpasswd -x "$x" >/dev/null 2>&1
        id "$x" >/dev/null 2>&1 && userdel "$x"
        getent group "$x" >/dev/null && groupdel "$x"
    done
    for x in "$GA" "$GB"; do getent group "$x" >/dev/null && groupdel "$x"; done
    if [ "$(md5sum < /etc/samba/smb.conf)" != "$MD5_ANTES" ]; then
        cat "$SMB_ANTES" > /etc/samba/smb.conf
        systemctl reload smbd
    fi
    rm -rf -- "${T:?}" "${SANDBOX:?}"
}
trap limpar_real EXIT

( umask 027; : > "$SANDBOX/debkit.log" ); ( umask 077; mkdir -p "$SANDBOX/backups" )
# Configuração REAL; log e backups do smb.conf só nesta execução
s() { env -u DEBKIT_APT -u DEBKIT_DPKG_ADMIN bash -c "source '$DEBKIT'; debkit_conf_carregar /etc/debkit/debkit.conf >/dev/null; debkit_ler_login_defs;
      DEBKIT_LOG='$SANDBOX/debkit.log'; DEBKIT_SMB_BACKUP_DIR='$SANDBOX/conf-bkp'; DEBKIT_BACKUP_DIR='$SANDBOX/backups'; $1" 2>&1; }
smb() {  # smb <usuário> <comandos>
    printf 'username = %s\npassword = %s\n' "$1" "$SENHA" > "$SANDBOX/auth.$1"; chmod 600 "$SANDBOX/auth.$1"
    ( cd "$SANDBOX" && timeout 20 smbclient "//127.0.0.1/$SHARE" -A "$SANDBOX/auth.$1" -c "$2" 2>&1 ); echo "RC=$?"
}
# Sessão aberta (smbclient lendo comandos de um fifo)
trap '' PIPE
abrir() {
    rm -f "$SANDBOX/sessao"; mkfifo "$SANDBOX/sessao"
    printf 'username = %s\npassword = %s\n' "$1" "$SENHA" > "$SANDBOX/auth.$1"; chmod 600 "$SANDBOX/auth.$1"
    ( cd "$SANDBOX" && timeout 60 smbclient "//127.0.0.1/$SHARE" -A "$SANDBOX/auth.$1" < "$SANDBOX/sessao" > "$SANDBOX/sessao.out" 2>&1 ) &
    PID_SESSAO=$!
    exec 3> "$SANDBOX/sessao"
}
enviar() { echo "$1" >&3 2>/dev/null; sleep 2; }
fechar() { echo "quit" >&3 2>/dev/null; exec 3>&-; wait "$PID_SESSAO" 2>/dev/null; PID_SESSAO=""; }

X=dkt_lx_naoexiste
errada() {  # errada <usuário>: tenta entrar com a senha errada
    printf 'username = %s\npassword = Errada#Teste9\n' "$1" > "$SANDBOX/auth.err"; chmod 600 "$SANDBOX/auth.err"
    timeout 20 smbclient "//127.0.0.1/$SHARE" -A "$SANDBOX/auth.err" -c ls >/dev/null 2>&1; echo "RC=$?"
}

caso "ambiente real preparado pelo debkit (log de autenticação ligado)"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
verdadeiro "log ligado no smb.conf real" s debkit_samba_auth_ligado

caso "usuários, grupo e compartilhamento (pelo debkit)"
contem "RC=0" "$(s "DEBKIT_G_NOME=$GA; DEBKIT_G_MEMBROS=(); debkit_grupo_criar; echo RC=\$?")"
for x in "$UA" "$UB"; do
    contem "RC=0" "$(s "DEBKIT_U_NOME=$x; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=($GA); DEBKIT_U_HOME=0;
                        DEBKIT_U_SENHA='$SENHA'; debkit_usuario_criar; echo RC=\$?")" "$x"
done
contem "RC=0" "$(s "DEBKIT_S_NOME=$SHARE; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$T/shr'; DEBKIT_S_GRUPO=$GA; debkit_shr_criar; echo RC=\$?")"

caso "logins de verdade: sucesso, senha errada, usuário inexistente, conta desativada"
sleep 1; INICIO=$(date '+%Y-%m-%d %H:%M:%S'); sleep 1
contem "RC=0" "$(smb "$UA" ls)" "$UA entra"
contem "RC=0" "$(smb "$UB" ls)" "$UB entra"
contem "RC=1" "$(errada "$UA")" "$UA senha errada (1)"
contem "RC=1" "$(errada "$UA")" "$UA senha errada (2)"
contem "RC=1" "$(errada "$X")" "usuário inexistente"
smbpasswd -d "$UB" >/dev/null
contem "RC=1" "$(SENHA="$SENHA" smb "$UB" ls)" "$UB desativado não entra"
sleep 1

caso "falhas lidas do log real, por usuário, com o motivo"
falhas=$(s "debkit_diag_falhas '$INICIO'")
IFS='|' read -r _ ip n _ st <<< "$(grep "^$UA|" <<< "$falhas")"
igual "127.0.0.1" "$ip"; verdadeiro "$UA: 2 tentativas ou mais ($n)" test "${n:-0}" -ge 2
igual "NT_STATUS_WRONG_PASSWORD" "$st"
contem "|NT_STATUS_NO_SUCH_USER" "$(grep "^$X|" <<< "$falhas")"
contem "|NT_STATUS_ACCOUNT_DISABLED" "$(grep "^$UB|" <<< "$falhas")"
nao_contem "NT_STATUS_OK" "$falhas"
caso "último login de cada um (desde o início do teste)"
ult=$(s debkit_diag_ultimos_logins)
for x in "$UA" "$UB"; do
    IFS='|' read -r _ d ip <<< "$(grep "^$x|" <<< "$ult")"
    verdadeiro "$x: último login depois do início ($d)" test "$d" '>' "$INICIO" -o "$d" == "$INICIO"
    igual "127.0.0.1" "$ip" "$x"
done
nao_contem "$X|" "$ult" "inexistente não tem login"
caso "tela com os dados reais"
saida=$(printf '\n' | s debkit_diag_tela_logins)
contem "senha errada" "$(grep "^  $UA " <<< "$saida" | head -1)"
contem "conta desativada" "$(grep "^  $UB " <<< "$saida" | head -1)"
contem "usuário inexistente" "$(grep "^  $X " <<< "$saida")"
contem "(desativada)" "$(grep "^  $UB " <<< "$saida" | tail -1)"
nao_contem "desligado" "$saida"

limpar_real; trap - EXIT
caso "limpeza"
igual "$MD5_ANTES" "$(md5sum < /etc/samba/smb.conf)" "smb.conf real idêntico ao do início"
verdadeiro "usuários e grupos removidos" bash -c "! getent passwd $UA && ! getent passwd $UB && ! getent group $GA"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
verdadeiro "pasta de teste apagada" test ! -e "$T"
verdadeiro "smbd ativo" systemctl is-active --quiet smbd
resumo
