#!/usr/bin/env bash
# Prova REAL dos comandos diretos (tarefa 4.2) com o Samba de verdade: tudo
# feito por "debkit samba ... --sim", como num script.
#
# ATENÇÃO: cria pelos comandos usuários e um grupo de teste (Linux e base
# REAL do Samba) e um compartilhamento no smb.conf REAL (pasta em
# /srv/dkt-teste.*; recarrega o smbd), e acessa pelo smbclient: o membro do
# grupo grava, quem não é membro é recusado até entrar no grupo, a senha
# trocada pelo comando vale e a antiga não. Por isso só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t27b_comandos_real.sh
# A configuração é a real, com log, trava e backups no sandbox. No fim, o
# compartilhamento, os usuários e o grupo são removidos pelos próprios
# comandos, e o smb.conf real volta idêntico.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

U1=dkt_cu1; U2=dkt_cu2; G=dkt_cg; SHARE=dkt-teste-cli; SENHA="Cli#Real1"; NOVA="Cli#Nova2"
for x in "$U1" "$U2" "$G"; do
    if getent passwd "$x" >/dev/null || getent group "$x" >/dev/null || pdbedit -u "$x" >/dev/null 2>&1; then echo "  $x já existe - abortando"; exit 1; fi
done
[ -f /etc/debkit/debkit.conf ] || { echo "  sem /etc/debkit/debkit.conf (rode: debkit --preparar) - abortando"; exit 1; }
T=$(mktemp -d /srv/dkt-teste.XXXXXX); chmod 755 "$T"
SMB_ANTES="$SANDBOX/smb.conf.real"; cp -p /etc/samba/smb.conf "$SMB_ANTES"; MD5_ANTES=$(md5sum < /etc/samba/smb.conf)
limpar_real() {
    local x
    for x in "$U1" "$U2"; do
        pdbedit -u "$x" >/dev/null 2>&1 && smbpasswd -x "$x" >/dev/null 2>&1
        id "$x" >/dev/null 2>&1 && userdel "$x"
        getent group "$x" >/dev/null && groupdel "$x"
    done
    getent group "$G" >/dev/null && groupdel "$G"
    if [ "$(md5sum < /etc/samba/smb.conf)" != "$MD5_ANTES" ]; then
        cat "$SMB_ANTES" > /etc/samba/smb.conf
        systemctl reload smbd
    fi
    rm -rf -- "${T:?}" "${SANDBOX:?}"
}
trap limpar_real EXIT

# Configuração REAL; log, regra do log, trava e backups no sandbox
{
    cat /etc/debkit/debkit.conf
    echo "LOG=$SANDBOX/debkit.log"
    echo "LOG_LOGROTATE=$SANDBOX/logrotate-debkit"
    echo "TRAVA=$SANDBOX/debkit.lock"
    echo "BACKUP_DIR=$SANDBOX/backups"
    echo "SMB_BACKUP_DIR=$SANDBOX/conf-bkp"
} > "$SANDBOX/real.conf"
chmod 644 "$SANDBOX/real.conf"
( umask 027; : > "$SANDBOX/debkit.log" ); ( umask 077; mkdir -p "$SANDBOX/backups" )
cli() { env -u DEBKIT_APT -u DEBKIT_DPKG_ADMIN DEBKIT_CONF_ARQUIVO="$SANDBOX/real.conf" bash "$DEBKIT" samba "$@" 2>&1; echo "RC=$?"; }
smb() {  # smb <usuário> <senha> <comandos>
    printf 'username = %s\npassword = %s\n' "$1" "$2" > "$SANDBOX/auth.$1"; chmod 600 "$SANDBOX/auth.$1"
    ( cd "$SANDBOX" && timeout 20 smbclient "//127.0.0.1/$SHARE" -A "$SANDBOX/auth.$1" -c "$3" 2>&1 ); echo "RC=$?"
}

caso "ambiente real preparado pelo debkit"
saida=$(env -u DEBKIT_APT -u DEBKIT_DPKG_ADMIN DEBKIT_CONF_ARQUIVO="$SANDBOX/real.conf" bash -c "source '$DEBKIT'; debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null;
        debkit_samba_ambiente_pronto && echo PRONTO; echo \"PLANO=\${DEBKIT_PLANO[*]}\"" 2>&1)
if ! contem "PRONTO" "$saida"; then echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; fi

caso "grupo, usuários e compartilhamento pelos comandos (--sim)"
contem "RC=0" "$(cli grupo criar "$G" --sim < /dev/null)" "grupo"
contem "RC=0" "$(printf '%s\n' "$SENHA" | cli usuario criar "$U1" --nome "Teste CLI" --grupos "$G" --sim)" "$U1 no grupo"
contem "RC=0" "$(printf '%s\n' "$SENHA" | cli usuario criar "$U2" --sim)" "$U2 fora do grupo"
saida=$(cli compartilhamento criar "$SHARE" --grupo "$G" --pasta "$T/shr" --descricao "Teste dos comandos" --sim < /dev/null)
contem "RC=0" "$saida"
verdadeiro "smbd ativo depois do reload" systemctl is-active --quiet smbd
contem "$SHARE" "$(cli compartilhamento listar)"

echo "conteudo" > "$SANDBOX/a.txt"
caso "membro grava; quem não é membro é recusado"
contem "RC=0" "$(smb "$U1" "$SENHA" "put a.txt doc.txt")"
igual "$G" "$(stat -c %G "$T/shr/doc.txt")" "arquivo com o grupo do compartilhamento"
saida=$(smb "$U2" "$SENHA" "ls"); nao_contem "RC=0" "$saida"; contem "ACCESS_DENIED" "$saida"
caso "grupo membros --adicionar: passa a entrar"
contem "RC=0" "$(cli grupo membros "$G" --adicionar "$U2" --sim < /dev/null)"
contem "doc.txt" "$(smb "$U2" "$SENHA" "ls")"
caso "usuario senha: a nova vale, a antiga não"
contem "RC=0" "$(printf '%s\n' "$NOVA" | cli usuario senha "$U1")"
contem "RC=0" "$(smb "$U1" "$NOVA" "ls")" "senha nova"
saida=$(smb "$U1" "$SENHA" "ls"); nao_contem "RC=0" "$saida" "senha antiga recusada"
caso "diagnóstico pelos comandos: logins registra a falha da senha antiga"
contem "$U1" "$(cli diagnostico logins)"

caso "remoção pelos comandos"
contem "RC=0" "$(cli compartilhamento remover "$SHARE" --sim < /dev/null)" "compartilhamento"
saida=$(smb "$U1" "$NOVA" "ls"); nao_contem "RC=0" "$saida" "não existe mais"
contem "RC=0" "$(cli usuario excluir "$U1" --sim < /dev/null)" "$U1"
contem "RC=0" "$(cli usuario excluir "$U2" --sim < /dev/null)" "$U2"
contem "RC=0" "$(cli grupo remover "$G" --sim < /dev/null)" "grupo"
caso "auditoria (do sandbox) registra cada comando"
for c in "grupo criar $G" "usuario criar $U1" "compartilhamento criar $SHARE" "usuario senha $U1" "grupo remover $G"; do
    contem "comando: samba $c" "$(cat "$SANDBOX/debkit.log")" "$c"
done
nao_contem "$SENHA" "$(cat "$SANDBOX/debkit.log")" "senha nunca no log"

limpar_real; trap - EXIT
caso "limpeza"
igual "$MD5_ANTES" "$(md5sum < /etc/samba/smb.conf)" "smb.conf real idêntico ao do início"
verdadeiro "usuários e grupo removidos" bash -c "! getent passwd $U1 && ! getent passwd $U2 && ! getent group $G"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
verdadeiro "smbd ativo" systemctl is-active --quiet smbd
resumo
