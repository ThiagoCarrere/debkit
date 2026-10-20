#!/usr/bin/env bash
# Prova REAL de trocar o grupo e ajustar as permissões de um compartilhamento
# (Fase 2, tarefa 2.2) com o Samba de verdade.
#
# ATENÇÃO: cria usuários e grupos de teste (Linux e base REAL do Samba, pelo
# debkit), cria pelo debkit um compartilhamento no smb.conf REAL (pasta em
# /srv/dkt-teste.*; recarrega o smbd), troca o grupo com uma sessão aberta
# de quem perde o acesso e acessa pelo smbclient: o grupo antigo perde o
# acesso na hora, o novo entra e mexe nos arquivos que já existiam; um
# arquivo posto à mão fora do padrão só fica acessível depois do ajuste.
# Por isso só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t18b_permissoes_real.sh
# Ao final o smb.conf real volta idêntico (e é recarregado), e os usuários,
# as contas Samba, os grupos e a pasta são removidos.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
caixa_de_areia

UA=dkt_pa; UB=dkt_pb; GA=dkt_pga; GB=dkt_pgb; SHARE=dkt-teste-perm; SENHA="Perm#Teste1"
for x in "$UA" "$UB" "$GA" "$GB"; do
    if getent passwd "$x" >/dev/null || getent group "$x" >/dev/null || pdbedit -u "$x" >/dev/null 2>&1; then echo "  $x já existe - abortando"; exit 1; fi
done
T=$(mktemp -d /srv/dkt-teste.XXXXXX); chmod 755 "$T"
SMB_ANTES="$AREIA/smb.conf.real"; cp -p /etc/samba/smb.conf "$SMB_ANTES"; MD5_ANTES=$(md5sum < /etc/samba/smb.conf)
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
    rm -rf -- "${T:?}" "${AREIA:?}"
}
trap limpar_real EXIT

( umask 027; : > "$AREIA/debkit.log" ); ( umask 077; mkdir -p "$AREIA/backups" )
# Configuração REAL; log e backups do smb.conf só nesta execução
s() { env -u DEBKIT_APT -u DEBKIT_DPKG_ADMIN bash -c "source '$DEBKIT'; debkit_conf_carregar /etc/debkit/debkit.conf >/dev/null; debkit_ler_login_defs;
      DEBKIT_LOG='$AREIA/debkit.log'; DEBKIT_SMB_BACKUP_DIR='$AREIA/conf-bkp'; DEBKIT_BACKUP_DIR='$AREIA/backups'; $1" 2>&1; }
smb() {  # smb <usuário> <comandos>
    printf 'username = %s\npassword = %s\n' "$1" "$SENHA" > "$AREIA/auth.$1"; chmod 600 "$AREIA/auth.$1"
    ( cd "$AREIA" && timeout 20 smbclient "//127.0.0.1/$SHARE" -A "$AREIA/auth.$1" -c "$2" 2>&1 ); echo "RC=$?"
}
# Sessão aberta (smbclient lendo comandos de um fifo)
trap '' PIPE
abrir() {
    rm -f "$AREIA/sessao"; mkfifo "$AREIA/sessao"
    printf 'username = %s\npassword = %s\n' "$1" "$SENHA" > "$AREIA/auth.$1"; chmod 600 "$AREIA/auth.$1"
    ( cd "$AREIA" && timeout 60 smbclient "//127.0.0.1/$SHARE" -A "$AREIA/auth.$1" < "$AREIA/sessao" > "$AREIA/sessao.out" 2>&1 ) &
    PID_SESSAO=$!
    exec 3> "$AREIA/sessao"
}
enviar() { echo "$1" >&3 2>/dev/null; sleep 2; }
fechar() { echo "quit" >&3 2>/dev/null; exec 3>&-; wait "$PID_SESSAO" 2>/dev/null; PID_SESSAO=""; }

caso "ambiente real preparado pelo debkit"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
_passou "pronto"

caso "usuários, grupos e compartilhamento do grupo A (pelo debkit)"
for g in "$GA" "$GB"; do contem "RC=0" "$(s "DEBKIT_G_NOME=$g; DEBKIT_G_MEMBROS=(); debkit_grupo_criar; echo RC=\$?")" "$g"; done
for x in "$UA:$GA" "$UB:$GB"; do
    contem "RC=0" "$(s "DEBKIT_U_NOME=${x%%:*}; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=(${x#*:}); DEBKIT_U_HOME=0;
                        DEBKIT_U_SENHA='$SENHA'; debkit_usuario_criar; echo RC=\$?")" "${x%%:*}"
done
contem "RC=0" "$(s "DEBKIT_S_NOME=$SHARE; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$T/shr'; DEBKIT_S_GRUPO=$GA; debkit_shr_criar; echo RC=\$?")"
echo "conteudo" > "$AREIA/a.txt"; echo "alterado" > "$AREIA/b.txt"
contem "RC=0" "$(smb "$UA" "mkdir sub; put a.txt sub/doc.txt")" "A grava"
contem "ACCESS_DENIED" "$(smb "$UB" "ls")" "B ainda não entra"

caso "trocar para o grupo B com A conectado: A perde na hora, inclusive a sessão aberta"
abrir "$UA"; enviar "put a.txt antes.txt"
verdadeiro "sessão aberta de A gravou" test -f "$T/shr/antes.txt"
saida=$(s "DEBKIT_S_NOME=$SHARE; DEBKIT_S_GRUPO=$GB; debkit_shr_trocar_grupo; echo RC=\$?")
contem "RC=0" "$saida"; contem "agora é do grupo $GB" "$saida"; contem "$UA: 1 sessão(ões) do Samba reconectada(s)" "$saida"
verdadeiro "smbd ativo depois do reload" systemctl is-active --quiet smbd
enviar "put a.txt depois.txt"
verdadeiro "a sessão que estava aberta não grava mais" test ! -e "$T/shr/depois.txt"
fechar
contem "ACCESS_DENIED" "$(smb "$UA" "ls")" "conexão nova de A recusada"
caso "grupo B: entra e mexe nos arquivos que já existiam"
igual "$GB" "$(stat -c %G "$T/shr/sub/doc.txt")" "conteúdo passou para o grupo B"
saida=$(smb "$UB" "get sub/doc.txt lido.txt; put b.txt sub/doc.txt; del antes.txt; put a.txt novo.txt")
contem "RC=0" "$saida"; igual "conteudo" "$(cat "$AREIA/lido.txt" 2>/dev/null)" "leu o arquivo de A"
igual "alterado" "$(cat "$T/shr/sub/doc.txt")" "alterou o arquivo de A"; verdadeiro "apagou o de A" test ! -e "$T/shr/antes.txt"
igual "$GB" "$(stat -c %G "$T/shr/novo.txt")" "arquivo novo com o grupo B"

caso "arquivo posto à mão fora do padrão: só depois do ajuste"
echo "manual" > "$T/shr/manual.txt"; chown "$UA:$UA" "$T/shr/manual.txt"; chmod 600 "$T/shr/manual.txt"
contem "ACCESS_DENIED" "$(smb "$UB" "get manual.txt m.txt")" "antes: B não lê"
saida=$(s "debkit_shr_ajustar_conteudo '$T/shr' $GB; echo RC=\$?")
contem "RC=0" "$saida"; contem "ajustadas" "$saida"
saida=$(smb "$UB" "get manual.txt m.txt; put b.txt manual.txt")
contem "RC=0" "$saida"; igual "manual" "$(cat "$AREIA/m.txt" 2>/dev/null)" "depois: B lê"; igual "alterado" "$(cat "$T/shr/manual.txt")" "e altera"

caso "remover o grupo do compartilhamento: recusado"
contem "é usado no Samba ([$SHARE])" "$(s "debkit_grupo_remover $GB; echo RC=\$?")"
verdadeiro "continua" getent group "$GB"

limpar_real; trap - EXIT
caso "limpeza"
igual "$MD5_ANTES" "$(md5sum < /etc/samba/smb.conf)" "smb.conf real idêntico ao do início"
verdadeiro "usuários e grupos removidos" bash -c "! getent passwd $UA && ! getent group $GA && ! getent group $GB"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
verdadeiro "pasta de teste apagada" test ! -e "$T"
verdadeiro "smbd ativo" systemctl is-active --quiet smbd
resumo
