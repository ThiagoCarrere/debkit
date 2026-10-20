#!/usr/bin/env bash
# Prova REAL de remover um compartilhamento (Fase 2, tarefa 2.3) com o
# Samba de verdade.
#
# ATENÇÃO: cria usuários e grupos de teste (Linux e base REAL do Samba, pelo
# debkit), cria pelo debkit um compartilhamento no smb.conf REAL (pasta em
# /srv/dkt-teste.*; recarrega o smbd) e o remove com uma sessão aberta de um
# membro: a sessão perde o acesso na hora, uma conexão nova é recusada, os
# arquivos ficam na pasta (só do root) e outro compartilhamento continua
# funcionando. Por isso só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t19b_remover_real.sh
# Ao final o smb.conf real volta idêntico (e é recarregado), e os usuários,
# as contas Samba, os grupos e a pasta são removidos.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

UA=dkt_ra; UB=dkt_rb; GA=dkt_rga; GB=dkt_rgb; SHARE=dkt-teste-rem; SENHA="Rem#Teste1"
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

caso "ambiente real preparado pelo debkit"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
_passou "pronto"

caso "usuários, grupos e dois compartilhamentos (pelo debkit)"
for g in "$GA" "$GB"; do contem "RC=0" "$(s "DEBKIT_G_NOME=$g; DEBKIT_G_MEMBROS=(); debkit_grupo_criar; echo RC=\$?")" "$g"; done
for x in "$UA:$GA" "$UB:$GB"; do
    contem "RC=0" "$(s "DEBKIT_U_NOME=${x%%:*}; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=(${x#*:}); DEBKIT_U_HOME=0;
                        DEBKIT_U_SENHA='$SENHA'; debkit_usuario_criar; echo RC=\$?")" "${x%%:*}"
done
contem "RC=0" "$(s "DEBKIT_S_NOME=$SHARE; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$T/shr'; DEBKIT_S_GRUPO=$GA; debkit_shr_criar; echo RC=\$?")"
contem "RC=0" "$(s "DEBKIT_S_NOME=$SHARE-b; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$T/outro'; DEBKIT_S_GRUPO=$GB; debkit_shr_criar; echo RC=\$?")"
echo "conteudo" > "$SANDBOX/a.txt"
contem "RC=0" "$(smb "$UA" "mkdir sub; put a.txt sub/doc.txt")" "A grava"

caso "remover com A conectado: a sessão perde o acesso na hora"
abrir "$UA"; enviar "put a.txt antes.txt"
verdadeiro "sessão aberta de A gravou" test -f "$T/shr/antes.txt"
saida=$(s "DEBKIT_S_NOME=$SHARE; debkit_shr_remover; echo RC=\$?")
contem "RC=0" "$saida"; contem "Compartilhamento $SHARE removido" "$saida"; contem "$UA: 1 sessão(ões) do Samba reconectada(s)" "$saida"
verdadeiro "smbd ativo depois do reload" systemctl is-active --quiet smbd
enviar "put a.txt depois.txt"
verdadeiro "a sessão que estava aberta não grava mais" test ! -e "$T/shr/depois.txt"
fechar
contem "BAD_NETWORK_NAME" "$(smb "$UA" "ls")" "conexão nova: o compartilhamento não existe mais"
caso "os arquivos ficam; a pasta é só do root"
igual "0 0 700" "$(stat -c '%u %g %a' "$T/shr")"
igual "conteudo" "$(cat "$T/shr/sub/doc.txt")" "arquivo de A intacto"; verdadeiro "antes.txt ficou" test -f "$T/shr/antes.txt"
caso "o outro compartilhamento continua funcionando"
SHARE_A="$SHARE"; SHARE="$SHARE-b"
contem "RC=0" "$(smb "$UB" "put a.txt b.txt")"; verdadeiro "B gravou" test -f "$T/outro/b.txt"
SHARE="$SHARE_A"
caso "o grupo deixa de ser usado no Samba"
igual "" "$(s "debkit_samba_grupo_usos $GA")"

limpar_real; trap - EXIT
caso "limpeza"
igual "$MD5_ANTES" "$(md5sum < /etc/samba/smb.conf)" "smb.conf real idêntico ao do início"
verdadeiro "usuários e grupos removidos" bash -c "! getent passwd $UA && ! getent group $GA && ! getent group $GB"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
verdadeiro "pasta de teste apagada" test ! -e "$T"
verdadeiro "smbd ativo" systemctl is-active --quiet smbd
resumo
