#!/usr/bin/env bash
# Testes da tarefa 0.3 - preparação do ambiente.
# Tudo em sandbox: cópia do smb.conf (e backups dele), grupo de teste "dkt_usuarios",
# apt falso e um serviço systemd de teste. O Samba real não é alterado
# (o "recarregar" é simulado; nos testes de linha de comando ele recarrega o
# smbd real, cuja configuração não muda).
source "$(dirname "$0")/lib.sh"
sandbox

GRUPO_T="$GRUPO_TESTE"
getent group "$GRUPO_T" >/dev/null && { echo "grupo $GRUPO_T já existe - abortando"; exit 1; }

# Ambiente de teste: configuração AINDA NÃO criada, tudo dentro do sandbox
prep_env() {
    rm -rf "${SANDBOX:?}/etc" "${SANDBOX:?}/backups" "${SANDBOX:?}/conf-bkp" "${SANDBOX:?}/debkit.log" "${SANDBOX:?}/logrotate-debkit"
    copiar_smb_conf "$SANDBOX/smb.conf"
    # o plano destes testes não depende do "unix password sync" do servidor
    # real (o item que o desliga tem testes próprios, em t12)
    sed -i -E 's/^([[:space:]]*unix[[:space:]]+password[[:space:]]+sync[[:space:]]*=[[:space:]]*).*/\1no/I' "$SANDBOX/smb.conf"
    getent group "$GRUPO_T" >/dev/null && groupdel "$GRUPO_T"
    : > "$SANDBOX/reloads"
}
# Trecho que configura o debkit (em modo source) para o sandbox
CFG="DEBKIT_CONF_ARQUIVO='$SANDBOX/etc/debkit/debkit.conf'; debkit_conf_padroes;
     DEBKIT_LOG='$SANDBOX/debkit.log'; DEBKIT_LOG_LOGROTATE='$SANDBOX/logrotate-debkit'; DEBKIT_BACKUP_DIR='$SANDBOX/backups'; DEBKIT_SMB_CONF='$SANDBOX/smb.conf';
     DEBKIT_SMB_BACKUP_DIR='$SANDBOX/conf-bkp'; DEBKIT_GRUPO_USUARIOS='$GRUPO_T'; DEBKIT_TRAVA='$SANDBOX/debkit.lock';
     DEBKIT_SSH_DROPIN='$SANDBOX/sshd_debkit.conf'; DEBKIT_AUTH_LOG='$SANDBOX/debkit-auth.json';
     DEBKIT_AUTH_LOGROTATE='$SANDBOX/logrotate-debkit-samba-auth';
     debkit_samba_recarregar() { echo reload >> '$SANDBOX/reloads'; };"
g() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }

# ── Backups ──────────────────────────────────────────────────────────────────
caso "backup: permissões, conteúdo e limpeza das cópias antigas"
prep_env
echo "conteudo" > "$SANDBOX/arq.conf"
b=$(g "debkit_backup '$SANDBOX/arq.conf'")
igual 700 "$(stat -c %a "$SANDBOX/backups")" "pasta 700"
igual 600 "$(stat -c %a "$b")" "cópia 600"
verdadeiro "conteúdo igual" cmp -s "$SANDBOX/arq.conf" "$b"
verdadeiro "nome arq.conf.dd-mm-aaaa-hh-mm-ss" bash -c '[[ "${1##*/}" =~ ^arq\.conf\.[0-9]{2}-[0-9]{2}-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}(-[0-9]+)?$ ]]' _ "$b"
# Os conteúdos v1..v5 em backups seguidos (o mais novo por último na ordem
# de criação: ver t06 para a ordem por data do nome)
for i in 1 2 3 4 5; do echo "v$i" > "$SANDBOX/arq.conf"; ultimo=$(g "DEBKIT_BACKUP_MANTER=3; debkit_backup '$SANDBOX/arq.conf'"); done
igual 3 "$(find "$SANDBOX/backups" -name 'arq.conf.*' | wc -l)" "mantém só 3"
igual "v5" "$(cat "$ultimo" 2>/dev/null)" "o backup recém-criado existe e é o v5"
igual "v3 v4 v5" "$(cat "$SANDBOX"/backups/arq.conf.* | sort | tr '\n' ' ' | sed 's/ $//')" "apagou as mais antigas"
contem "não existe" "$(g "debkit_backup '$SANDBOX/nao_existe'")" "arquivo inexistente"
contem "Não foi possível fazer o backup" "$(g "DEBKIT_BACKUP_DIR=/proc/nao_pode; debkit_backup '$SANDBOX/arq.conf'")" "pasta impossível"

# ── Plano ────────────────────────────────────────────────────────────────────
# plano '<simulações>' -> as simulações valem para a verificação E para o plano
plano() { g "$1 debkit_verificar_ambiente >/dev/null; debkit_montar_plano; echo \"PLANO=\${DEBKIT_PLANO[*]}\"; echo \"IMP=\$DEBKIT_PLANO_IMPOSSIVEL\""; }

caso "plano numa máquina sem nada do debkit"
prep_env
saida=$(plano)
contem "PLANO=dir_conf conf dir_backup log log_rotacao grupo" "$saida"
igual "PLANO=dir_conf conf dir_backup log log_rotacao grupo" "$(grep '^PLANO=' <<< "$saida")" "sem shares_conf/include (removidos na 1.0)"
nao_contem "samba_servico" "$saida" "Samba real ativo e habilitado: não entra"
caso "plano com Samba parado"
contem "PLANO=samba_servico" "$(plano 'debkit_servico_ativo() { return 1; };')"
caso "plano com bloqueio manual (sem systemd)"
saida=$(g "DEBKIT_DIR_SYSTEMD=/nao; debkit_verificar_ambiente >/dev/null; debkit_montar_plano; echo \"PLANO=\${DEBKIT_PLANO[*]}\"; echo \"IMP=\$DEBKIT_PLANO_IMPOSSIVEL\"")
contem "PLANO=" "$saida"; contem "IMP=Há itens que o debkit não pode resolver" "$saida"
caso "plano com pacotes faltando (Debian) e fora do Debian"
falta='debkit_tem_comando() { case "$1" in smbd|testparm) return 1;; esac; command -v "$1" >/dev/null; };'
contem "PLANO=pacotes samba_servico" "$(plano "$falta")"
printf 'ID=rocky\nID_LIKE="rhel fedora"\n' > "$SANDBOX/os-release"
contem "IMP=Instalação automática indisponível neste sistema. Instale manualmente: samba samba-common-bin" \
      "$(g "DEBKIT_ARQ_OS_RELEASE='$SANDBOX/os-release'; $falta debkit_verificar_ambiente >/dev/null; debkit_montar_plano; echo \"IMP=\$DEBKIT_PLANO_IMPOSSIVEL\"")"

# ── Execução completa ────────────────────────────────────────────────────────
caso "execução completa no sandbox"
prep_env
md5_antes=$(md5sum < "$SANDBOX/smb.conf")
saida=$(g "debkit_verificar_ambiente >/dev/null; debkit_montar_plano; debkit_executar_plano; echo RC=\$?")
contem "RC=0" "$saida"
igual 755 "$(stat -c %a "$SANDBOX/etc/debkit")" "pasta de configuração 755"
igual "644 0" "$(stat -c '%a %u' "$SANDBOX/etc/debkit/debkit.conf")" "debkit.conf 644 do root"
contem "GRUPO_USUARIOS=$GRUPO_T" "$(cat "$SANDBOX/etc/debkit/debkit.conf")" "debkit.conf com os valores em uso"
contem "rc=0" "$(bash -c "source '$DEBKIT'; debkit_conf_carregar '$SANDBOX/etc/debkit/debkit.conf'; echo rc=\$?")" "debkit.conf gerado é válido"
igual 700 "$(stat -c %a "$SANDBOX/backups")" "backups 700"
igual 640 "$(stat -c %a "$SANDBOX/debkit.log")" "log 640"
gid=$(getent group "$GRUPO_T" | cut -d: -f3)
verdadeiro "grupo criado como grupo de SISTEMA (GID $gid < 1000)" test "${gid:-9999}" -lt 1000
igual "$md5_antes" "$(md5sum < "$SANDBOX/smb.conf")" "smb.conf não é tocado pela preparação"
verdadeiro "nenhum debkit-shares.conf criado" test ! -e "$SANDBOX/debkit-shares.conf"
igual 0 "$(grep -c reload "$SANDBOX/reloads")" "Samba não recarregado"
contem "SMB_BACKUP_DIR=$SANDBOX/conf-bkp" "$(cat "$SANDBOX/etc/debkit/debkit.conf")" "debkit.conf com SMB_BACKUP_DIR"
nao_contem "SHARES_CONF" "$(cat "$SANDBOX/etc/debkit/debkit.conf")" "debkit.conf sem SHARES_CONF"
nao_contem "PREFIXO_GRUPO" "$(cat "$SANDBOX/etc/debkit/debkit.conf")" "debkit.conf sem PREFIXO_GRUPO"
log=$(cat "$SANDBOX/debkit.log")
for a in dir_conf conf dir_backup log grupo; do contem "preparar acao=$a resultado=ok" "$log" "auditoria $a"; done

caso "idempotente: rodar de novo não tem nada a fazer"
contem "PLANO=" "$(plano)"; igual "PLANO=" "$(plano | grep '^PLANO=')"
saida=$(g "debkit_preparar")
contem "O ambiente já está preparado" "$saida"

# ── Falha no meio: desfaz o que é do debkit ─────────────────────────────────────
caso "falha no meio (log): desfaz tudo o que já tinha feito"
prep_env
md5_antes=$(md5sum < "$SANDBOX/smb.conf")
saida=$(g "debkit_acao_log() { return 1; }; debkit_verificar_ambiente >/dev/null; debkit_montar_plano; debkit_executar_plano; echo RC=\$?")
contem "RC=1" "$saida"; contem "Desfazendo" "$saida"
igual "$md5_antes" "$(md5sum < "$SANDBOX/smb.conf")" "smb.conf idêntico ao original"
verdadeiro "debkit.conf removido" test ! -e "$SANDBOX/etc/debkit/debkit.conf"
verdadeiro "pasta de configuração removida" test ! -e "$SANDBOX/etc/debkit"
verdadeiro "pasta de backups (vazia) removida" test ! -e "$SANDBOX/backups"
verdadeiro "grupo não criado" bash -c "! getent group $GRUPO_T"
contem "acao=log resultado=falha" "$(cat "$SANDBOX/debkit.log" 2>/dev/null)" "auditoria da falha"

caso "falha ao criar o grupo: desfaz conf/pastas"
prep_env
md5_antes=$(md5sum < "$SANDBOX/smb.conf")
saida=$(g "groupadd() { return 1; }; debkit_verificar_ambiente >/dev/null; debkit_montar_plano; debkit_executar_plano; echo RC=\$?")
contem "RC=1" "$saida"
verdadeiro "debkit.conf removido" test ! -e "$SANDBOX/etc/debkit/debkit.conf"
verdadeiro "backups (vazia) removida" test ! -e "$SANDBOX/backups"
igual "$md5_antes" "$(md5sum < "$SANDBOX/smb.conf")" "smb.conf nem foi tocado"

prep_env
caso "desfazer não apaga o grupo se já tiver membros"
g "debkit_acao_grupo; usermod -aG $GRUPO_T nobody; debkit_desfazer grupo" >/dev/null
verdadeiro "grupo mantido" getent group "$GRUPO_T" >/dev/null
gpasswd -d nobody "$GRUPO_T" >/dev/null; groupdel "$GRUPO_T"

# ── Pacotes (apt falso) ──────────────────────────────────────────────────────
cat > "$SANDBOX/fake-apt" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_DIR/apt-args"
case "$*" in
    *" update") exit "${FAKE_UPDATE_RC:-0}" ;;
    *install*)  echo "E: falha simulada linha 1"; echo "E: falha simulada linha 2"
                [ "${FAKE_INSTALL_RC:-0}" -eq 0 ] && [ -z "${FAKE_NAO_INSTALA:-}" ] && touch "$FAKE_DIR/instalado"
                exit "${FAKE_INSTALL_RC:-0}" ;;
esac
EOF
chmod 755 "$SANDBOX/fake-apt"
APT="export FAKE_DIR='$SANDBOX'; DEBKIT_APT='$SANDBOX/fake-apt';
     debkit_tem_comando() { case \"\$1\" in smbd|testparm) [ -e '$SANDBOX/instalado' ] || return 1;; esac; command -v \"\$1\" >/dev/null; };"
pac() { rm -f "$SANDBOX/instalado" "$SANDBOX/apt-args"; g "$APT debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(pacotes); debkit_executar_plano; echo RC=\$?"; }

caso "pacotes: instalação com sucesso"
saida=$(pac)
contem "RC=0" "$saida"; contem "Instalar os pacotes: samba samba-common-bin" "$saida"
args=$(cat "$SANDBOX/apt-args")
contem "-o DPkg::Lock::Timeout=120 update" "$args" "update com espera pelo apt"
contem "--force-confold install -y --no-install-recommends samba samba-common-bin" "$args" "mantém config existente e não instala os recomendados"
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
rm -f "$SANDBOX/instalado"
saida=$(FAKE_INSTALL_RC=100 g "$APT debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(pacotes dir_conf); debkit_executar_plano")
verdadeiro "dir_conf não executado" test ! -e "$SANDBOX/etc/debkit"
caso "linha de comando real do apt-get é válida (simulação -s)"
verdadeiro "apt-get -s aceita as opções" env DEBIAN_FRONTEND=noninteractive apt-get -s -o DPkg::Lock::Timeout=120 \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install -y --no-install-recommends samba samba-common-bin

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
contem "RC=1" "$saida"; contem "Não foi possível ativar o serviço debkitteste (veja: systemctl status debkitteste)" "$saida"
systemctl stop debkitteste 2>/dev/null; systemctl disable debkitteste 2>/dev/null; rm -f "$UNID"; systemctl daemon-reload; systemctl reset-failed debkitteste 2>/dev/null
verdadeiro "unidade de teste removida" bash -c '! systemctl cat debkitteste >/dev/null 2>&1'

# ── Linha de comando e assistente ────────────────────────────────────────────
# Configuração do sandbox apontando smb.conf, backups e grupo para o sandbox
conf_sandbox() { cat > "$SANDBOX/debkit.conf" <<EOF
LOG=$SANDBOX/debkit.log
TRAVA=$SANDBOX/debkit.lock
BACKUP_DIR=$SANDBOX/backups
SMB_CONF=$SANDBOX/smb.conf
SMB_BACKUP_DIR=$SANDBOX/conf-bkp
GRUPO_USUARIOS=$GRUPO_T
SSH_DROPIN=$SANDBOX/sshd_debkit.conf
AUTH_LOG=$SANDBOX/debkit-auth.json
AUTH_LOGROTATE=$SANDBOX/logrotate-debkit-samba-auth
LOG_LOGROTATE=$SANDBOX/logrotate-debkit
EOF
}
caso "--preparar respondendo n: nada muda, auditoria registra a recusa"
prep_env; conf_sandbox; md5_antes=$(md5sum < "$SANDBOX/smb.conf")
saida=$(printf 'n\n' | bash "$DEBKIT" --preparar 2>&1); cod=$?
igual 1 "$cod"; contem "O debkit vai:" "$saida"; contem "Nada foi alterado" "$saida"
igual "$md5_antes" "$(md5sum < "$SANDBOX/smb.conf")" "smb.conf intacto"
verdadeiro "grupo não criado" bash -c "! getent group $GRUPO_T"
contem "resposta=nao" "$(cat "$SANDBOX/debkit.log")"
caso "--preparar respondendo s"
saida=$(printf 's\n' | bash "$DEBKIT" --preparar 2>&1); cod=$?
igual 0 "$cod"; contem "Ambiente preparado com sucesso" "$saida"
contem "resposta=sim" "$(cat "$SANDBOX/debkit.log")"
caso "--preparar de novo: nada a fazer"
saida=$(printf '' | bash "$DEBKIT" --preparar 2>&1); cod=$?
igual 0 "$cod"; contem "já está preparado" "$saida"

caso "assistente ao abrir o menu: recusa e o menu abre mesmo assim"
prep_env; conf_sandbox
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
caso "grupo de teste removido"
verdadeiro "não existe mais" bash -c "! getent group $GRUPO_T"
real_intacto

resumo
