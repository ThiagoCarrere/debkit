#!/usr/bin/env bash
# Prova REAL da pasta pessoal (tarefa 1.1b) com o Samba de verdade.
#
# ATENÇÃO: monta um disco de teste (arquivo ext4 em loop) em /mnt, ajusta o
# [homes] do smb.conf REAL pelo debkit (recarrega o smbd), cria dois
# usuários de teste com pasta pessoal (Linux e base REAL do Samba) e acessa
# as pastas pelo smbclient. Por isso só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t09b_home_real.sh
# Ao final o smb.conf real volta idêntico (e é recarregado), os usuários e
# as contas Samba são removidos e o disco é desmontado.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o Samba real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

U1=dkt_rh1; U2=dkt_rh2; SENHA="Home#Teste1"
for x in "$U1" "$U2"; do
    if id "$x" >/dev/null 2>&1 || pdbedit -u "$x" >/dev/null 2>&1; then echo "  $x já existe - abortando"; exit 1; fi
done
DISCO=$(mktemp -d /mnt/dkt-teste.XXXXXX)
SMB_ANTES="$SANDBOX/smb.conf.real"
cp -p /etc/samba/smb.conf "$SMB_ANTES"
MD5_ANTES=$(md5sum < /etc/samba/smb.conf)

limpar_real() {
    local x
    for x in "$U1" "$U2"; do
        pdbedit -u "$x" >/dev/null 2>&1 && smbpasswd -x "$x" >/dev/null 2>&1
        id "$x" >/dev/null 2>&1 && userdel "$x"
    done
    # smb.conf real de volta, idêntico (conteúdo, dono e permissões)
    if [ "$(md5sum < /etc/samba/smb.conf)" != "$MD5_ANTES" ]; then
        cat "$SMB_ANTES" > /etc/samba/smb.conf
        systemctl reload smbd
    fi
    mountpoint -q "$DISCO" && umount "$DISCO"
    rmdir "$DISCO" 2>/dev/null
    rm -rf -- "${SANDBOX:?}"
}
trap limpar_real EXIT

truncate -s 32M "$SANDBOX/disco.img"; mkfs.ext4 -q -F "$SANDBOX/disco.img"
mount -o loop "$SANDBOX/disco.img" "$DISCO" || { echo "  não foi possível montar o disco de teste - abortando"; exit 1; }

# Configuração REAL (smb.conf, base do Samba, grupo de proteção); log,
# backups e HOMES_BASE só nesta execução (o debkit.conf real não muda)
( umask 027; : > "$SANDBOX/debkit.log" ); ( umask 077; mkdir -p "$SANDBOX/backups" )   # senão o plano pediria para criá-los
s() { env -u DEBKIT_APT -u DEBKIT_DPKG_ADMIN bash -c "source '$DEBKIT'; debkit_conf_carregar /etc/debkit/debkit.conf >/dev/null; debkit_ler_login_defs;
      DEBKIT_LOG='$SANDBOX/debkit.log'; DEBKIT_LOG_LOGROTATE='$SANDBOX/logrotate-debkit'; DEBKIT_SMB_BACKUP_DIR='$SANDBOX/conf-bkp'; DEBKIT_BACKUP_DIR='$SANDBOX/backups'; DEBKIT_HOMES_BASE='$DISCO/homes'; $1" 2>&1; }

caso "ambiente real preparado pelo debkit"
s 'debkit_samba_ambiente_pronto' >/dev/null || { echo "  o ambiente real não está preparado (rode: debkit --preparar) - abortando"; exit 1; }
_passou "pronto"

caso "base no disco de teste e [homes] real com escrita (pelo debkit)"
mkdir -p "$DISCO/homes"
contem "RC=0" "$(s 'debkit_samba_ajustar_homes; echo RC=$?')"
igual "ok" "$(s debkit_samba_homes_estado)"
verdadeiro "smbd ativo depois do reload" systemctl is-active --quiet smbd

caso "criar dois usuários de arquivos com pasta pessoal"
for x in "$U1" "$U2"; do
    contem "RC=0" "$(s "DEBKIT_U_NOME=$x; DEBKIT_U_TIPO=arquivos; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=(); DEBKIT_U_HOME=1;
                        DEBKIT_U_SENHA='$SENHA'; debkit_usuario_criar; echo RC=\$?")" "$x"
done

smb() {  # smb <usuário> <compartilhamento> <comandos>
    printf 'username = %s\npassword = %s\n' "$1" "$SENHA" > "$SANDBOX/auth"; chmod 600 "$SANDBOX/auth"
    ( cd "$SANDBOX" && timeout 20 smbclient "//127.0.0.1/$2" -A "$SANDBOX/auth" -c "$3" 2>&1 ); echo "RC=$?"
}
echo "conteudo do teste" > "$SANDBOX/arquivo.txt"
caso "Samba: o usuário grava na própria pasta pessoal"
saida=$(smb "$U1" "$U1" "put arquivo.txt; ls")
contem "RC=0" "$saida"; contem "arquivo.txt" "$saida"
igual "conteudo do teste" "$(cat "$DISCO/homes/$U1/arquivo.txt" 2>/dev/null)" "arquivo no disco de dados"
igual "$U1" "$(stat -c %U "$DISCO/homes/$U1/arquivo.txt" 2>/dev/null)" "dono é o usuário"
caso "Samba: outro usuário NÃO acessa a pasta pessoal alheia"
saida=$(smb "$U2" "$U1" "ls")
nao_contem "arquivo.txt" "$saida"; nao_contem "RC=0" "$saida"
caso "Samba: [homes] não aparece na lista de compartilhamentos (browseable = no)"
nao_contem "homes" "$(printf 'username = %s\npassword = %s\n' "$U1" "$SENHA" > "$SANDBOX/auth"; timeout 20 smbclient -L //127.0.0.1 -A "$SANDBOX/auth" 2>&1 | awk '$2 == "Disk" {print $1}')"

# ── Limpeza ──────────────────────────────────────────────────────────────────
limpar_real; trap - EXIT
caso "limpeza"
igual "$MD5_ANTES" "$(md5sum < /etc/samba/smb.conf)" "smb.conf real idêntico ao do início"
verdadeiro "usuários de teste removidos" bash -c "! id $U1 && ! id $U2"
verdadeiro "contas Samba de teste removidas" bash -c "! pdbedit -L 2>/dev/null | grep -q '^dkt_'"
verdadeiro "disco de teste desmontado" bash -c "! findmnt -rn -o TARGET | grep -q dkt-teste"
resumo
