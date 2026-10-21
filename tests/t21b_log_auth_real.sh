#!/usr/bin/env bash
# Prova REAL do log de autenticação do Samba (Fase 3, tarefa 3.0).
#
# ATENÇÃO: cria um usuário e um grupo de teste (Linux e base REAL do Samba,
# pelo debkit) e um compartilhamento; liga pelo debkit, no smb.conf REAL, a
# classe auth_json_audit num arquivo de TESTE (/var/log/samba/dkt-teste-
# auth.json; recarrega o smbd) com a regra do logrotate no sandbox, e prova
# que o smbd registra senha errada, usuário inexistente e sucesso, e que a
# rotação funciona (o login seguinte cai no arquivo novo). Vale com a VM já
# preparada ou não. Por isso só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t21b_log_auth_real.sh
# Ao final o smb.conf real volta idêntico (e é recarregado), e o usuário, a
# conta Samba, o grupo, a pasta e o log de teste são removidos.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

UA=dkt_la; UB=dkt_lb; GA=dkt_lga; GB=dkt_lgb; SHARE=dkt-teste-auth; SENHA="Auth#Teste1"
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
      DEBKIT_LOG='$SANDBOX/debkit.log'; DEBKIT_LOG_LOGROTATE='$SANDBOX/logrotate-debkit'; DEBKIT_SMB_BACKUP_DIR='$SANDBOX/conf-bkp'; DEBKIT_BACKUP_DIR='$SANDBOX/backups'; $1" 2>&1; }
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

LOGT=/var/log/samba/dkt-teste-auth.json; REGRA="$SANDBOX/logrotate-dkt-teste"
AUTH="DEBKIT_AUTH_LOG='$LOGT'; DEBKIT_AUTH_LOGROTATE='$REGRA';"
# depois do reload que devolve o smb.conf (o smbd reabre os logs nele)
limpar_auth() { limpar_real; sleep 1; rm -f -- "$LOGT" "$LOGT".*; }
trap limpar_auth EXIT
rm -f -- "$LOGT" "$LOGT".*
linhas() { python3 -I -c '
import json, sys
for l in open(sys.argv[1]):
    i = l.find("{")
    if i < 0: continue
    a = json.loads(l[i:]).get("Authentication", {})
    print(a.get("status"), a.get("clientAccount"), a.get("remoteAddress", "").rsplit(":", 1)[0])' "$1" 2>/dev/null; }

caso "ambiente real preparado pelo debkit"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
_passou "pronto"

caso "usuário e compartilhamento de teste (pelo debkit)"
contem "RC=0" "$(s "DEBKIT_G_NOME=$GA; DEBKIT_G_MEMBROS=(); debkit_grupo_criar; echo RC=\$?")"
contem "RC=0" "$(s "DEBKIT_U_NOME=$UA; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=($GA); DEBKIT_U_HOME=0;
                    DEBKIT_U_SENHA='$SENHA'; debkit_usuario_criar; echo RC=\$?")"
contem "RC=0" "$(s "DEBKIT_S_NOME=$SHARE; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$T/shr'; DEBKIT_S_GRUPO=$GA; debkit_shr_criar; echo RC=\$?")"

caso "ligar pelo debkit no smb.conf real: o smbd passa a registrar a classe"
saida=$(s "$AUTH DEBKIT_SAMBA_LOGLEVEL_NOVO=; debkit_acao_samba_log_auth; echo RC=\$?")
contem "RC=0" "$saida"
contem "auth_json_audit:3@$LOGT" "$(grep -iE '^[[:space:]]*log ?level' /etc/samba/smb.conf)" "linha no smb.conf real"
verdadeiro "smbd ativo depois do reload" systemctl is-active --quiet smbd
sleep 1
contem "auth_json_audit:3" "$(smbcontrol smbd debuglevel 2>/dev/null | head -1)" "smbd em execução com a classe"
verdadeiro "regra válida para o logrotate" logrotate -d "$REGRA"

caso "logins registrados: senha errada, usuário inexistente e sucesso, com IP"
SENHA_CERTA="$SENHA"
SENHA="errada"; smb "$UA" "ls" >/dev/null
printf 'username = dkt_nao_existe\npassword = x\n' > "$SANDBOX/auth.x"; chmod 600 "$SANDBOX/auth.x"
timeout 20 smbclient "//127.0.0.1/$SHARE" -A "$SANDBOX/auth.x" -c ls >/dev/null 2>&1
SENHA="$SENHA_CERTA"; contem "RC=0" "$(smb "$UA" "ls")" "login certo funciona"
sleep 1
saida=$(linhas "$LOGT")
contem "NT_STATUS_WRONG_PASSWORD $UA ipv4:127.0.0.1" "$saida"
contem "NT_STATUS_NO_SUCH_USER dkt_nao_existe ipv4:127.0.0.1" "$saida"
contem "NT_STATUS_OK $UA ipv4:127.0.0.1" "$saida"

caso "rotação pelo logrotate: o arquivo gira e o login seguinte cai no arquivo novo"
logrotate -f -s "$SANDBOX/logrotate.state" "$REGRA" >/dev/null 2>&1
verdadeiro "girado (.1)" test -s "$LOGT.1"
SENHA="errada"; smb "$UA" "ls" >/dev/null; SENHA="$SENHA_CERTA"; sleep 1
contem "NT_STATUS_WRONG_PASSWORD $UA" "$(linhas "$LOGT")" "arquivo novo recebe o login"
igual "1" "$(linhas "$LOGT" | wc -l)" "só o login novo"

limpar_auth; trap - EXIT
caso "limpeza"
igual "$MD5_ANTES" "$(md5sum < /etc/samba/smb.conf)" "smb.conf real idêntico ao do início"
sleep 1
verdadeiro "smbd voltou sem a classe de teste" bash -c "! smbcontrol smbd debuglevel 2>/dev/null | head -1 | grep -q 'dkt-teste'"
verdadeiro "usuários e grupos removidos" bash -c "! getent passwd $UA && ! getent group $GA"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
verdadeiro "log de teste apagado" bash -c "! ls $LOGT* 2>/dev/null | grep -q ."
verdadeiro "pasta de teste apagada" test ! -e "$T"
verdadeiro "smbd ativo" systemctl is-active --quiet smbd
resumo
