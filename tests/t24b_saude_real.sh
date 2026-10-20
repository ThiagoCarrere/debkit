#!/usr/bin/env bash
# Prova REAL da saúde do Samba (Fase 3, tarefa 3.3) com o servidor de verdade.
#
# ATENÇÃO: o relatório roda no servidor real (só leitura: o smb.conf e as
# sessões não mudam). Depois cria usuário e grupos de teste (Linux e base
# REAL do Samba, pelo debkit) e compartilhamentos no smb.conf REAL (pastas em
# /srv/dkt-teste.*; recarrega o smbd): um com grupo sem membros, um com a
# pasta apagada, e faz 10 logins com a senha errada. Não para o smbd. Só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t24b_saude_real.sh
# Ao final o smb.conf real volta idêntico (e é recarregado), e os usuários,
# as contas Samba, os grupos e as pastas são removidos.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

UA=dkt_ha; UB=dkt_hb; GA=dkt_hga; GB=dkt_hgb; SHARE=dkt-teste-sau; SENHA="Sau#Teste1"
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

errada() {
    printf 'username = %s\npassword = Errada#Teste9\n' "$1" > "$SANDBOX/auth.err"; chmod 600 "$SANDBOX/auth.err"
    timeout 20 smbclient "//127.0.0.1/$SHARE" -A "$SANDBOX/auth.err" -c ls >/dev/null 2>&1
}
relatorio() { s "debkit_saude_coletar; printf '%s\n' \"\${DEBKIT_SAUDE[@]}\"" | tr '\t' '|'; }

caso "ambiente real preparado pelo debkit"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
_passou "pronto"
caso "relatório do servidor real: serviço, porta, disco; não muda nada"
md5_conf=$(md5sum < /etc/samba/smb.conf); sessoes=$(s debkit_diag_sessoes | sort)
saida=$(relatorio)
contem "config|ok|Serviço smbd ativo" "$saida"; contem "config|ok|/etc/samba/smb.conf válido" "$saida"
contem "config|info|Samba no ar desde" "$saida"
contem "rede|ok|smbd escutando na porta 445" "$saida"
contem "disco|ok|" "$saida"; contem "base do Samba" "$saida"
nao_contem "config|aviso|A preparação" "$saida" "nada pendente"
igual "$md5_conf" "$(md5sum < /etc/samba/smb.conf)" "smb.conf igual"
igual "$sessoes" "$(s debkit_diag_sessoes | sort)" "sessões iguais"

caso "grupo sem membros, compartilhamento sem pasta e muitas falhas aparecem"
contem "RC=0" "$(s "DEBKIT_G_NOME=$GA; DEBKIT_G_MEMBROS=(); debkit_grupo_criar; echo RC=\$?")"
contem "RC=0" "$(s "DEBKIT_G_NOME=$GB; DEBKIT_G_MEMBROS=(); debkit_grupo_criar; echo RC=\$?")"
contem "RC=0" "$(s "DEBKIT_U_NOME=$UA; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=($GB); DEBKIT_U_HOME=0;
                    DEBKIT_U_SENHA='$SENHA'; debkit_usuario_criar; echo RC=\$?")"
contem "RC=0" "$(s "DEBKIT_S_NOME=$SHARE; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$T/shr'; DEBKIT_S_GRUPO=$GB; debkit_shr_criar; echo RC=\$?")"
contem "RC=0" "$(s "DEBKIT_S_NOME=$SHARE-vazio; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$T/vazio'; DEBKIT_S_GRUPO=$GA; debkit_shr_criar; echo RC=\$?")"
contem "RC=0" "$(s "DEBKIT_S_NOME=$SHARE-sumiu; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$T/sumiu'; DEBKIT_S_GRUPO=$GB; debkit_shr_criar; echo RC=\$?")"
rmdir "$T/sumiu"
for (( i = 0; i < 10; i++ )); do errada "$UA"; done
sleep 1
saida=$(relatorio)
contem "shr|aviso|$SHARE-vazio: o grupo $GA não tem membros: ninguém acessa" "$saida"
contem "shr|erro|$SHARE-sumiu: a pasta $T/sumiu não existe" "$saida"
nao_contem "shr|aviso|$SHARE:" "$saida" "o que tem membro e pasta: sem alerta"
linha=$(grep "atividade|aviso|$UA em 127.0.0.1" <<< "$saida")
verdadeiro "$UA: aviso de muitas falhas ($linha)" test -n "$linha"
contem "$SHARE" "$(grep '^disco|' <<< "$saida")" "a pasta do compartilhamento entra no disco"
caso "tela com os dados reais"
saida=$(printf '\n' | s debkit_diag_tela_saude)
contem "✘ $SHARE-sumiu: a pasta" "$saida"; contem "problema(s)" "$saida"
igual "$sessoes" "$(s debkit_diag_sessoes | grep -v '|dkt_' | sort)" "sessões de fora do teste iguais"

limpar_real; trap - EXIT
caso "limpeza"
igual "$MD5_ANTES" "$(md5sum < /etc/samba/smb.conf)" "smb.conf real idêntico ao do início"
verdadeiro "usuários e grupos removidos" bash -c "! getent passwd $UA && ! getent group $GA && ! getent group $GB"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
verdadeiro "pasta de teste apagada" test ! -e "$T"
verdadeiro "smbd ativo" systemctl is-active --quiet smbd
resumo
