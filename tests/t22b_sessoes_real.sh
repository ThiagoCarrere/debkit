#!/usr/bin/env bash
# Prova REAL das sessões ativas (Fase 3, tarefa 3.1) com o Samba de verdade.
#
# ATENÇÃO: cria usuários e um grupo de teste (Linux e base REAL do Samba,
# pelo debkit) e um compartilhamento no smb.conf REAL (pasta em
# /srv/dkt-teste.*; recarrega o smbd); abre duas sessões (uma com arquivo
# aberto), confere a leitura e desconecta UMA: ela acaba na hora e a outra
# continua; sessões de quem não é do teste não mudam. Por isso só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t22b_sessoes_real.sh
# Ao final o smb.conf real volta idêntico (e é recarregado), e os usuários,
# as contas Samba, o grupo e a pasta são removidos.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

UA=dkt_sa; UB=dkt_sb; GA=dkt_sga; GB=dkt_sgb; SHARE=dkt-teste-ses; SENHA="Ses#Teste1"
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

PID_B=""
limpar_sessoes() { [ -n "$PID_B" ] && kill "$PID_B" 2>/dev/null; limpar_real; }
trap limpar_sessoes EXIT
outros() { s "debkit_diag_sessoes" | grep -v '|dkt_' | sort; }

caso "ambiente real preparado pelo debkit"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
_passou "pronto"

caso "usuários, grupo e compartilhamento (pelo debkit)"
contem "RC=0" "$(s "DEBKIT_G_NOME=$GA; DEBKIT_G_MEMBROS=(); debkit_grupo_criar; echo RC=\$?")"
for x in "$UA" "$UB"; do
    contem "RC=0" "$(s "DEBKIT_U_NOME=$x; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=($GA); DEBKIT_U_HOME=0;
                        DEBKIT_U_SENHA='$SENHA'; debkit_usuario_criar; echo RC=\$?")" "$x"
done
contem "RC=0" "$(s "DEBKIT_S_NOME=$SHARE; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$T/shr'; DEBKIT_S_GRUPO=$GA; debkit_shr_criar; echo RC=\$?")"
echo "conteudo" > "$SANDBOX/a.txt"
contem "RC=0" "$(smb "$UA" "put a.txt relatorio.txt")"

caso "duas sessões abertas: aparecem com o compartilhamento e o arquivo aberto"
antes_outros=$(outros)
abrir "$UA"; enviar "open relatorio.txt"
printf 'username = %s\npassword = %s\n' "$UB" "$SENHA" > "$SANDBOX/auth.$UB"; chmod 600 "$SANDBOX/auth.$UB"
( { echo "ls"; sleep 40; echo quit; } | timeout 60 smbclient "//127.0.0.1/$SHARE" -A "$SANDBOX/auth.$UB" >/dev/null 2>&1 ) &
PID_B=$!
sleep 2
resumo_s=$(s debkit_diag_resumo)
linha_a=$(grep "|$UA|" <<< "$resumo_s"); linha_b=$(grep "|$UB|" <<< "$resumo_s")
contem "|$UA|127.0.0.1|$SHARE|1|" "$linha_a" "A: compartilhamento e 1 arquivo aberto"
contem "|$UB|127.0.0.1|$SHARE|0|" "$linha_b" "B: compartilhamento"
contem "relatorio.txt" "$(s debkit_diag_arquivos)"
PA=${linha_a%%|*}; PB=${linha_b%%|*}

caso "desconectar a sessão de A: encerrada na hora; B continua"
saida=$(s "debkit_diag_desconectar $PA; echo RC=\$?")
contem "RC=0" "$saida"; contem "Sessão de $UA em 127.0.0.1 desconectada" "$saida"
verdadeiro "processo da sessão de A terminou" bash -c "! kill -0 $PA 2>/dev/null"
enviar "put a.txt depois.txt"
verdadeiro "a sessão de A não grava mais" test ! -e "$T/shr/depois.txt"
fechar
contem "|$UB|" "$(s debkit_diag_sessoes)" "a sessão de B continua"
verdadeiro "processo da sessão de B vivo" kill -0 "$PB"
contem "sessao_desconectar usuario=$UA ip=127.0.0.1 pid=$PA resultado=ok" "$(cat "$SANDBOX/debkit.log")"
caso "outras sessões do servidor (fora do teste) intactas"
igual "$antes_outros" "$(outros)"
caso "PID que não é sessão do Samba: recusado"
contem "não existe mais" "$(s "debkit_diag_desconectar $$; echo RC=\$?")"
verdadeiro "este processo continua" kill -0 $$

limpar_sessoes; trap - EXIT
caso "limpeza"
igual "$MD5_ANTES" "$(md5sum < /etc/samba/smb.conf)" "smb.conf real idêntico ao do início"
verdadeiro "usuários e grupos removidos" bash -c "! getent passwd $UA && ! getent passwd $UB && ! getent group $GA"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
verdadeiro "pasta de teste apagada" test ! -e "$T"
verdadeiro "smbd ativo" systemctl is-active --quiet smbd
resumo
