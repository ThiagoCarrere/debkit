#!/usr/bin/env bash
# Testes da tarefa 4.1 - rotação do log de auditoria do debkit (item da
# preparação; seção 3.9): regra do logrotate mensal, 24 meses, recriada se
# mudar (com backup), desfeita se a preparação falhar adiante. Log e regra
# do sandbox; o logrotate de verdade gira o log do sandbox.
source "$(dirname "$0")/lib.sh"
sandbox

CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;"
p() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
REGRA="$SANDBOX/logrotate-debkit"; LOGT="$SANDBOX/debkit.log"
plano() { p "debkit_verificar_ambiente >/dev/null; debkit_montar_plano; echo \"PLANO=\${DEBKIT_PLANO[*]}\""; }
aplicar() { p "${1:-} DEBKIT_PLANO=(log_rotacao ${2:-}); debkit_executar_plano; echo RC=\$?"; }

caso "configuração: LOG_LOGROTATE (padrão /etc/logrotate.d/debkit), aceita no debkit.conf"
igual "/etc/logrotate.d/debkit" "$(bash -c "source '$DEBKIT'; debkit_conf_padroes; echo \$DEBKIT_LOG_LOGROTATE")"
igual "$REGRA" "$(p 'echo $DEBKIT_LOG_LOGROTATE')"
contem "LOG_LOGROTATE" "$(p 'echo ${DEBKIT_CONF_ORDEM[*]}')" "vai para o debkit.conf gerado"
caso "logrotate é dependência do núcleo (não só do Samba)"
contem "logrotate|essencial|logrotate" "$(bash -c "source '$DEBKIT'; printf '%s\n' \"\${DEBKIT_DEPENDENCIAS[@]}\"")"

caso "sem a regra: entra no plano, com a descrição"
rm -f "$REGRA"
contem "log_rotacao" "$(plano)"
contem "Girar o log de auditoria $LOGT todo mês, guardando 24 meses compactados (regra $REGRA)" \
    "$(p "debkit_verificar_ambiente >/dev/null; debkit_montar_plano; debkit_mostrar_plano")"
caso "aplicar: regra 644, mensal, 24, compactada, cria o log 640, aceita pelo logrotate"
contem "RC=0" "$(aplicar)"
igual "644" "$(stat -c %a "$REGRA")"
r=$(cat "$REGRA")
contem "$LOGT {" "$r"; contem "monthly" "$r"; contem "rotate 24" "$r"; contem "compress" "$r"; contem "delaycompress" "$r"
contem "create 0640 root root" "$r"; nao_contem "postrotate" "$r" "sem postrotate (o debkit abre o log a cada linha)"
verdadeiro "logrotate aceita" logrotate -d "$REGRA"
contem "acao=log_rotacao resultado=ok" "$(cat "$LOGT")" "auditado"
caso "idempotente: não entra mais no plano"
nao_contem "log_rotacao" "$(plano)"

caso "mudada à mão: entra no plano; recria com backup da antiga"
echo "# mudado" >> "$REGRA"
contem "log_rotacao" "$(plano)"
contem "RC=0" "$(aplicar)"
nao_contem "# mudado" "$(cat "$REGRA")"
verdadeiro "backup da regra antiga" bash -c "grep -rl '# mudado' '$SANDBOX/backups' | grep -q ."

caso "passo seguinte falha: a regra nova sai"
rm -f "$REGRA"
saida=$(aplicar "groupadd() { return 1; };" grupo)
contem "RC=1" "$saida"; verdadeiro "regra nova apagada" test ! -e "$REGRA"
caso "passo seguinte falha: a regra antiga volta"
echo "# antiga" > "$REGRA"
saida=$(aplicar "groupadd() { return 1; };" grupo)
contem "RC=1" "$saida"; igual "# antiga" "$(cat "$REGRA")"
caso "logrotate recusa a regra: a própria ação é desfeita"
rm -f "$REGRA"
saida=$(aplicar "logrotate() { return 1; };")
contem "RC=1" "$saida"; verdadeiro "regra apagada" test ! -e "$REGRA"
contem "acao=log_rotacao resultado=falha" "$(cat "$LOGT")"

caso "logrotate de verdade gira o log; a auditoria lê o girado"
contem "RC=0" "$(aplicar)"
p "debkit_auditar teste_rotacao 'antes=1'"
logrotate -f -s "$SANDBOX/logrotate.estado" "$REGRA"
verdadeiro "girado em .1" test -f "$LOGT.1"
contem "teste_rotacao" "$(cat "$LOGT.1")"
igual "640 0:0" "$(stat -c '%a %u:%g' "$LOGT")" "log novo 640 do root"
p "debkit_auditar teste_depois 'depois=1'"
contem "teste_depois" "$(cat "$LOGT")" "o debkit grava no log novo"
arqs=$(p "debkit_aud_arquivos")
contem "$LOGT.1" "$arqs"; contem "$LOGT" "$arqs"

caso "preparação completa (--preparar) cria a regra"
rm -f "$REGRA"
contem "Girar o log de auditoria" "$(printf 's\n' | bash "$DEBKIT" --preparar 2>&1)"
verdadeiro "regra criada" test -f "$REGRA"

caso "inglês"
contem "Rotate the audit log $LOGT monthly" "$(p "DEBKIT_IDIOMA=en; debkit_descrever_acao log_rotacao")"

real_intacto
resumo
