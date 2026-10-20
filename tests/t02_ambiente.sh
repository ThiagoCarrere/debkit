#!/usr/bin/env bash
# Testes da tarefa 0.2 - detecção do ambiente (somente leitura).
# Os cenários são simulados (comandos "faltando", outros sistemas, sshd_config
# e smb.conf de teste); nada no servidor é alterado.
source "$(dirname "$0")/lib.sh"
sandbox

# verif [código bash a rodar antes] -> imprime as linhas da verificação,
# "BLOQ=<n>", "PAC=<pacotes>" e "RC=<código>"
# A detecção é SOMENTE LEITURA, então aqui é seguro usar o caminho padrão do
# arquivo SSH do debkit (para testar se o sshd_config real o inclui).
verif() {
    bash -c "source '$DEBKIT'; debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\"; DEBKIT_SSH_DROPIN=/etc/ssh/sshd_config.d/debkit.conf; ${1:-}
        debkit_verificar_ambiente; rc=\$?
        printf '%s\n' \"\${DEBKIT_VERIF[@]}\"
        echo \"BLOQ=\$DEBKIT_BLOQUEIOS\"; echo \"PAC=\${DEBKIT_PACOTES_FALTANDO[*]}\"; echo \"RC=\$rc\"
        echo \"SSH=\$DEBKIT_TEM_SSH DROPIN=\$DEBKIT_SSH_DROPIN_OK SVC_SAMBA=\$DEBKIT_SVC_SAMBA SVC_SSH=\$DEBKIT_SVC_SSH\""
}
# faltando <comandos...> -> trecho que simula esses comandos ausentes
faltando() { echo "debkit_tem_comando() { case \"\$1\" in $(IFS='|'; echo "$*")) return 1 ;; esac; command -v \"\$1\" >/dev/null 2>&1; };"; }

# ── Servidor real ────────────────────────────────────────────────────────────
caso "servidor real (--verificar)"
saida=$(bash "$DEBKIT" --verificar 2>&1); cod=$?
igual 0 "$cod" "código 0"
contem "Todas as 23 dependências essenciais presentes" "$saida"
contem "Modo: servidor de arquivos independente" "$saida"
contem "Base de senhas: tdbsam" "$saida"
contem "Ambiente pronto para o debkit." "$saida"
saida=$(verif)
contem "SSH=1 DROPIN=1 SVC_SAMBA=smbd SVC_SSH=ssh" "$saida" "variáveis de saída"

caso "--verificar em inglês e sem root"
contem "Environment ready for debkit." "$(DEBKIT_IDIOMA=en bash "$DEBKIT" --check 2>&1)"
saida=$(setpriv --reuid=65534 --regid=65534 --clear-groups bash "$DEBKIT" --verificar 2>&1); cod=$?
contem "precisa ser executado como root" "$saida"; igual 1 "$cod"

caso "--verificar não usa trava nem auditoria"
bash "$DEBKIT" --verificar >/dev/null 2>&1
verdadeiro "sem log" test ! -e "$SANDBOX/debkit.log"
verdadeiro "sem trava" test ! -e "$SANDBOX/debkit.lock"

# ── Dependências faltando (simulado) ─────────────────────────────────────────
caso "faltam smbd, testparm, chpasswd e useradd"
saida=$(verif "$(faltando smbd testparm chpasswd useradd)")
contem "Falta o comando smbd (pacote samba)" "$saida"
contem "Falta o comando testparm (pacote samba-common-bin)" "$saida"
contem "PAC=passwd samba samba-common-bin" "$saida" "pacotes sem repetição, na ordem da tabela (núcleo, depois módulos)"
contem "Samba não instalado" "$saida"
contem "RC=1" "$saida" "verificação falha"
nao_contem "Todas as" "$saida" "não diz que está tudo presente"

caso "falta systemctl: não vira pacote a instalar"
saida=$(verif "$(faltando systemctl)")
contem "Falta o comando systemctl" "$saida"; contem "PAC=" "$saida"
nao_contem "PAC=systemd" "$saida"

caso "ferramentas de desenvolvimento faltando não bloqueiam"
saida=$(verif "$(faltando shellcheck smbclient)")
contem "shellcheck não instalado (só para desenvolvimento" "$saida"
contem "BLOQ=0" "$saida"; contem "RC=0" "$saida"

caso "sem servidor SSH: proteção não necessária, sem bloqueio"
saida=$(verif "$(faltando sshd)")
contem "proteção SSH não necessária" "$saida"; contem "RC=0" "$saida"; contem "SSH=0 DROPIN=0" "$saida"

caso "sem systemd em execução"
saida=$(DEBKIT_DIR_SYSTEMD=/nao/existe verif)
contem "systemd não está em execução" "$saida"; contem "RC=1" "$saida"

# ── Sistema (os-release) ─────────────────────────────────────────────────────
osr() { printf '%b' "$1" > "$SANDBOX/os-release"; verif "DEBKIT_ARQ_OS_RELEASE='$SANDBOX/os-release';"; }
caso "Ubuntu (derivado do Debian) sem aviso"
saida=$(osr 'ID=ubuntu\nID_LIKE=debian\nVERSION_ID="24.04"\nPRETTY_NAME="Ubuntu 24.04 LTS"')
contem "Ubuntu 24.04 LTS" "$saida"; nao_contem "fora da família Debian" "$saida"
caso "Mint (ID_LIKE com vários nomes)"
nao_contem "fora da família Debian" "$(osr 'ID=linuxmint\nID_LIKE="ubuntu debian"\nPRETTY_NAME="Linux Mint 22"')"
caso "Rocky Linux (fora da família Debian)"
saida=$(osr 'ID="rocky"\nID_LIKE="rhel centos fedora"\nPRETTY_NAME="Rocky Linux 9.4"')
contem "fora da família Debian" "$saida"; contem "RC=0" "$saida" "só aviso"
caso "os-release ausente"
contem "Sistema não identificado" "$(DEBKIT_ARQ_OS_RELEASE=/nao/existe verif)"
caso "os-release malicioso NÃO é executado"
rm -f /tmp/debkit_injecao_os
saida=$(osr 'ID=debian\nPRETTY_NAME="$(touch /tmp/debkit_injecao_os)"\n$(touch /tmp/debkit_injecao_os)')
verdadeiro "nenhum comando executado" test ! -e /tmp/debkit_injecao_os
contem '$(touch /tmp/debkit_injecao_os)' "$saida" "aparece só como texto"

# ── SSH: o sshd_config inclui o arquivo do debkit? ──────────────────────────────
sshc() { printf '%b' "$1" > "$SANDBOX/sshd_config"; verif "DEBKIT_ARQ_SSHD_CONFIG='$SANDBOX/sshd_config';" | grep -o 'DROPIN=[01]'; }
caso "Include padrão do Debian";        igual "DROPIN=1" "$(sshc 'Include /etc/ssh/sshd_config.d/*.conf\nPort 22')"
caso "Include relativo";                igual "DROPIN=1" "$(sshc 'Include sshd_config.d/*.conf')"
caso "include minúsculo e indentado";   igual "DROPIN=1" "$(sshc '   include /etc/ssh/sshd_config.d/*.conf')"
caso "vários padrões na mesma linha";   igual "DROPIN=1" "$(sshc 'Include /outro/*.conf /etc/ssh/sshd_config.d/*.conf')"
caso "Include comentado";               igual "DROPIN=0" "$(sshc '#Include /etc/ssh/sshd_config.d/*.conf')"
caso "sem Include";                     igual "DROPIN=0" "$(sshc 'Port 22\nPermitRootLogin no')"
caso "Include de outra pasta";          igual "DROPIN=0" "$(sshc 'Include /etc/ssh/outra/*.conf')"
caso "sshd_config ausente";             igual "DROPIN=0" "$(DEBKIT_ARQ_SSHD_CONFIG=/nao/existe verif | grep -o 'DROPIN=[01]')"
caso "aviso quando não inclui"
contem "a proteção SSH automática não poderá ser aplicada" "$(DEBKIT_ARQ_SSHD_CONFIG=/nao/existe verif)"

# ── Samba: smb.conf de teste ─────────────────────────────────────────────────
smb() {
    printf '%b' "$1" > "$SANDBOX/smb.conf"
    sed -i '/^SMB_CONF=/d' "$SANDBOX/debkit.conf"; echo "SMB_CONF=$SANDBOX/smb.conf" >> "$SANDBOX/debkit.conf"
    verif
}
caso "smb.conf mínimo (server role = auto + security padrão = independente)"
saida=$(smb '[global]\n   workgroup = TESTE\n')
contem "Modo: servidor de arquivos independente" "$saida"; contem "RC=0" "$saida"
caso "auto + security = user"
contem "Modo: servidor de arquivos independente" "$(smb '[global]\n   security = user\n')"
caso "auto + security = ads (membro de domínio)"
contem "Modo: member server (não testado" "$(smb '[global]\n   security = ads\n   realm = TESTE.LOCAL\n   workgroup = TESTE\n   idmap config * : backend = tdb\n   idmap config * : range = 10000-20000\n')"
caso "controlador de domínio NÃO suportado"
saida=$(smb '[global]\n   server role = active directory domain controller\n')
contem "controlador de domínio NÃO é suportado" "$saida"; contem "RC=1" "$saida"
caso "base de senhas smbpasswd não suportada"
saida=$(smb '[global]\n   passdb backend = smbpasswd\n')
contem "Base de senhas: smbpasswd - não suportada" "$saida"; contem "RC=1" "$saida"
caso "smb.conf com erro grave"
saida=$(smb '[global\n')
contem "com erro (veja: testparm)" "$saida"; contem "RC=1" "$saida"
caso "smb.conf ausente"
sed -i '/^SMB_CONF=/d' "$SANDBOX/debkit.conf"; echo "SMB_CONF=$SANDBOX/nao_existe.conf" >> "$SANDBOX/debkit.conf"
saida=$(verif)
contem "nao_existe.conf não existe" "$saida"; contem "RC=1" "$saida"
# volta a apontar para a cópia do smb.conf real dentro do sandbox
sed -i '/^SMB_CONF=/d' "$SANDBOX/debkit.conf"; echo "SMB_CONF=$SANDBOX/smb.conf" >> "$SANDBOX/debkit.conf"
copiar_smb_conf "$SANDBOX/smb.conf"

# ── Serviços (simulado) ──────────────────────────────────────────────────────
caso "Samba parado e desabilitado"
saida=$(verif 'debkit_servico_ativo() { return 1; }; debkit_servico_habilitado() { return 1; };')
contem "Serviço smbd parado" "$saida"; contem "Serviço smbd não inicia junto com o sistema" "$saida"
contem "RC=0" "$saida" "parado é aviso (a 0.3 oferece iniciar), não bloqueio"
caso "serviço do Samba não encontrado no systemd"
contem "Serviço do Samba (smbd/smb) não encontrado" "$(verif 'debkit_servico_existe() { return 1; };')"

# ── Menu ─────────────────────────────────────────────────────────────────────
preparar_sandbox
caso "menu: opção 9 mostra o ambiente e volta"
saida=$(pty 0.8 "bash $DEBKIT" 9 "" 0)
contem "9) Ambiente: verificar" "$saida"; contem "Ambiente do servidor" "$saida"
contem "Ambiente pronto para o debkit." "$saida"

real_intacto

resumo
