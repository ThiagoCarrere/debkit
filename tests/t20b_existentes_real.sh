#!/usr/bin/env bash
# Prova REAL dos compartilhamentos já existentes (Fase 2, tarefa 2.4) com o
# Samba de verdade.
#
# ATENÇÃO: cria usuários e grupos de teste (Linux e base REAL do Samba, pelo
# debkit), escreve À MÃO no smb.conf REAL três compartilhamentos fora do
# padrão (pastas em /srv/dkt-teste.*; recarrega o smbd), traz um para o
# padrão com uma sessão aberta de quem perde o acesso e remove outro cuja
# pasta é compartilhada com o terceiro. Por isso só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t20b_existentes_real.sh
# Ao final o smb.conf real volta idêntico (e é recarregado), e os usuários,
# as contas Samba, os grupos e a pasta são removidos.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

UA=dkt_ea; UB=dkt_eb; GA=dkt_ega; GB=dkt_egb; SHARE=dkt-teste-exist; SENHA="Exist#Teste1"
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

caso "ambiente real preparado pelo debkit"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
_passou "pronto"

caso "usuários e grupos (pelo debkit); três compartilhamentos feitos à mão"
for g in "$GA" "$GB"; do contem "RC=0" "$(s "DEBKIT_G_NOME=$g; DEBKIT_G_MEMBROS=(); debkit_grupo_criar; echo RC=\$?")" "$g"; done
for x in "$UA:$GA" "$UB:$GB"; do
    contem "RC=0" "$(s "DEBKIT_U_NOME=${x%%:*}; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=(${x#*:}); DEBKIT_U_HOME=0;
                        DEBKIT_U_SENHA='$SENHA'; debkit_usuario_criar; echo RC=\$?")" "${x%%:*}"
done
mkdir "$T/shr" "$T/dup"; chmod 777 "$T/shr" "$T/dup"
echo "do B" > "$T/shr/doc.txt"; chown "$UB:$UB" "$T/shr/doc.txt"; chmod 644 "$T/shr/doc.txt"
printf '\n[%s]\n   comment = Feito a mao\n   path = %s/shr\n   valid users = @%s, %s\n   write list = %s\n   read only = yes\n   create mask = 0644\n' \
    "$SHARE" "$T" "$GA" "$UB" "$UB" >> /etc/samba/smb.conf
for d in dup dup2; do
    printf '[%s-%s]\n   path = %s/dup\n   valid users = @%s\n   read only = no\n' "$SHARE" "$d" "$T" "$GA" >> /etc/samba/smb.conf
done
systemctl reload smbd; sleep 1
echo "conteudo" > "$SANDBOX/a.txt"; echo "alterado" > "$SANDBOX/b.txt"
contem "RC=0" "$(smb "$UB" "put a.txt b1.txt")" "antes: B grava (write list)"
contem "ACCESS_DENIED" "$(smb "$UA" "put a.txt a1.txt")" "antes: A só lê"

caso "trazer para o padrão (grupo A) com B conectado: B perde na hora, A grava"
abrir "$UB"; enviar "put a.txt b2.txt"
verdadeiro "sessão aberta de B gravou" test -f "$T/shr/b2.txt"
saida=$(s "DEBKIT_S_NOME=$SHARE; DEBKIT_S_GRUPO=$GA; debkit_shr_padronizar; echo RC=\$?")
contem "RC=0" "$saida"; contem "Compartilhamento $SHARE no padrão" "$saida"; contem "$UB: 1 sessão(ões) do Samba reconectada(s)" "$saida"
verdadeiro "smbd ativo depois do reload" systemctl is-active --quiet smbd
enviar "put a.txt b3.txt"
verdadeiro "a sessão de B que estava aberta não grava mais" test ! -e "$T/shr/b3.txt"
fechar
contem "ACCESS_DENIED" "$(smb "$UB" "ls")" "conexão nova de B recusada"
saida=$(smb "$UA" "put b.txt doc.txt; put a.txt a2.txt")
contem "RC=0" "$saida"; igual "alterado" "$(cat "$T/shr/doc.txt")" "A altera o arquivo de B (conteúdo ajustado)"
igual "$GA 660" "$(stat -c '%G %a' "$T/shr/a2.txt")" "arquivo novo no padrão (grupo, 0660)"
igual "Feito a mao" "$(testparm -s --section-name="$SHARE" --parameter-name=comment 2>/dev/null)" "o resto da seção ficou"

caso "remover um feito à mão cuja pasta é de outro compartilhamento: a pasta não muda"
antes=$(stat -c '%u %g %a' "$T/dup")
saida=$(s "DEBKIT_S_NOME=$SHARE-dup; debkit_shr_remover; echo RC=\$?")
contem "RC=0" "$saida"; contem "não foi alterada" "$saida"
igual "$antes" "$(stat -c '%u %g %a' "$T/dup")"
SHARE0="$SHARE"
SHARE="$SHARE0-dup"; contem "BAD_NETWORK_NAME" "$(smb "$UA" "ls")" "o removido não existe mais"
sleep 1   # conexão logo depois da recusada às vezes passa do tempo do smbclient
SHARE="$SHARE0-dup2"; contem "RC=0" "$(smb "$UA" "put a.txt d.txt")" "o outro continua"
SHARE="$SHARE0"

limpar_real; trap - EXIT
caso "limpeza"
igual "$MD5_ANTES" "$(md5sum < /etc/samba/smb.conf)" "smb.conf real idêntico ao do início"
verdadeiro "usuários e grupos removidos" bash -c "! getent passwd $UA && ! getent group $GA && ! getent group $GB"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
verdadeiro "pasta de teste apagada" test ! -e "$T"
verdadeiro "smbd ativo" systemctl is-active --quiet smbd
resumo
