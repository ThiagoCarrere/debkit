#!/usr/bin/env bash
# Testes do item da preparação "log de autenticação do Samba" (Fase 3,
# tarefa 3.0; decisões na seção 3.8): "log level" com a classe
# auth_json_audit:3 num arquivo próprio (o nível do administrador fica) e a
# regra do logrotate. smb.conf, log e regra da areia; a prova com login de
# verdade está em t21b_log_auth_real.sh.
source "$(dirname "$0")/lib.sh"
caixa_de_areia

CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;
     debkit_samba_recarregar() { echo reload >> '$AREIA/reloads'; };"
p() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
efetivo() { testparm -s "$AREIA/smb.conf" 2>/dev/null; }
REGRA="$AREIA/logrotate-debkit-samba-auth"; CLASSE="auth_json_audit:3@$AREIA/debkit-auth.json"
smb_teste() { printf '%b' "$1" > "$AREIA/smb.conf"; isolar_smb_conf "$AREIA/smb.conf"; rm -rf "$AREIA/conf-bkp"; : > "$AREIA/reloads"; }
plano() { p "debkit_verificar_ambiente >/dev/null; printf '%s\n' \"\${DEBKIT_VERIF[@]}\" | grep '^samba'; debkit_montar_plano; echo \"PLANO=\${DEBKIT_PLANO[*]}\""; }
aplicar() { p "${1:-} debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(samba_log_auth ${2:-}); debkit_executar_plano; echo RC=\$?"; }
linhas_log() { grep -iE '^[[:space:]]*(log ?level|debug ?level)[[:space:]]*=' "$AREIA/smb.conf"; }
SMB_DEBIAN='[global]\n   workgroup = TESTE\n   server role = standalone server\n   map to guest = never\n# Log\n   log file = /var/log/samba/log.%%m\n   max log size = 1000\n\n[dados]\n   path = /tmp\n'

caso "desligado: avisa e entra no plano"
smb_teste "$SMB_DEBIAN"; rm -f "$REGRA"
saida=$(plano)
contem "Log de autenticação do Samba desligado: as falhas de login não ficam registradas" "$saida"
contem "samba_log_auth" "$(grep '^PLANO=' <<< "$saida")"
contem "Ligar no $AREIA/smb.conf o log de autenticação do Samba" "$(p "debkit_verificar_ambiente >/dev/null; debkit_montar_plano; debkit_mostrar_plano")"
caso "ligar: linha no fim do [global] (nível 0, o padrão), configuração em vigor igual"
antes=$(efetivo)
contem "RC=0" "$(aplicar)"
igual "   log level = 0 $CLASSE" "$(linhas_log)"
igual "max log size = 1000" "$(sed -n '/max log size/{p;q}' "$AREIA/smb.conf" | sed 's/^ *//')"
igual "   log level = 0 $CLASSE" "$(sed '/^\[dados\]/,$d' "$AREIA/smb.conf" | grep -v '^$' | tail -1)" "no fim do [global]"
igual "$antes" "$(efetivo)" "o resto da configuração em vigor não mudou"
verdadeiro "backup em conf-bkp" test -n "$(find "$AREIA/conf-bkp" -name 'smb.conf.*')"
igual 1 "$(grep -c reload "$AREIA/reloads")" "Samba recarregado"
caso "ligar: regra do logrotate (semanal, 12 semanas, válida para o logrotate)"
igual "644" "$(stat -c %a "$REGRA")"
contem "$AREIA/debkit-auth.json {" "$(cat "$REGRA")"; contem "weekly" "$(cat "$REGRA")"; contem "rotate 12" "$(cat "$REGRA")"
verdadeiro "logrotate aceita" logrotate -d "$REGRA"
caso "idempotente: depois não entra mais no plano"
saida=$(plano)
nao_contem "samba_log_auth" "$saida"; contem "Log de autenticação do Samba: $AREIA/debkit-auth.json" "$saida"

caso "nível do administrador fica; outra configuração da classe sai; debug level (sinônimo) sai"
smb_teste '[global]\n   workgroup = TESTE\n   debug level = 3\n   log level = 2 passdb:5 auth_json_audit:2\n   map to guest = never\n[dados]\n   path = /tmp\n   log level = 9\n'
contem "RC=0" "$(aplicar)"
igual "$(printf '   log level = 2 passdb:5 %s\n   log level = 9' "$CLASSE")" "$(linhas_log)" "uma linha no [global], no lugar; a do [dados] não muda"
contem "map to guest = never" "$(sed -n '/log level = 2/{n;p}' "$AREIA/smb.conf")" "no mesmo lugar"
caso "nome sem espaços e maiúsculas"
smb_teste '[global]\n   LogLevel = 1\n[dados]\n   path = /tmp\n'
contem "samba_log_auth" "$(plano)"
contem "RC=0" "$(aplicar)"; igual "   log level = 1 $CLASSE" "$(linhas_log)"

caso "só a regra mudada à mão: avisa, recria (com backup) e não mexe no smb.conf"
echo "# mudado" >> "$REGRA"; md5=$(md5sum < "$AREIA/smb.conf"); : > "$AREIA/reloads"
saida=$(plano)
contem "A rotação do log de autenticação ($REGRA) falta ou foi alterada" "$saida"; contem "samba_log_auth" "$saida"
contem "RC=0" "$(aplicar)"
nao_contem "# mudado" "$(cat "$REGRA")"; igual "$md5" "$(md5sum < "$AREIA/smb.conf")"; igual 0 "$(grep -c reload "$AREIA/reloads")"
verdadeiro "backup da regra antiga" bash -c "grep -rl '# mudado' '$AREIA/backups' | grep -q ."

caso "passo seguinte falha: smb.conf volta e a regra nova sai"
smb_teste "$SMB_DEBIAN"; rm -f "$REGRA"; cp "$AREIA/smb.conf" "$AREIA/smb.antes"
saida=$(p "debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(samba_log_auth grupo); groupadd() { return 1; }; debkit_executar_plano; echo RC=\$?")
contem "RC=1" "$saida"; contem "restaurado do backup" "$saida"
verdadeiro "smb.conf de volta" cmp -s "$AREIA/smb.antes" "$AREIA/smb.conf"
verdadeiro "regra nova apagada" test ! -e "$REGRA"
caso "passo seguinte falha: a regra antiga volta"
echo "# antiga" > "$REGRA"
saida=$(p "debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(samba_log_auth grupo); groupadd() { return 1; }; debkit_executar_plano; echo RC=\$?")
contem "RC=1" "$saida"; igual "# antiga" "$(cat "$REGRA")"
caso "logrotate recusa a regra: a própria ação é desfeita"
rm -f "$REGRA"
saida=$(aplicar "logrotate() { return 1; };")
contem "RC=1" "$saida"; verdadeiro "smb.conf de volta" cmp -s "$AREIA/smb.antes" "$AREIA/smb.conf"; verdadeiro "regra apagada" test ! -e "$REGRA"
caso "filtro com defeito: a conferência recusa e nada muda"
md5=$(md5sum < "$AREIA/smb.conf")
saida=$(p "debkit_samba_filtro_auth() { sed 's/workgroup = TESTE/workgroup = OUTRO/'; }; DEBKIT_SAMBA_LOGLEVEL_NOVO=x; debkit_acao_samba_log_auth; echo RC=\$?")
contem "RC=1" "$saida"; contem "mais do que o pretendido" "$saida"; igual "$md5" "$(md5sum < "$AREIA/smb.conf")"
caso "inglês"
contem "Samba authentication log is off" "$(p "DEBKIT_IDIOMA=en; debkit_verificar_ambiente >/dev/null; printf '%s\n' \"\${DEBKIT_VERIF[@]}\"")"

real_intacto
resumo
