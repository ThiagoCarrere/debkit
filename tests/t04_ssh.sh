#!/usr/bin/env bash
# Testes da tarefa 0.4 - proteção SSH (lógica, com sshd SIMULADO).
# Não toca no SSH real. A prova com login de verdade fica em
# t04b_ssh_real.sh (só roda com GSB_TESTE_REAL=1).
source "$(dirname "$0")/lib.sh"
caixa_de_areia

DROPIN="$AREIA/sshd_config.d/gsb.conf"
mkdir -p "$AREIA/sshd_config.d"
printf 'Include %s/sshd_config.d/*.conf\nPasswordAuthentication yes\n' "$AREIA" > "$AREIA/sshd_config"

# sshd simulado: "sshd -t" falha se o arquivo do gsb tiver "QUEBRADO";
# "sshd -T" mostra denygroups lido do arquivo do gsb (se existir), a menos
# que FAKE_SEM_DENY esteja definido. Recargas são registradas em reloads.
FAKE="export FAKE_SEM_DENY=\${FAKE_SEM_DENY:-};
  GSB_SSH_DROPIN='$DROPIN'; GSB_ARQ_SSHD_CONFIG='$AREIA/sshd_config'; GSB_BACKUP_DIR='$AREIA/backups'; GSB_GRUPO_USUARIOS='$GRUPO_TESTE';
  sshd() {
    case \"\$1\" in
      -t) grep -q QUEBRADO '$DROPIN' 2>/dev/null && { echo '$DROPIN line 3: Bad configuration option: QUEBRADO'; return 255; }; return 0 ;;
      -T) echo 'passwordauthentication yes'
          [ -z \"\$FAKE_SEM_DENY\" ] && [ -f '$DROPIN' ] && awk '\$1 == \"DenyGroups\" {print \"denygroups\", \$2}' '$DROPIN'
          return 0 ;;
    esac
  };
  gsb_ssh_recarregar() { echo reload >> '$AREIA/reloads'; };"
s() { bash -c "source '$GSB'; gsb_conf_carregar \"\$GSB_CONF_ARQUIVO\"; $FAKE $1" 2>&1; }
limpar_ssh() { rm -f "$DROPIN" "$AREIA/reloads"; rm -rf "${AREIA:?}/backups"; }

# ── Detecção ─────────────────────────────────────────────────────────────────
caso "Include antes de qualquer Match: aceito"
igual 0 "$(s 'gsb_ssh_aceita_dropin; echo $?')"
caso "Include DEPOIS de um Match: retorna 2 e a verificação avisa"
printf 'PasswordAuthentication yes\nMatch User alguem\n  X11Forwarding no\nInclude %s/sshd_config.d/*.conf\n' "$AREIA" > "$AREIA/sshd_config"
igual 2 "$(s 'gsb_ssh_aceita_dropin; echo $?')"
saida=$(s 'gsb_verificar_ambiente >/dev/null; printf "%s\n" "${GSB_VERIF[@]}"; echo "DROPIN=$GSB_SSH_DROPIN_OK"')
contem "só DEPOIS de um bloco Match" "$saida"; contem "DROPIN=0" "$saida"
caso "Match comentado não conta"
printf '# Match User alguem\nInclude %s/sshd_config.d/*.conf\n' "$AREIA" > "$AREIA/sshd_config"
igual 0 "$(s 'gsb_ssh_aceita_dropin; echo $?')"
printf 'Include %s/sshd_config.d/*.conf\nPasswordAuthentication yes\n' "$AREIA" > "$AREIA/sshd_config"

caso "proteção ativa só se o grupo estiver em denygroups (sshd -T)"
limpar_ssh
igual 1 "$(s 'gsb_ssh_protecao_ativa; echo $?')" "sem arquivo"
printf 'DenyGroups outro %s\n' "$GRUPO_TESTE" > "$DROPIN"
igual 1 "$(s 'gsb_ssh_protecao_ativa; echo $?')" "grupo em segundo na lista (o fake só mostra o 1º)"
printf 'DenyGroups %s\n' "$GRUPO_TESTE" > "$DROPIN"
igual 0 "$(s 'gsb_ssh_protecao_ativa; echo $?')" "grupo presente"
printf 'DenyGroups %sx\n' "$GRUPO_TESTE" > "$DROPIN"
igual 1 "$(s 'gsb_ssh_protecao_ativa; echo $?')" "nome parecido não conta"
limpar_ssh

# ── Plano ────────────────────────────────────────────────────────────────────
plano_ssh() { s "$1 gsb_verificar_ambiente >/dev/null; gsb_montar_plano; echo \"PLANO=\${GSB_PLANO[*]}\"" | grep '^PLANO='; }
caso "plano inclui a proteção quando aplicável"
contem "ssh_protecao" "$(plano_ssh)"
caso "plano não inclui sem servidor SSH"
nao_contem "ssh_protecao" "$(plano_ssh 'gsb_tem_comando() { [ "$1" == sshd ] && return 1; command -v "$1" >/dev/null; };')"
caso "plano não inclui com Include depois de Match"
printf 'Match User x\n  X11Forwarding no\nInclude %s/sshd_config.d/*.conf\n' "$AREIA" > "$AREIA/sshd_config"
nao_contem "ssh_protecao" "$(plano_ssh)"
printf 'Include %s/sshd_config.d/*.conf\nPasswordAuthentication yes\n' "$AREIA" > "$AREIA/sshd_config"
caso "plano não inclui quando já está protegido"
printf '%s\nDenyGroups %s\n' "# gsb - Gerenciador Samba: bloqueio SSH dos usuários do servidor de arquivos" "$GRUPO_TESTE" > "$DROPIN"
nao_contem "ssh_protecao" "$(plano_ssh)"
limpar_ssh

# ── Ação ─────────────────────────────────────────────────────────────────────
caso "aplicar: cria o arquivo, valida, recarrega e confirma"
saida=$(s 'gsb_acao_ssh_protecao; echo RC=$?')
contem "RC=0" "$saida"
igual 644 "$(stat -c %a "$DROPIN")" "arquivo 644"
contem "DenyGroups $GRUPO_TESTE" "$(cat "$DROPIN")"
contem "# gsb - Gerenciador Samba: bloqueio SSH" "$(head -1 "$DROPIN")" "marca de autoria"
igual 1 "$(grep -c reload "$AREIA/reloads")" "SSH recarregado 1 vez"

caso "configuração inválida: NÃO recarrega e o desfazer remove o arquivo"
limpar_ssh
saida=$(s 'GSB_GRUPO_USUARIOS="QUEBRADO"; gsb_acao_ssh_protecao; echo RC=$?; gsb_desfazer ssh_protecao')
contem "RC=1" "$saida"; contem "o SSH NÃO foi recarregado" "$saida"
contem "Bad configuration option" "$saida" "mostra o erro do sshd"
verdadeiro "nenhuma recarga" test ! -s "$AREIA/reloads"
verdadeiro "arquivo removido" test ! -e "$DROPIN"

caso "regra não confirmada no sshd -T: falha e desfaz"
limpar_ssh
saida=$(FAKE_SEM_DENY=1 s 'gsb_verificar_ambiente >/dev/null; GSB_PLANO=(ssh_protecao); gsb_executar_plano; echo RC=$?')
contem "RC=1" "$saida"; contem "não apareceu na configuração em vigor" "$saida"
verdadeiro "arquivo removido" test ! -e "$DROPIN"

caso "arquivo de OUTRA pessoa com o mesmo nome: não sobrescreve, nem apaga ao desfazer"
limpar_ssh
echo "# arquivo do administrador" > "$DROPIN"
saida=$(s 'GSB_PLANO=(ssh_protecao); gsb_executar_plano; echo RC=$?')
contem "RC=1" "$saida"; contem "não foi criado pelo gsb" "$saida"
igual "# arquivo do administrador" "$(cat "$DROPIN")" "arquivo intacto"
caso "remover proteção também recusa arquivo alheio"
contem "não foi criado pelo gsb" "$(s 'gsb_ssh_remover_protecao; echo RC=$?')"
igual "# arquivo do administrador" "$(cat "$DROPIN")"

caso "arquivo do gsb já existente: backup e, se falhar, volta ao anterior"
limpar_ssh
printf '%s\n# versão antiga\nDenyGroups antigo\n' "# gsb - Gerenciador Samba: bloqueio SSH dos usuários do servidor de arquivos" > "$DROPIN"
antes=$(cat "$DROPIN")
saida=$(FAKE_SEM_DENY=1 s 'GSB_PLANO=(ssh_protecao); gsb_executar_plano; echo RC=$?')
contem "RC=1" "$saida"
igual "$antes" "$(cat "$DROPIN")" "versão anterior restaurada"

caso "administrador (sudo) membro do grupo: recusa para não trancá-lo fora"
limpar_ssh
groupadd "$GRUPO_TESTE"; usermod -aG "$GRUPO_TESTE" nobody
saida=$(SUDO_USER=nobody s 'gsb_acao_ssh_protecao; echo RC=$?')
contem "RC=1" "$saida"; contem "trancaria você fora do SSH" "$saida"
verdadeiro "nada criado" test ! -e "$DROPIN"
gpasswd -d nobody "$GRUPO_TESTE" >/dev/null; groupdel "$GRUPO_TESTE"

caso "falha ANTES de escrever não mexe no arquivo do gsb que já existia"
limpar_ssh
printf '%s\nDenyGroups anterior\n' "# gsb - Gerenciador Samba: bloqueio SSH dos usuários do servidor de arquivos" > "$DROPIN"
antes=$(cat "$DROPIN")
groupadd "$GRUPO_TESTE"; usermod -aG "$GRUPO_TESTE" nobody
saida=$(SUDO_USER=nobody s 'GSB_PLANO=(ssh_protecao); gsb_executar_plano; echo RC=$?')
contem "RC=1" "$saida"
igual "$antes" "$(cat "$DROPIN")" "arquivo anterior intacto"
verdadeiro "nenhuma recarga" test ! -s "$AREIA/reloads"
gpasswd -d nobody "$GRUPO_TESTE" >/dev/null; groupdel "$GRUPO_TESTE"

caso "remover proteção do gsb"
limpar_ssh
s 'gsb_acao_ssh_protecao' >/dev/null
saida=$(s 'gsb_ssh_remover_protecao; echo RC=$?')
contem "RC=0" "$saida"
verdadeiro "arquivo removido" test ! -e "$DROPIN"
verdadeiro "backup guardado" test -n "$(find "$AREIA/backups" -name 'gsb.conf.*')"
caso "remover sem proteção aplicada: nada a fazer"
igual "RC=0" "$(s 'gsb_ssh_remover_protecao; echo RC=$?')"

caso "o SSH real não foi tocado"
verdadeiro "sshd_config.d real sem arquivo do gsb" test ! -e /etc/ssh/sshd_config.d/gsb.conf
verdadeiro "sshd -T real sem o grupo de teste" bash -c "! sshd -T 2>/dev/null | grep -qw $GRUPO_TESTE"

resumo
