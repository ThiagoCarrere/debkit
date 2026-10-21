#!/usr/bin/env bash
# Prova REAL do "map to guest = never" (Fase 2) com o Samba de verdade.
#
# ATENÇÃO: cria um usuário de teste no Linux e na base REAL do Samba (pelo
# debkit) e tenta login pelo smbclient: o usuário entra; um nome que não
# existe e o próprio usuário depois de excluído são RECUSADOS (antes, com
# "bad user", viravam convidado). Por isso só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t16b_convidado_real.sh
# Precisa do ambiente real já preparado pelo debkit (que muda o "map to
# guest"). Ao final o usuário e a conta Samba de teste são removidos.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

U=dkt_gst; SENHA="Convidado#Teste1"
if getent passwd "$U" >/dev/null || getent group "$U" >/dev/null || pdbedit -u "$U" >/dev/null 2>&1; then echo "  $U já existe - abortando"; exit 1; fi
limpar_real() {
    pdbedit -u "$U" >/dev/null 2>&1 && smbpasswd -x "$U" >/dev/null 2>&1
    id "$U" >/dev/null 2>&1 && userdel "$U"
    getent group "$U" >/dev/null && groupdel "$U"
    rm -rf -- "${SANDBOX:?}"
}
trap limpar_real EXIT

( umask 027; : > "$SANDBOX/debkit.log" )
s() { env -u DEBKIT_APT -u DEBKIT_DPKG_ADMIN bash -c "source '$DEBKIT'; debkit_conf_carregar /etc/debkit/debkit.conf >/dev/null; debkit_ler_login_defs; DEBKIT_LOG='$SANDBOX/debkit.log'; DEBKIT_LOG_LOGROTATE='$SANDBOX/logrotate-debkit'; $1" 2>&1; }
smb_login() {  # smb_login <usuário> <senha>
    printf 'username = %s\npassword = %s\n' "$1" "$2" > "$SANDBOX/auth"; chmod 600 "$SANDBOX/auth"
    timeout 20 smbclient -L //127.0.0.1 -A "$SANDBOX/auth" 2>&1; echo "RC=$?"
}

caso "ambiente real preparado pelo debkit (map to guest = never)"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
igual "Never" "$(testparm -s --parameter-name='map to guest' 2>/dev/null)"

caso "o usuário entra; nome que não existe é recusado"
contem "RC=0" "$(s "DEBKIT_U_NOME=$U; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=(); DEBKIT_U_HOME=0; DEBKIT_U_SENHA='$SENHA'; debkit_usuario_criar; echo RC=\$?")"
contem "RC=0" "$(smb_login "$U" "$SENHA")" "usuário com a senha certa"
contem "NT_STATUS_LOGON_FAILURE" "$(smb_login "$U" "errada123")" "senha errada"
contem "NT_STATUS_LOGON_FAILURE" "$(smb_login dkt_nao_existe_xyz "$SENHA")" "nome que não existe (antes: virava convidado)"
caso "depois de excluído, o login é recusado"
contem "RC=0" "$(s "debkit_usuario_excluir $U; echo RC=\$?")"
contem "NT_STATUS_LOGON_FAILURE" "$(smb_login "$U" "$SENHA")"

limpar_real; trap - EXIT
caso "limpeza"
verdadeiro "usuário de teste removido" bash -c "! id $U && ! pdbedit -u $U"
resumo
