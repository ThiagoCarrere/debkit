#!/usr/bin/env bash
# Prova REAL da criação de usuário (tarefa 1.1) com login de verdade.
#
# ATENÇÃO: cria dois usuários de teste no Linux e na base REAL do Samba
# (pelo debkit, com a configuração real: /etc/debkit/debkit.conf, smb.conf
# e grupo de proteção reais) e tenta login pelo Samba e pelo SSH. Por isso
# só roda com:  DEBKIT_TESTE_REAL=1 tests/run.sh t07b_usuario_real.sh
# Precisa do ambiente real já preparado pelo debkit. Ao final os usuários
# e as contas Samba são removidos.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba e o SSH reais - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
caixa_de_areia

ARQ=dkt_rarq; SRV=dkt_rsrv
SENHA_SAMBA="Samba#Teste1"; SENHA_LINUX="Linux#Teste2"
for x in "$ARQ" "$SRV"; do
    if id "$x" >/dev/null 2>&1 || pdbedit -u "$x" >/dev/null 2>&1; then echo "  $x já existe - abortando"; exit 1; fi
done
INICIO=$(date '+%Y-%m-%d %H:%M:%S')

limpar_real() {
    local i x
    pkill -u "$ARQ" 2>/dev/null; pkill -u "$SRV" 2>/dev/null
    for (( i = 0; i < 20; i++ )); do pgrep -u "$ARQ,$SRV" >/dev/null 2>&1 || break; sleep 0.5; done
    for x in "$ARQ" "$SRV"; do
        pdbedit -u "$x" >/dev/null 2>&1 && smbpasswd -x "$x" >/dev/null 2>&1
        id "$x" >/dev/null 2>&1 && userdel "$x"
    done
    rm -rf -- "${AREIA:?}"
}
trap limpar_real EXIT

# Configuração REAL (e apt/dpkg reais: só consulta); só o log vai para a
# areia (o real não muda)
s() { env -u DEBKIT_APT -u DEBKIT_DPKG_ADMIN bash -c "source '$DEBKIT'; debkit_conf_carregar /etc/debkit/debkit.conf >/dev/null; debkit_ler_login_defs; DEBKIT_LOG='$AREIA/debkit.log'; $1" 2>&1; }

( umask 027; : > "$AREIA/debkit.log" )   # senão o plano pediria para criar o log
caso "ambiente real preparado pelo debkit"
if ! s 'debkit_samba_ambiente_pronto' >/dev/null; then
    echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1
fi
_passou "pronto"
GRUPO_REAL=$(s 'echo "$DEBKIT_GRUPO_USUARIOS"')

caso "criar pelo debkit: usuário de arquivos e usuário com acesso ao servidor"
contem "RC=0" "$(s "DEBKIT_U_NOME=$ARQ; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS='Teste Arquivos'; DEBKIT_U_GRUPOS=();
                    DEBKIT_U_SENHA='$SENHA_SAMBA'; debkit_usuario_criar; echo RC=\$?")" "$ARQ"
contem "RC=0" "$(s "DEBKIT_U_NOME=$SRV; DEBKIT_U_TIPO=servidor; DEBKIT_U_GECOS='Teste Servidor'; DEBKIT_U_GRUPOS=();
                    DEBKIT_U_SENHA='$SENHA_SAMBA'; DEBKIT_U_SENHA_LINUX='$SENHA_LINUX'; debkit_usuario_criar; echo RC=\$?")" "$SRV"
contem "$GRUPO_REAL" "$(id -nG "$ARQ")" "$ARQ no grupo de proteção real ($GRUPO_REAL)"
verdadeiro "conta na base REAL do Samba" pdbedit -u "$ARQ"

# ── Samba: login de verdade no smbd ──────────────────────────────────────────
smb_login() {
    printf 'username = %s\npassword = %s\n' "$1" "$2" > "$AREIA/auth"; chmod 600 "$AREIA/auth"
    timeout 20 smbclient -L //127.0.0.1 -A "$AREIA/auth" 2>&1; echo "RC=$?"
}
caso "Samba: usuário de arquivos entra com a senha do Samba"
saida=$(smb_login "$ARQ" "$SENHA_SAMBA")
contem "RC=0" "$saida"; contem "IPC\$" "$saida" "lista os compartilhamentos autenticado"
caso "Samba: senha errada é recusada"
contem "NT_STATUS_LOGON_FAILURE" "$(smb_login "$ARQ" "errada123")"
caso "Samba: usuário com acesso ao servidor entra com a senha do Samba"
contem "RC=0" "$(smb_login "$SRV" "$SENHA_SAMBA")"

# ── SSH ──────────────────────────────────────────────────────────────────────
SSH_OPCOES=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no
            -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 -o ConnectTimeout=5 -o LogLevel=ERROR)
ssh_tentar() {
    printf '#!/bin/sh\necho "%s"\n' "$2" > "$AREIA/askpass"; chmod 700 "$AREIA/askpass"
    SSH_ASKPASS="$AREIA/askpass" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
        timeout 20 setsid -w ssh "${SSH_OPCOES[@]}" "$1@127.0.0.1" true </dev/null 2>&1
    echo "RC=$?"
}
caso "SSH: usuário de arquivos é RECUSADO (DenyGroups), mesmo tentando a senha do Samba"
contem "Permission denied" "$(ssh_tentar "$ARQ" "$SENHA_SAMBA")"
contem "DenyGroups" "$(journalctl -u ssh --since "$INICIO" --no-pager 2>/dev/null | grep "$ARQ")" "motivo no log do SSH"
caso "SSH: usuário com acesso ao servidor entra com a senha do Linux"
saida=$(ssh_tentar "$SRV" "$SENHA_LINUX")
nao_contem "Permission denied" "$saida"; contem "RC=0" "$saida"
caso "SSH: com a senha do Samba (diferente) não entra"
saida=$(ssh_tentar "$SRV" "$SENHA_SAMBA")
nao_contem "RC=0" "$saida" "login recusado"
contem "Failed password for $SRV" "$(journalctl -u ssh --since "$INICIO" --no-pager 2>/dev/null)" "falha registrada no log do SSH"
nao_contem "user '$SRV' granted access" "$(journalctl --since "$INICIO" --no-pager 2>/dev/null)" "o PAM NÃO aceita a senha do Samba (sem pam_winbind)"

# ── Trocar senha (pelo debkit) ───────────────────────────────────────────────
NOVA_SAMBA="Samba#Nova3"; NOVA_AMBAS="Ambas#Nova4"
caso "trocar senha: usuário de arquivos (Samba) - a nova entra, a antiga não"
contem "RC=0" "$(s "DEBKIT_U_SENHA='$NOVA_SAMBA'; debkit_usuario_trocar_senha $ARQ samba; echo RC=\$?")"
contem "RC=0" "$(smb_login "$ARQ" "$NOVA_SAMBA")" "senha nova no Samba"
contem "NT_STATUS_LOGON_FAILURE" "$(smb_login "$ARQ" "$SENHA_SAMBA")" "senha antiga recusada"
igual "L" "$(passwd -S "$ARQ" | awk '{print $2}')" "Linux continua bloqueada"
caso "trocar senha: acesso ao servidor (as duas) - Samba e SSH com a nova"
contem "RC=0" "$(s "DEBKIT_U_SENHA='$NOVA_AMBAS'; debkit_usuario_trocar_senha $SRV ambas; echo RC=\$?")"
contem "RC=0" "$(smb_login "$SRV" "$NOVA_AMBAS")" "Samba"
saida=$(ssh_tentar "$SRV" "$NOVA_AMBAS"); nao_contem "Permission denied" "$saida"; contem "RC=0" "$saida" "SSH com a nova"
nao_contem "RC=0" "$(ssh_tentar "$SRV" "$SENHA_LINUX")" "SSH com a antiga não entra"
caso "unix password sync desligado no Samba real"
igual "No" "$(testparm -s --parameter-name='unix password sync' 2>/dev/null)"

caso "auditoria (log da areia) sem senhas"
log=$(cat "$AREIA/debkit.log")
contem "usuario_criar nome=$ARQ tipo=arquivos" "$log"; contem "usuario_criar nome=$SRV tipo=servidor" "$log"
nao_contem "Teste1" "$log"; nao_contem "Teste2" "$log"; nao_contem "Nova3" "$log"; nao_contem "Nova4" "$log"
contem "senha_trocar nome=$ARQ alvo=samba resultado=ok" "$log"

# ── Limpeza ──────────────────────────────────────────────────────────────────
limpar_real; trap - EXIT
caso "limpeza"
verdadeiro "usuários de teste removidos" bash -c "! id $ARQ && ! id $SRV"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"

resumo
