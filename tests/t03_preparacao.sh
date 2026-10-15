#!/usr/bin/env bash
# Testes da tarefa 0.3 - preparação do ambiente.
# Tudo em caixa de areia: cópia do smb.conf, grupo de teste "dkt_usuarios",
# apt falso e um serviço systemd de teste. O Samba real não é alterado
# (o "recarregar" é simulado; nos testes de linha de comando ele recarrega o
# smbd real, cuja configuração não muda).
source "$(dirname "$0")/lib.sh"
caixa_de_areia

GRUPO_T="$GRUPO_TESTE"
getent group "$GRUPO_T" >/dev/null && { echo "grupo $GRUPO_T já existe - abortando"; exit 1; }

# Ambiente de teste: configuração AINDA NÃO criada, tudo dentro da areia
prep_env() {
    rm -rf "${AREIA:?}/etc" "${AREIA:?}/backups" "${AREIA:?}/debkit.log" "${AREIA:?}/debkit-shares.conf"
    cp -p /etc/samba/smb.conf "$AREIA/smb.conf"
    getent group "$GRUPO_T" >/dev/null && groupdel "$GRUPO_T"
    : > "$AREIA/reloads"
}
# Trecho que configura o debkit (em modo source) para a areia
CFG="DEBKIT_CONF_ARQUIVO='$AREIA/etc/debkit/debkit.conf'; debkit_conf_padroes;
     DEBKIT_LOG='$AREIA/debkit.log'; DEBKIT_BACKUP_DIR='$AREIA/backups'; DEBKIT_SMB_CONF='$AREIA/smb.conf';
     DEBKIT_SHARES_CONF='$AREIA/debkit-shares.conf'; DEBKIT_GRUPO_USUARIOS='$GRUPO_T'; DEBKIT_TRAVA='$AREIA/debkit.lock';
     DEBKIT_SSH_DROPIN='$AREIA/sshd_debkit.conf';
     debkit_samba_recarregar() { echo reload >> '$AREIA/reloads'; };"
g() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }

# ── Backups ──────────────────────────────────────────────────────────────────
caso "backup: permissões, conteúdo e limpeza das cópias antigas"
prep_env
echo "conteudo" > "$AREIA/arq.conf"
b=$(g "debkit_backup '$AREIA/arq.conf'")
igual 700 "$(stat -c %a "$AREIA/backups")" "pasta 700"
igual 600 "$(stat -c %a "$b")" "cópia 600"
verdadeiro "conteúdo igual" cmp -s "$AREIA/arq.conf" "$b"
for i in 1 2 3 4 5; do echo "v$i" > "$AREIA/arq.conf"; g "DEBKIT_BACKUP_MANTER=3; debkit_backup '$AREIA/arq.conf'" >/dev/null; done
igual 3 "$(find "$AREIA/backups" -name 'arq.conf.*' | wc -l)" "mantém só 3"
igual "v5" "$(cat "$(find "$AREIA/backups" -name 'arq.conf.*' | sort | tail -1)")" "a mais nova é a última"
igual "v3" "$(cat "$(find "$AREIA/backups" -name 'arq.conf.*' | sort | head -1)")" "apagou as mais antigas"
contem "não existe" "$(g "debkit_backup '$AREIA/nao_existe'")" "arquivo inexistente"
contem "Não foi possível fazer o backup" "$(g "DEBKIT_BACKUP_DIR=/proc/nao_pode; debkit_backup '$AREIA/arq.conf'")" "pasta impossível"

# ── Plano ────────────────────────────────────────────────────────────────────
# plano '<simulações>' -> as simulações valem para a verificação E para o plano
plano() { g "$1 debkit_verificar_ambiente >/dev/null; debkit_montar_plano; echo \"PLANO=\${DEBKIT_PLANO[*]}\"; echo \"IMP=\$DEBKIT_PLANO_IMPOSSIVEL\""; }

caso "plano numa máquina sem nada do debkit"
prep_env
saida=$(plano)
contem "PLANO=dir_conf conf dir_backup log grupo shares_conf include" "$saida"
nao_contem "samba_servico" "$saida" "Samba real ativo e habilitado: não entra"
caso "plano com Samba parado"
contem "PLANO=samba_servico" "$(plano 'debkit_servico_ativo() { return 1; };')"
caso "plano com bloqueio manual (sem systemd)"
saida=$(g "DEBKIT_DIR_SYSTEMD=/nao; debkit_verificar_ambiente >/dev/null; debkit_montar_plano; echo \"PLANO=\${DEBKIT_PLANO[*]}\"; echo \"IMP=\$DEBKIT_PLANO_IMPOSSIVEL\"")
contem "PLANO=" "$saida"; contem "IMP=Há itens que o debkit não pode resolver" "$saida"
caso "plano com pacotes faltando (Debian) e fora do Debian"
falta='debkit_tem_comando() { case "$1" in smbd|testparm) return 1;; esac; command -v "$1" >/dev/null; };'
contem "PLANO=pacotes samba_servico" "$(plano "$falta")"
printf 'ID=rocky\nID_LIKE="rhel fedora"\n' > "$AREIA/os-release"
contem "IMP=Instalação automática indisponível neste sistema. Instale manualmente: samba samba-common-bin" \
      "$(g "DEBKIT_ARQ_OS_RELEASE='$AREIA/os-release'; $falta debkit_verificar_ambiente >/dev/null; debkit_montar_plano; echo \"IMP=\$DEBKIT_PLANO_IMPOSSIVEL\"")"

# ── Execução completa ────────────────────────────────────────────────────────
caso "execução completa na areia"
prep_env
md5_antes=$(md5sum < "$AREIA/smb.conf")
saida=$(g "debkit_verificar_ambiente >/dev/null; debkit_montar_plano; debkit_executar_plano; echo RC=\$?")
contem "RC=0" "$saida"
igual 755 "$(stat -c %a "$AREIA/etc/debkit")" "pasta de configuração 755"
igual "644 0" "$(stat -c '%a %u' "$AREIA/etc/debkit/debkit.conf")" "debkit.conf 644 do root"
contem "GRUPO_USUARIOS=$GRUPO_T" "$(cat "$AREIA/etc/debkit/debkit.conf")" "debkit.conf com os valores em uso"
contem "rc=0" "$(bash -c "source '$DEBKIT'; debkit_conf_carregar '$AREIA/etc/debkit/debkit.conf'; echo rc=\$?")" "debkit.conf gerado é válido"
igual 700 "$(stat -c %a "$AREIA/backups")" "backups 700"
igual 640 "$(stat -c %a "$AREIA/debkit.log")" "log 640"
gid=$(getent group "$GRUPO_T" | cut -d: -f3)
verdadeiro "grupo criado como grupo de SISTEMA (GID $gid < 1000)" test "${gid:-9999}" -lt 1000
igual 644 "$(stat -c %a "$AREIA/debkit-shares.conf")" "debkit-shares.conf 644"
contem "include = $AREIA/debkit-shares.conf" "$(tail -2 "$AREIA/smb.conf")" "linha include no fim"
verdadeiro "smb.conf continua válido" testparm -s "$AREIA/smb.conf"
b=$(find "$AREIA/backups" -name 'smb.conf.*' | head -1)
igual "$md5_antes" "$(md5sum < "$b")" "backup do smb.conf original"
igual 1 "$(grep -c reload "$AREIA/reloads")" "Samba recarregado 1 vez"
log=$(cat "$AREIA/debkit.log")
for a in dir_conf conf dir_backup log grupo shares_conf include; do contem "preparar acao=$a resultado=ok" "$log" "auditoria $a"; done

caso "idempotente: rodar de novo não tem nada a fazer"
contem "PLANO=" "$(plano)"; igual "PLANO=" "$(plano | grep '^PLANO=')"
saida=$(g "debkit_preparar")
contem "O ambiente já está preparado" "$saida"
igual 1 "$(grep -c '^include' "$AREIA/smb.conf")" "include não duplicado"

caso "include escrito por outra pessoa (maiúsculas/espaços) é reconhecido"
prep_env
printf '\n  Include =   %s  \n' "$AREIA/debkit-shares.conf" >> "$AREIA/smb.conf"
nao_contem "include" "$(plano | grep '^PLANO=')"

caso "smb.conf sem quebra de linha no final"
prep_env
printf '[global]\n   workgroup = TESTE' > "$AREIA/smb.conf"
g "debkit_verificar_ambiente >/dev/null; debkit_montar_plano; debkit_executar_plano" >/dev/null
igual "   workgroup = TESTE" "$(sed -n 2p "$AREIA/smb.conf")" "última linha original intacta"
contem "include = $AREIA/debkit-shares.conf" "$(cat "$AREIA/smb.conf")"
verdadeiro "válido" testparm -s "$AREIA/smb.conf"

# ── Falha no meio: desfaz o que é do debkit ─────────────────────────────────────
caso "include falha no testparm: desfaz TUDO (inclusive a linha no smb.conf)"
prep_env
md5_antes=$(md5sum < "$AREIA/smb.conf")
# o testparm "falha" só depois que a linha do debkit entra no arquivo (a
# verificação inicial precisa ver o smb.conf válido, senão nem há plano)
saida=$(g "testparm() { grep -q 'debkit-shares' \"\${*: -1}\" 2>/dev/null && return 1; command testparm \"\$@\"; };
           debkit_verificar_ambiente >/dev/null; debkit_montar_plano; debkit_executar_plano; echo RC=\$?")
contem "RC=1" "$saida"; contem "Desfazendo" "$saida"
igual "$md5_antes" "$(md5sum < "$AREIA/smb.conf")" "smb.conf idêntico ao original"
verdadeiro "debkit.conf removido" test ! -e "$AREIA/etc/debkit/debkit.conf"
verdadeiro "pasta de configuração removida" test ! -e "$AREIA/etc/debkit"
verdadeiro "grupo removido" bash -c "! getent group $GRUPO_T"
verdadeiro "debkit-shares.conf removido" test ! -e "$AREIA/debkit-shares.conf"
verdadeiro "backup do smb.conf mantido (pasta não vazia)" test -n "$(find "$AREIA/backups" -name 'smb.conf.*')"
contem "acao=include resultado=falha" "$(cat "$AREIA/debkit.log")"
contem "acao=grupo resultado=desfeito" "$(cat "$AREIA/debkit.log")"

caso "falha ao criar o grupo: desfaz conf/pastas, para antes do include"
prep_env
md5_antes=$(md5sum < "$AREIA/smb.conf")
saida=$(g "groupadd() { return 1; }; debkit_verificar_ambiente >/dev/null; debkit_montar_plano; debkit_executar_plano; echo RC=\$?")
contem "RC=1" "$saida"
verdadeiro "debkit.conf removido" test ! -e "$AREIA/etc/debkit/debkit.conf"
verdadeiro "backups (vazia) removida" test ! -e "$AREIA/backups"
igual "$md5_antes" "$(md5sum < "$AREIA/smb.conf")" "smb.conf nem foi tocado"

caso "desfazer não apaga debkit-shares.conf que já tem compartilhamento"
prep_env
g "debkit_acao_shares_conf; echo '[algum]' >> '$AREIA/debkit-shares.conf'; debkit_desfazer shares_conf" >/dev/null
verdadeiro "mantido" test -e "$AREIA/debkit-shares.conf"
caso "desfazer não apaga o grupo se já tiver membros"
g "debkit_acao_grupo; usermod -aG $GRUPO_T nobody; debkit_desfazer grupo" >/dev/null
verdadeiro "grupo mantido" getent group "$GRUPO_T" >/dev/null
gpasswd -d nobody "$GRUPO_T" >/dev/null; groupdel "$GRUPO_T"

# ── Pacotes (apt falso) ──────────────────────────────────────────────────────
cat > "$AREIA/fake-apt" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_DIR/apt-args"
case "$*" in
    *" update") exit "${FAKE_UPDATE_RC:-0}" ;;
    *install*)  echo "E: falha simulada linha 1"; echo "E: falha simulada linha 2"
                [ "${FAKE_INSTALL_RC:-0}" -eq 0 ] && [ -z "${FAKE_NAO_INSTALA:-}" ] && touch "$FAKE_DIR/instalado"
                exit "${FAKE_INSTALL_RC:-0}" ;;
esac
EOF
chmod 755 "$AREIA/fake-apt"
APT="export FAKE_DIR='$AREIA'; DEBKIT_APT='$AREIA/fake-apt';
     debkit_tem_comando() { case \"\$1\" in smbd|testparm) [ -e '$AREIA/instalado' ] || return 1;; esac; command -v \"\$1\" >/dev/null; };"
pac() { rm -f "$AREIA/instalado" "$AREIA/apt-args"; g "$APT debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(pacotes); debkit_executar_plano; echo RC=\$?"; }

caso "pacotes: instalação com sucesso"
saida=$(pac)
contem "RC=0" "$saida"; contem "Instalar os pacotes: samba samba-common-bin" "$saida"
args=$(cat "$AREIA/apt-args")
contem "-o DPkg::Lock::Timeout=120 update" "$args" "update com espera pelo apt"
contem "--force-confold install -y samba samba-common-bin" "$args" "mantém config existente"
caso "pacotes: falha na instalação mostra o motivo"
saida=$(FAKE_INSTALL_RC=100 pac)
contem "RC=1" "$saida"; contem "A instalação falhou" "$saida"; contem "E: falha simulada linha 2" "$saida"
caso "pacotes: update falha mas install funciona"
saida=$(FAKE_UPDATE_RC=100 pac)
contem "Não foi possível atualizar a lista" "$saida"; contem "RC=0" "$saida"
caso "pacotes: apt diz sucesso mas o comando não aparece"
saida=$(FAKE_NAO_INSTALA=1 pac)
contem "RC=1" "$saida"; contem "o comando smbd ainda não existe" "$saida"
caso "pacotes: falha não desfaz nada que não foi feito e para o plano"
rm -f "$AREIA/instalado"
saida=$(FAKE_INSTALL_RC=100 g "$APT debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(pacotes dir_conf); debkit_executar_plano")
verdadeiro "dir_conf não executado" test ! -e "$AREIA/etc/debkit"
caso "linha de comando real do apt-get é válida (simulação -s)"
verdadeiro "apt-get -s aceita as opções" env DEBIAN_FRONTEND=noninteractive apt-get -s -o DPkg::Lock::Timeout=120 \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y samba samba-common-bin

# ── Serviço (unidade systemd de teste) ───────────────────────────────────────
UNID=/etc/systemd/system/debkitteste.service
servico_teste() {
    printf '[Unit]\nDescription=teste do debkit\n[Service]\nType=oneshot\nRemainAfterExit=yes\nExecStart=%s\n[Install]\nWantedBy=multi-user.target\n' "$1" > "$UNID"
    systemctl daemon-reload
}
SVC='debkit_descobrir_servico() { echo debkitteste; };'
caso "serviço parado e desabilitado: o debkit ativa e habilita"
servico_teste /bin/true
saida=$(g "$SVC debkit_acao_samba_servico; echo RC=\$?")
contem "RC=0" "$saida"
verdadeiro "ativo" systemctl is-active --quiet debkitteste
verdadeiro "habilitado" systemctl is-enabled --quiet debkitteste
caso "serviço que não consegue iniciar: erro claro"
systemctl stop debkitteste; systemctl disable debkitteste 2>/dev/null; servico_teste /bin/false
saida=$(g "$SVC debkit_acao_samba_servico; echo RC=\$?")
contem "RC=1" "$saida"; contem "Não foi possível ativar o serviço debkitteste" "$saida"
systemctl stop debkitteste 2>/dev/null; systemctl disable debkitteste 2>/dev/null; rm -f "$UNID"; systemctl daemon-reload; systemctl reset-failed debkitteste 2>/dev/null
verdadeiro "unidade de teste removida" bash -c '! systemctl cat debkitteste >/dev/null 2>&1'

# ── Linha de comando e assistente ────────────────────────────────────────────
# Configuração da areia apontando smb.conf/shares/grupo para a areia
conf_areia() { cat > "$AREIA/debkit.conf" <<EOF
LOG=$AREIA/debkit.log
TRAVA=$AREIA/debkit.lock
BACKUP_DIR=$AREIA/backups
SMB_CONF=$AREIA/smb.conf
SHARES_CONF=$AREIA/debkit-shares.conf
GRUPO_USUARIOS=$GRUPO_T
SSH_DROPIN=$AREIA/sshd_debkit.conf
EOF
}
caso "--preparar respondendo n: nada muda, auditoria registra a recusa"
prep_env; conf_areia; md5_antes=$(md5sum < "$AREIA/smb.conf")
saida=$(printf 'n\n' | bash "$DEBKIT" --preparar 2>&1); cod=$?
igual 1 "$cod"; contem "O debkit vai:" "$saida"; contem "Nada foi alterado" "$saida"
igual "$md5_antes" "$(md5sum < "$AREIA/smb.conf")" "smb.conf intacto"
verdadeiro "grupo não criado" bash -c "! getent group $GRUPO_T"
contem "resposta=nao" "$(cat "$AREIA/debkit.log")"
caso "--preparar respondendo s"
saida=$(printf 's\n' | bash "$DEBKIT" --preparar 2>&1); cod=$?
igual 0 "$cod"; contem "Ambiente preparado com sucesso" "$saida"
contem "include = $AREIA/debkit-shares.conf" "$(cat "$AREIA/smb.conf")"
contem "resposta=sim" "$(cat "$AREIA/debkit.log")"
caso "--preparar de novo: nada a fazer"
saida=$(printf '' | bash "$DEBKIT" --preparar 2>&1); cod=$?
igual 0 "$cod"; contem "já está preparado" "$saida"

caso "assistente ao abrir o menu: recusa e o menu abre mesmo assim"
prep_env; conf_areia
saida=$(pty 0.8 "bash $DEBKIT" n "" 0)
contem "Preparação do servidor para o debkit" "$saida"; contem "Nada foi alterado" "$saida"
contem "9) Ambiente: verificar e preparar" "$saida" "menu abriu"
caso "assistente: aceita e prepara"
saida=$(pty 0.8 "bash $DEBKIT" s "" 0)
contem "Ambiente preparado com sucesso" "$saida"
caso "assistente não aparece quando já está preparado"
nao_contem "Preparação do servidor" "$(pty 0.8 "bash $DEBKIT" 0)"
caso "menu 9 com tudo preparado"
saida=$(pty 0.8 "bash $DEBKIT" 9 "" 0)
contem "Ambiente pronto para o debkit." "$saida"
nao_contem "O debkit vai:" "$saida" "não oferece preparar de novo"

# ── Limpeza ──────────────────────────────────────────────────────────────────
getent group "$GRUPO_T" >/dev/null && groupdel "$GRUPO_T"
caso "nada fora da caixa de areia"
verdadeiro "grupo de teste removido" bash -c "! getent group $GRUPO_T"
verdadeiro "/etc/debkit não existe" test ! -e /etc/debkit
verdadeiro "/var/log/debkit.log não existe" test ! -e /var/log/debkit.log
verdadeiro "/etc/samba/debkit-shares.conf não existe" test ! -e /etc/samba/debkit-shares.conf
verdadeiro "smb.conf real sem include do debkit" bash -c "! grep -q debkit-shares /etc/samba/smb.conf"

resumo
