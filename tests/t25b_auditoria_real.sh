#!/usr/bin/env bash
# Prova REAL da consulta à auditoria (Fase 3, tarefa 3.4).
#
# ATENÇÃO: lê o log REAL do debkit (/var/log/debkit.log; só leitura) e faz
# ações de verdade pelo debkit (Linux e base REAL do Samba, smb.conf REAL com
# pasta em /srv/dkt-teste.*; recarrega o smbd): grupo, usuários,
# compartilhamento, saída do grupo e remoção, registradas no log do teste, e
# confere a consulta. Só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t25b_auditoria_real.sh
# Ao final o smb.conf real volta idêntico (e é recarregado), e os usuários,
# as contas Samba, o grupo e a pasta são removidos.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

UA=dkt_aa; UB=dkt_ab; GA=dkt_aga; GB=dkt_agb; SHARE=dkt-teste-aud; SENHA="Aud#Teste1"
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

aud() { s "debkit_aud_filtrar '$1' '' '$2' '$3'" | cut -d'|' -f3 | tr '\n' ' '; }

caso "ambiente real preparado pelo debkit"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
_passou "pronto"
caso "o log real é só lido"
md5_log=$(md5sum < /var/log/debkit.log)
saida=$(printf '\n\n\n' | env -u DEBKIT_APT bash -c "source '$DEBKIT'; debkit_conf_carregar /etc/debkit/debkit.conf >/dev/null; debkit_ler_login_defs; debkit_diag_tela_auditoria; echo RC=\$?" 2>&1)
contem "RC=0" "$saida"; contem "Filtro: últimos 30 dias" "$saida"
igual "$md5_log" "$(md5sum < /var/log/debkit.log)" "log real igual"

caso "ações de verdade pelo debkit (grupo, usuários, compartilhamento, membros, remoção)"
HOJE=$(date '+%Y-%m-%d')
contem "RC=0" "$(s "DEBKIT_G_NOME=$GA; DEBKIT_G_MEMBROS=(); debkit_grupo_criar; echo RC=\$?")"
for x in "$UA" "$UB"; do
    contem "RC=0" "$(s "DEBKIT_U_NOME=$x; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=($GA); DEBKIT_U_HOME=0;
                        DEBKIT_U_SENHA='$SENHA'; debkit_usuario_criar; echo RC=\$?")" "$x"
done
contem "RC=0" "$(s "DEBKIT_S_NOME=$SHARE; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$T/shr'; DEBKIT_S_GRUPO=$GA; debkit_shr_criar; echo RC=\$?")"
contem "RC=0" "$(s "DEBKIT_G_ENTRAR=(); DEBKIT_G_SAIR=($UB); debkit_grupo_alterar_membros $GA; echo RC=\$?")"
contem "RC=0" "$(s "DEBKIT_S_NOME=$SHARE; debkit_shr_remover; echo RC=\$?")"

caso "a consulta acha cada ação, pelo afetado e pelo tipo"
todas=$(aud "$HOJE" "" "")
igual "shr_remover grupo_membros shr_criar usuario_criar usuario_criar grupo_criar " "$todas" "ordem: a mais recente primeiro"
igual "grupo_membros usuario_criar " "$(aud "$HOJE" "$UB" "")" "$UB: criado e saiu do grupo"
igual "shr_remover shr_criar " "$(aud "$HOJE" "$SHARE" shr)"
igual "grupo_membros shr_criar usuario_criar usuario_criar grupo_criar " "$(aud "$HOJE" "$GA" "")" "o grupo aparece em grupos=, grupo= e nome="
saida=$(printf '%s\n' "" "$UB" "" | s debkit_diag_tela_auditoria)
contem "membros do grupo" "$saida"; contem "criar usuário" "$saida"; contem "2 ação(ões)." "$saida"

limpar_real; trap - EXIT
caso "limpeza"
igual "$MD5_ANTES" "$(md5sum < /etc/samba/smb.conf)" "smb.conf real idêntico ao do início"
igual "$md5_log" "$(md5sum < /var/log/debkit.log)" "log real do debkit igual (as ações foram para o log do teste)"
verdadeiro "usuários e grupos removidos" bash -c "! getent passwd $UA && ! getent passwd $UB && ! getent group $GA"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
verdadeiro "pasta de teste apagada" test ! -e "$T"
verdadeiro "smbd ativo" systemctl is-active --quiet smbd
resumo
