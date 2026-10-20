#!/usr/bin/env bash
# Testes dos logins (Fase 3, tarefa 3.2; decisões na seção 3.8): leitura do
# log de autenticação (atual e girados, .gz também), falhas por usuário e
# máquina na janela de dias, último login de cada usuário e tela. Log
# simulado no sandbox; a prova com logins de verdade está em
# t23b_logins_real.sh.
source "$(dirname "$0")/lib.sh"
sandbox

# Uma linha do log como o Samba grava: ev <data> <status> <usuário> <endereço> [tipo]
ev() {
    printf '  {"timestamp": "%s.123456-0300", "type": "%s", "%s": {"eventId": 4625, "status": "%s", "remoteAddress": "%s", "clientDomain": "WORKGROUP", "clientAccount": "%s", "workstation": "PC"}}\n' \
        "$1" "${5:-Authentication}" "${5:-Authentication}" "$2" "$4" "$3"
}
dia() { date -d "$1" '+%Y-%m-%dT%H:%M:%S'; }
br()  { date -d "$1" '+%d/%m/%Y %H:%M'; }
D1=$(dia '-1 day 10:00'); D2=$(dia '-2 days 09:30'); D3=$(dia '-3 days 15:00')
D20=$(dia '-20 days 08:00'); D40=$(dia '-40 days 08:00'); H=$(dia 'today 07:15')
LOGF="$SANDBOX/debkit-auth.json"
montar_log() {
    rm -f "$LOGF" "$LOGF".*
    { ev "$D40" NT_STATUS_OK dkt_ana "ipv4:192.168.0.10:5000"
      ev "$D40" NT_STATUS_WRONG_PASSWORD dkt_ana "ipv4:192.168.0.10:5001"; } | gzip > "$LOGF.2.gz"
    { ev "$D20" NT_STATUS_OK dkt_bruno "ipv4:192.168.0.22:5000"
      ev "$D20" NT_STATUS_NO_SUCH_USER fulano "ipv4:192.168.0.99:5000"; } > "$LOGF.1"
    { ev "$D3" NT_STATUS_WRONG_PASSWORD dkt_ana "ipv4:192.168.0.10:6000"
      ev "$D2" NT_STATUS_WRONG_PASSWORD DKT_Ana "ipv4:192.168.0.10:6001"
      ev "$D1" NT_STATUS_ACCOUNT_DISABLED dkt_ana "ipv4:192.168.0.10:6002"
      ev "$D2" NT_STATUS_WRONG_PASSWORD dkt_ana "ipv4:10.0.0.5:6003"
      ev "$D1" NT_STATUS_NO_SUCH_USER administrador "ipv6:[fe80::1]:6004"
      ev "$D1" NT_STATUS_OK "" "ipv4:192.168.0.30:6005"
      ev "$D1" NT_STATUS_OK dkt_bruno "ipv4:192.168.0.23:6006" Authorization
      ev "$H" NT_STATUS_OK dkt_ana "ipv4:192.168.0.11:6007"
      echo "lixo que não é json"; } > "$LOGF"
}
CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;
     debkit_samba_usuarios_dados() { printf '%s\n' 'dkt_ana|Ana|arquivos|ativa|||' 'dkt_bruno|Bruno|arquivos|desativada|||' \
         'dkt_carla|Carla|arquivos|ativa|||' 'dkt_sem|Sem|servidor|nao|||' 'dkt_so|||so_samba|||'; };"
p() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
tela() { printf '\n' | p "$1; debkit_diag_tela_logins; echo RC=\$?"; }
preparar_sandbox
montar_log

# ════════════════════════════════════════════════════════════════════════════
# Leitura do log
# ════════════════════════════════════════════════════════════════════════════
caso "eventos: atual, .1 e .gz; data local, usuário em minúsculas, IP sem porta"
saida=$(p debkit_diag_auth_eventos)
contem "${D40/T/ }|NT_STATUS_OK|dkt_ana|192.168.0.10" "$saida" "do .2.gz"
contem "${D20/T/ }|NT_STATUS_NO_SUCH_USER|fulano|192.168.0.99" "$saida" "do .1"
contem "${D2/T/ }|NT_STATUS_WRONG_PASSWORD|dkt_ana|192.168.0.10" "$saida" "DKT_Ana vira dkt_ana"
contem "|administrador|fe80::1" "$saida" "IPv6 sem colchetes e sem porta"
nao_contem "||" "$saida" "anônimo fica de fora"
nao_contem "192.168.0.23" "$saida" "só eventos de autenticação"
nao_contem "lixo" "$saida"
igual 10 "$(wc -l <<< "$saida")"
caso "início do registro: o evento mais antigo (mesmo no .gz)"
igual "${D40/T/ }" "$(p debkit_diag_auth_inicio)"

caso "falhas: só na janela, por usuário e máquina, a mais recente primeiro"
saida=$(p "debkit_diag_falhas '$(date -d '-7 days' '+%Y-%m-%d %H:%M:%S')'")
igual "$(printf '%s\n' "dkt_ana|192.168.0.10|3|${D1/T/ }|NT_STATUS_ACCOUNT_DISABLED" \
    "administrador|fe80::1|1|${D1/T/ }|NT_STATUS_NO_SUCH_USER" \
    "dkt_ana|10.0.0.5|1|${D2/T/ }|NT_STATUS_WRONG_PASSWORD")" "$saida"
caso "falhas: janela maior pega os girados"
saida=$(p "debkit_diag_falhas '$(date -d '-60 days' '+%Y-%m-%d %H:%M:%S')'")
contem "dkt_ana|192.168.0.10|4|" "$saida"; contem "fulano|192.168.0.99|1|" "$saida"

caso "último login com sucesso de cada usuário"
igual "$(printf '%s\n' "dkt_ana|${H/T/ }|192.168.0.11" "dkt_bruno|${D20/T/ }|192.168.0.22")" "$(p debkit_diag_ultimos_logins)"

caso "motivos em palavras; status desconhecido aparece como veio"
for x in "WRONG_PASSWORD:senha errada" "NO_SUCH_USER:usuário inexistente" "ACCOUNT_DISABLED:conta desativada" \
         "ACCOUNT_LOCKED_OUT:conta bloqueada" "PASSWORD_EXPIRED:senha expirada" "PASSWORD_MUST_CHANGE:senha expirada" \
         "ACCOUNT_EXPIRED:conta expirada" "INVALID_LOGON_HOURS:fora do horário" "LOGON_FAILURE:login recusado" \
         "OUTRO_QUALQUER:NT_STATUS_OUTRO_QUALQUER"; do
    contem "${x#*:}" "$(p "debkit_diag_motivo NT_STATUS_${x%%:*}")" "${x%%:*}"
done

caso "sem log nenhum: nada"
igual "" "$(p "DEBKIT_AUTH_LOG='$SANDBOX/nao-existe.json'; debkit_diag_auth_eventos; debkit_diag_auth_inicio")"

# ════════════════════════════════════════════════════════════════════════════
# Tela
# ════════════════════════════════════════════════════════════════════════════
caso "tela: início do registro, falhas da semana com motivo"
saida=$(tela "debkit_samba_auth_ligado() { :; }")
contem "Registro desde $(br "$D40")" "$saida"
contem "Falhas de login nos últimos 7 dias" "$saida"
contem "Tentativas" "$saida"; contem "Motivo" "$saida"
linha=$(grep "192.168.0.10 " <<< "$saida")
contem "dkt_ana" "$linha"; contem " 3 " "$linha"; contem "$(br "$D1")" "$linha"; contem "conta desativada" "$linha"
contem "usuário inexistente" "$(grep 'administrador' <<< "$saida")"
nao_contem "fulano" "$saida" "falha de 20 dias atrás fica fora da janela"
nao_contem "desligado" "$saida"
contem "RC=0" "$saida"
caso "tela: último login de cada usuário com conta no Samba"
contem "$(br "$H")  192.168.0.11" "$(grep '^  dkt_ana ' <<< "$saida" | tail -1)"
contem "$(br "$D20")  192.168.0.22 (desativada)" "$(grep '^  dkt_bruno ' <<< "$saida")"
contem "nenhum desde o início do registro" "$(grep '^  dkt_carla ' <<< "$saida")"
contem "nenhum desde o início do registro" "$(grep '^  dkt_so ' <<< "$saida")" "conta só no Samba"
nao_contem "dkt_sem" "$saida" "sem conta no Samba fica de fora"
caso "tela: limite de linhas de falha"
contem "... e mais 1 (usuário e máquina)." "$(tela "debkit_samba_auth_ligado() { :; }; DEBKIT_DIAG_MAX_FALHAS=2")"
caso "tela: sem falhas na janela"
ev "$H" NT_STATUS_OK dkt_ana "ipv4:1.2.3.4:1" > "$SANDBOX/x.json"
saida=$(tela "debkit_samba_auth_ligado() { :; }; DEBKIT_DIAG_DIAS=1; DEBKIT_AUTH_LOG='$SANDBOX/x.json'")
contem "Nenhuma falha de login nos últimos 1 dias." "$saida"; contem "$(br "$H")  1.2.3.4" "$saida"
caso "tela: log desligado avisa (e mostra o que já foi registrado)"
saida=$(tela "debkit_samba_auth_ligado() { return 1; }")
contem "log de autenticação do Samba está desligado" "$saida"; contem "debkit --preparar" "$saida"; contem "dkt_ana" "$saida"
caso "tela: nada registrado"
saida=$(tela "DEBKIT_AUTH_LOG='$SANDBOX/vazio.json'")
contem "Nenhum login registrado ainda em $SANDBOX/vazio.json" "$saida"; contem "RC=0" "$saida"
caso "menu Samba > 4) Diagnóstico > 2) Logins"
saida=$(pty 0.6 "bash $DEBKIT" 1 4 2 "" 0 0 0)
contem "2) Logins (falhas e último login de cada usuário)" "$saida"; contem "Registro desde" "$saida"
caso "inglês"
saida=$(tela "DEBKIT_IDIOMA=en; debkit_samba_auth_ligado() { :; }")
contem "Login failures in the last 7 days" "$saida"; contem "account disabled" "$saida"; contem "Last login of each Samba user" "$saida"

real_intacto
resumo
