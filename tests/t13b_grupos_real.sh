#!/usr/bin/env bash
# Prova REAL dos grupos (Fase 1) com o Samba de verdade.
#
# ATENÇÃO: cria dois usuários de arquivos e um grupo de teste (Linux e base
# REAL do Samba, pelo debkit), acrescenta ao smb.conf REAL um
# compartilhamento de teste "valid users = @grupo" (recarrega o smbd) e
# acessa pelo smbclient: o grupo dá o acesso, entrar/sair muda o acesso nas
# conexões novas e uma sessão já aberta só muda ao reconectar. Por isso só
# roda com:  DEBKIT_TESTE_REAL=1 tests/run.sh t13b_grupos_real.sh
# Ao final o smb.conf real volta idêntico (e é recarregado), e os usuários,
# as contas Samba e o grupo são removidos.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
caixa_de_areia

U1=dkt_rg1; U2=dkt_rg2; G=dkt_rgp; SHARE=dkt_teste_grupo; SENHA="Grupo#Teste1"
for x in "$U1" "$U2" "$G"; do
    if getent passwd "$x" >/dev/null || getent group "$x" >/dev/null || pdbedit -u "$x" >/dev/null 2>&1; then echo "  $x já existe - abortando"; exit 1; fi
done
SMB_ANTES="$AREIA/smb.conf.real"
cp -p /etc/samba/smb.conf "$SMB_ANTES"
MD5_ANTES=$(md5sum < /etc/samba/smb.conf)
PASTA="$AREIA/compartilhado"

limpar_real() {
    local x i
    [ -n "${PID_SESSAO:-}" ] && kill "$PID_SESSAO" 2>/dev/null
    exec 3>&- 2>/dev/null
    pkill -u "$U1" 2>/dev/null; pkill -u "$U2" 2>/dev/null
    for (( i = 0; i < 20; i++ )); do pgrep -u "$U1,$U2" >/dev/null 2>&1 || break; sleep 0.5; done
    for x in "$U1" "$U2"; do
        pdbedit -u "$x" >/dev/null 2>&1 && smbpasswd -x "$x" >/dev/null 2>&1
        id "$x" >/dev/null 2>&1 && userdel "$x"
    done
    getent group "$G" >/dev/null && groupdel "$G"
    if [ "$(md5sum < /etc/samba/smb.conf)" != "$MD5_ANTES" ]; then
        cat "$SMB_ANTES" > /etc/samba/smb.conf
        systemctl reload smbd
    fi
    rm -rf -- "${AREIA:?}"
}
trap limpar_real EXIT

# Configuração REAL (smb.conf, base do Samba, grupo de proteção); só o log vai para a areia
s() { env -u DEBKIT_APT -u DEBKIT_DPKG_ADMIN bash -c "source '$DEBKIT'; debkit_conf_carregar /etc/debkit/debkit.conf >/dev/null; debkit_ler_login_defs; DEBKIT_LOG='$AREIA/debkit.log'; $1" 2>&1; }
smb() {  # smb <usuário> <comandos>
    printf 'username = %s\npassword = %s\n' "$1" "$SENHA" > "$AREIA/auth.$1"; chmod 600 "$AREIA/auth.$1"
    ( cd "$AREIA" && timeout 20 smbclient "//127.0.0.1/$SHARE" -A "$AREIA/auth.$1" -c "$2" 2>&1 ); echo "RC=$?"
}

( umask 027; : > "$AREIA/debkit.log" )   # senão o plano pediria para criá-lo
caso "ambiente real preparado pelo debkit"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
_passou "pronto"

caso "usuários de arquivos e grupo com um membro (pelo debkit)"
for x in "$U1" "$U2"; do
    contem "RC=0" "$(s "DEBKIT_U_NOME=$x; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=(); DEBKIT_U_HOME=0;
                        DEBKIT_U_SENHA='$SENHA'; debkit_usuario_criar; echo RC=\$?")" "$x"
done
contem "RC=0" "$(s "DEBKIT_G_NOME=$G; DEBKIT_G_MEMBROS=($U1); debkit_grupo_criar; echo RC=\$?")"
igual "$U1" "$(getent group "$G" | cut -d: -f4)"

# Compartilhamento de teste só para o grupo (pasta do grupo, 2770)
mkdir -p "$PASTA"; chown root:"$G" "$PASTA"; chmod 2770 "$PASTA"
printf '\n[%s]\n   path = %s\n   valid users = @%s\n   read only = no\n' "$SHARE" "$PASTA" "$G" >> /etc/samba/smb.conf
systemctl reload smbd; sleep 1
echo "conteudo" > "$AREIA/a.txt"

caso "smb.conf real: o debkit vê o uso do grupo"
igual "$SHARE" "$(s "debkit_samba_grupo_usos $G")"

caso "Samba: membro acessa e grava; quem não é membro é recusado"
saida=$(smb "$U1" "put a.txt a1.txt; ls")
contem "RC=0" "$saida"; contem "a1.txt" "$saida"
igual "$G" "$(stat -c %G "$PASTA/a1.txt" 2>/dev/null)" "arquivo com o grupo"
saida=$(smb "$U2" "ls"); nao_contem "RC=0" "$saida"; contem "ACCESS_DENIED" "$saida"

caso "entrar: o novo membro passa a acessar"
contem "RC=0" "$(s "DEBKIT_G_ENTRAR=($U2); DEBKIT_G_SAIR=(); debkit_grupo_alterar_membros $G; echo RC=\$?")"
saida=$(smb "$U2" "put a.txt a2.txt; ls"); contem "RC=0" "$saida"; contem "a2.txt" "$saida"

caso "sair com a sessão aberta: a sessão aberta continua até reconectar; conexão nova é recusada"
mkfifo "$AREIA/sessao"
printf 'username = %s\npassword = %s\n' "$U1" "$SENHA" > "$AREIA/auth.$U1"
( cd "$AREIA" && timeout 60 smbclient "//127.0.0.1/$SHARE" -A "$AREIA/auth.$U1" < "$AREIA/sessao" > "$AREIA/sessao.out" 2>&1 ) &
PID_SESSAO=$!
exec 3> "$AREIA/sessao"
echo "put a.txt b1.txt" >&3; sleep 2
verdadeiro "sessão aberta gravou antes" test -f "$PASTA/b1.txt"
contem "RC=0" "$(s "DEBKIT_G_ENTRAR=(); DEBKIT_G_SAIR=($U1); debkit_grupo_alterar_membros $G; echo RC=\$?")" "saiu do grupo"
nao_contem "$U1" "$(getent group "$G")"
echo "put a.txt b2.txt" >&3; sleep 2
verdadeiro "sessão aberta ainda grava (só muda ao reconectar)" test -f "$PASTA/b2.txt"
echo "quit" >&3; exec 3>&-; wait "$PID_SESSAO" 2>/dev/null; PID_SESSAO=""
saida=$(smb "$U1" "put a.txt b3.txt"); nao_contem "RC=0" "$saida"
verdadeiro "conexão nova não grava" test ! -e "$PASTA/b3.txt"

caso "remover o grupo: ninguém mais acessa"
contem "RC=0" "$(s "debkit_grupo_remover $G; echo RC=\$?")"
saida=$(smb "$U2" "ls"); nao_contem "RC=0" "$saida"
verdadeiro "usuários continuam" bash -c "id $U1 && id $U2"
igual "$(stat -c %g "$PASTA")" "$(stat -c %g "$PASTA/a1.txt")" "arquivos ficam com o número do grupo (o aviso da remoção)"

# ── Limpeza ──────────────────────────────────────────────────────────────────
limpar_real; trap - EXIT
caso "limpeza"
igual "$MD5_ANTES" "$(md5sum < /etc/samba/smb.conf)" "smb.conf real idêntico ao do início"
verdadeiro "usuários e grupo removidos" bash -c "! id $U1 && ! id $U2 && ! getent group $G"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
verdadeiro "smbd ativo" systemctl is-active --quiet smbd
resumo
