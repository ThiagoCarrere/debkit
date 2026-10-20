#!/usr/bin/env bash
# Prova REAL da proteção SSH (tarefa 0.4) com login de verdade.
#
# ATENÇÃO: este teste recarrega o SSH real do servidor (sem derrubar sessões)
# e cria temporariamente um arquivo em /etc/ssh/sshd_config.d/ e dois
# usuários de teste. Por isso só roda com:  DEBKIT_TESTE_REAL=1 tests/run.sh t04b_ssh_real.sh
# Ao final tudo é removido e a configuração do SSH volta a ser idêntica.
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o SSH real - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

DROPIN_REAL="/etc/ssh/sshd_config.d/debkitt-teste.conf"
SENHA="SenhaTeste123"
PORTA_TUNEL=28445
for x in dkt_bloq dkt_livre; do id "$x" >/dev/null 2>&1 && { echo "usuário $x já existe - abortando"; exit 1; }; done
[ -e "$DROPIN_REAL" ] && { echo "$DROPIN_REAL já existe - abortando"; exit 1; }
SSHD_ANTES=$(sshd -T 2>/dev/null | md5sum)
INICIO=$(date '+%Y-%m-%d %H:%M:%S')

limpar_real() {
    local i x
    # Sessões de teste podem ainda estar encerrando: espera os processos
    # saírem antes do userdel (senão ele recusa e os usuários sobram)
    pkill -u dkt_bloq 2>/dev/null; pkill -u dkt_livre 2>/dev/null
    for (( i = 0; i < 20; i++ )); do
        pgrep -u dkt_bloq,dkt_livre >/dev/null 2>&1 || break
        sleep 0.5
    done
    for x in dkt_bloq dkt_livre; do id "$x" >/dev/null 2>&1 && userdel "$x"; done
    if [ -e "$DROPIN_REAL" ]; then rm -f "$DROPIN_REAL"; sshd -t && systemctl reload ssh; fi
    getent group "$GRUPO_TESTE" >/dev/null && groupdel "$GRUPO_TESTE"
    rm -rf -- "${SANDBOX:?}"
}
trap limpar_real EXIT

groupadd "$GRUPO_TESTE"
useradd -M -s /usr/sbin/nologin -G "$GRUPO_TESTE" dkt_bloq
useradd -M -s /usr/sbin/nologin dkt_livre
printf 'dkt_bloq:%s\ndkt_livre:%s\n' "$SENHA" "$SENHA" | chpasswd
printf '#!/bin/sh\necho "%s"\n' "$SENHA" > "$SANDBOX/askpass"; chmod 700 "$SANDBOX/askpass"

SSH_OPCOES=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no
            -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 -o ConnectTimeout=5 -o LogLevel=ERROR)
# Tenta login com senha e um comando; imprime a saída do ssh
ssh_tentar() {
    SSH_ASKPASS="$SANDBOX/askpass" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
        timeout 20 setsid -w ssh "${SSH_OPCOES[@]}" "$1@127.0.0.1" true </dev/null 2>&1
}
# Tenta abrir um túnel (ssh -N -L) e diz se a porta local abriu
tunel_tentar() {
    SSH_ASKPASS="$SANDBOX/askpass" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 \
        timeout 8 setsid ssh "${SSH_OPCOES[@]}" -N -L "127.0.0.1:$PORTA_TUNEL:127.0.0.1:22" "$1@127.0.0.1" </dev/null >/dev/null 2>&1 &
    sleep 4
    if ss -ltn "sport = :$PORTA_TUNEL" | grep -q LISTEN; then echo "TUNEL_ABERTO"; else echo "TUNEL_FECHADO"; fi
    wait 2>/dev/null
}
# PIDs dos processos das sessões SSH já abertas que NÃO são de teste
# (ex: "sshd-session: root@pts/0"). Prova forte de que nenhuma caiu: todos
# os PIDs de antes continuam vivos depois.
sessoes_reais() { ps -eo pid=,args= | awk '$2 == "sshd-session:" && $3 ~ /@/ && $3 !~ /^dkt_/ {print $1}' | sort; }
todas_vivas() { local p; for p in $1; do kill -0 "$p" 2>/dev/null || return 1; done; }
# A senha foi ACEITA? (o nologin então recusa o shell; a mensagem depende do
# idioma do servidor, por isso vale qualquer uma delas)
autenticou() {
    [[ "$1" != *"Permission denied"* ]] && grep -qiE 'not available|não está disponível|Could not chdir' <<< "$1"
}
s() { bash -c "source '$DEBKIT'; debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\"; DEBKIT_SSH_DROPIN='$DROPIN_REAL'; $1" 2>&1; }

# ── 1. Antes: a falha de segurança que motivou a proteção ────────────────────
caso "ANTES: usuário com nologin AUTENTICA com senha"
verdadeiro "senha aceita (o nologin só recusa o shell)" autenticou "$(ssh_tentar dkt_bloq)"
caso "ANTES: e consegue abrir TÚNEL SSH mesmo com nologin (a brecha)"
igual "TUNEL_ABERTO" "$(tunel_tentar dkt_bloq)"

# ── 2. Aplicar pela função do debkit (SSH real, recarga real) ───────────────────
caso "aplicar a proteção pelo debkit"
sess_antes=$(sessoes_reais)
saida=$(s 'debkit_acao_ssh_protecao; echo RC=$?')
contem "RC=0" "$saida"
verdadeiro "proteção efetiva (sshd -T)" bash -c "sshd -T | grep -q '^denygroups.*$GRUPO_TESTE'"
verdadeiro "há sessões reais para observar ($(wc -w <<< "$sess_antes"))" test -n "$sess_antes"
verdadeiro "TODAS as sessões SSH já abertas continuam vivas" todas_vivas "$sess_antes"
verdadeiro "SSH ativo" systemctl is-active --quiet ssh

# ── 3. Depois ────────────────────────────────────────────────────────────────
caso "DEPOIS: usuário do grupo é RECUSADO"
saida=$(ssh_tentar dkt_bloq)
contem "Permission denied" "$saida"
verdadeiro "nem chega a autenticar" bash -c '! grep -qiE "not available|não está disponível" <<< "$1"' _ "$saida"
caso "DEPOIS: túnel também é recusado"
igual "TUNEL_FECHADO" "$(tunel_tentar dkt_bloq)"
caso "DEPOIS: testemunha FORA do grupo continua autenticando"
verdadeiro "senha aceita" autenticou "$(ssh_tentar dkt_livre)"
caso "log do SSH registra o motivo (DenyGroups)"
contem "DenyGroups" "$(journalctl -u ssh --since "$INICIO" --no-pager 2>/dev/null | grep dkt_bloq)"

# ── 4. Remover pela função do debkit ────────────────────────────────────────────
caso "remover a proteção pelo debkit"
contem "RC=0" "$(s 'debkit_ssh_remover_protecao; echo RC=$?')"
verdadeiro "arquivo removido" test ! -e "$DROPIN_REAL"
verdadeiro "volta a autenticar" autenticou "$(ssh_tentar dkt_bloq)"

# ── 5. Limpeza ───────────────────────────────────────────────────────────────
limpar_real; trap - EXIT
caso "SSH real idêntico ao do início"
igual "$SSHD_ANTES" "$(sshd -T 2>/dev/null | md5sum)"
verdadeiro "usuários de teste removidos" bash -c '! id dkt_bloq && ! id dkt_livre'

resumo
