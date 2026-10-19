#!/usr/bin/env bash
# Prova REAL de criar compartilhamento (Fase 2, tarefa 2.1) com o Samba de
# verdade.
#
# ATENÇÃO: cria usuários e grupos de teste (Linux e base REAL do Samba, pelo
# debkit), cria pelo debkit um compartilhamento no smb.conf REAL (pasta em
# /srv/dkt-teste.*; recarrega o smbd) e acessa pelo smbclient: os membros do
# grupo gravam (e alteram e apagam o arquivo do colega) e quem não está no
# grupo é recusado. Por isso só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t17b_compartilhar_real.sh
# Ao final o smb.conf real volta idêntico (e é recarregado), e os usuários,
# as contas Samba, os grupos e a pasta são removidos.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
caixa_de_areia

W1=dkt_sw1; W2=dkt_sw2; N=dkt_sn; GW=dkt_srw; SHARE=dkt-teste-shr; SENHA="Shr#Teste1"
for x in "$W1" "$W2" "$N" "$GW"; do
    if getent passwd "$x" >/dev/null || getent group "$x" >/dev/null || pdbedit -u "$x" >/dev/null 2>&1; then echo "  $x já existe - abortando"; exit 1; fi
done
T=$(mktemp -d /srv/dkt-teste.XXXXXX); chmod 755 "$T"
SMB_ANTES="$AREIA/smb.conf.real"; cp -p /etc/samba/smb.conf "$SMB_ANTES"; MD5_ANTES=$(md5sum < /etc/samba/smb.conf)
limpar_real() {
    local x
    for x in "$W1" "$W2" "$N"; do
        pdbedit -u "$x" >/dev/null 2>&1 && smbpasswd -x "$x" >/dev/null 2>&1
        id "$x" >/dev/null 2>&1 && userdel "$x"
        getent group "$x" >/dev/null && groupdel "$x"
    done
    getent group "$GW" >/dev/null && groupdel "$GW"
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

caso "ambiente real preparado pelo debkit"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
_passou "pronto"

caso "usuários e grupos (pelo debkit)"
contem "RC=0" "$(s "DEBKIT_G_NOME=$GW; DEBKIT_G_MEMBROS=(); debkit_grupo_criar; echo RC=\$?")" "$GW"
for x in "$W1:$GW" "$W2:$GW" "$N:"; do
    contem "RC=0" "$(s "DEBKIT_U_NOME=${x%%:*}; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=(${x#*:}); DEBKIT_U_HOME=0;
                        DEBKIT_U_SENHA='$SENHA'; debkit_usuario_criar; echo RC=\$?")" "${x%%:*}"
done

caso "criar o compartilhamento no smb.conf real (pelo debkit)"
saida=$(s "DEBKIT_S_NOME=$SHARE; DEBKIT_S_COMENTARIO='Teste do debkit'; DEBKIT_S_PASTA='$T/shr'; DEBKIT_S_GRUPO=$GW; debkit_shr_criar; echo RC=\$?")
contem "RC=0" "$saida"
verdadeiro "smbd ativo depois do reload" systemctl is-active --quiet smbd
contem "$SHARE|$T/shr|@$GW||" "$(s debkit_shr_dados)" "listagem real (sem alerta)"

echo "conteudo" > "$AREIA/a.txt"; echo "alterado" > "$AREIA/b.txt"
caso "membro do grupo: grava arquivo e pasta, com o grupo do compartilhamento"
saida=$(smb "$W1" "put a.txt doc.txt; mkdir sub; put a.txt sub/doc2.txt; ls")
contem "RC=0" "$saida"; contem "doc.txt" "$saida"
igual "$GW" "$(stat -c %G "$T/shr/doc.txt")" "arquivo com o grupo de escrita"
igual "$GW 2770" "$(stat -c '%G %a' "$T/shr/sub")" "pasta nova: grupo e 2770 (setgid)"
igual "$GW" "$(stat -c %G "$T/shr/sub/doc2.txt")" "arquivo dentro da pasta nova"
caso "membro do grupo: o colega altera e apaga o arquivo do outro"
contem "RC=0" "$(smb "$W2" "put b.txt doc.txt")"
igual "alterado" "$(cat "$T/shr/doc.txt")" "conteúdo trocado pelo colega"
contem "RC=0" "$(smb "$W2" "del sub/doc2.txt")"; verdadeiro "apagado pelo colega" test ! -e "$T/shr/sub/doc2.txt"
caso "membro do grupo: lê o arquivo do colega"
saida=$(smb "$W1" "get doc.txt lido.txt")
contem "RC=0" "$saida"; igual "alterado" "$(cat "$AREIA/lido.txt" 2>/dev/null)" "leu o arquivo"
caso "fora do grupo: recusado"
saida=$(smb "$N" "ls"); nao_contem "RC=0" "$saida"; contem "ACCESS_DENIED" "$saida"

limpar_real; trap - EXIT
caso "limpeza"
igual "$MD5_ANTES" "$(md5sum < /etc/samba/smb.conf)" "smb.conf real idêntico ao do início"
verdadeiro "usuários e grupos removidos" bash -c "! getent passwd $W1 && ! getent group $GW"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
verdadeiro "pasta de teste apagada" test ! -e "$T"
verdadeiro "smbd ativo" systemctl is-active --quiet smbd
resumo
