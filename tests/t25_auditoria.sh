#!/usr/bin/env bash
# Testes da consulta à auditoria (Fase 3, tarefa 3.4; decisões na seção
# 3.8): leitura do log do debkit (atual e girados, .gz também), filtros por
# período, por quem foi afetado e por tipo de ação, e a tela. Log simulado no
# sandbox; a prova com ações de verdade está em t25b_auditoria_real.sh.
source "$(dirname "$0")/lib.sh"
sandbox

dia() { date -d "$1" '+%Y-%m-%dT%H:%M:%S-0300'; }
iso() { date -d "$1" '+%Y-%m-%d'; }
br()  { date -d "$1" '+%d/%m/%Y'; }
H=$(dia 'today 08:00'); H2=$(dia 'today 08:00'); D3=$(dia '-3 days 10:00'); D40=$(dia '-40 days 10:00')
LOGF="$SANDBOX/debkit.log"
montar_log() {
    rm -f "$LOGF" "$LOGF".*
    printf '%s\n' "$D40 root[1] usuario_criar nome=antigo tipo=arquivos uid=1100 grupos= resultado=ok" | gzip > "$LOGF.2.gz"
    printf '%s\n' "$D3 thiago[2] sessao_inicio v0.1.0" \
                  "$D3 thiago[2] grupo_criar nome=gp_x gid=1200 membros=ana,bia resultado=ok" \
                  "$D3 thiago[2] senha_trocar nome=ana alvo=samba resultado=falha motivo=samba" > "$LOGF.1"
    printf '%s\n' "linha estranha sem data" \
                  "$H root[3] shr_criar nome=docs pasta=/srv/docs grupo=gp_x resultado=ok" \
                  "$H2 root[3] shr_ajustar pasta=/srv/docs grupo=gp_x itens=4 resultado=ok" \
                  "$H root[3] grupo_membros grupo=gp_x entraram=carla sairam=bia resultado=ok" \
                  "$H root[3] sessao_desconectar usuario=ana ip=192.168.0.10 pid=99 resultado=ok" \
                  "$H root[3] conf_definir chave=SHARES_BASE valor=/srv" \
                  "$H root[3] acao_nova x=1" \
                  "$H root[3] sessao_fim motivo=normal" > "$LOGF"
}
CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;"
p() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
f() { p "debkit_aud_filtrar '$1' '$2' '$3' '$4'" | cut -d'|' -f3 | tr '\n' ' '; }
tela() { local pre="$1"; shift; printf '%s\n' "$@" | p "$pre; debkit_diag_tela_auditoria; echo RC=\$?"; }
preparar_sandbox
montar_log

# ════════════════════════════════════════════════════════════════════════════
# Leitura e filtros
# ════════════════════════════════════════════════════════════════════════════
caso "tudo (menos o uso): atual, .1 e .gz; a mais recente primeiro, inclusive no mesmo segundo"
igual "acao_nova conf_definir sessao_desconectar grupo_membros shr_ajustar shr_criar senha_trocar grupo_criar usuario_criar " "$(f "" "" "" "")"
caso "campos: data, quem (sem o pid), ação e detalhes"
contem "${H:0:10} ${H:11:8}|root|shr_criar|nome=docs pasta=/srv/docs grupo=gp_x resultado=ok" "$(p "debkit_aud_filtrar '' '' '' shr")"
contem "|thiago|grupo_criar|nome=gp_x gid=1200 membros=ana,bia resultado=ok" "$(p "debkit_aud_filtrar '' '' '' grupos")"
caso "período: desde, até e um dia só"
igual "senha_trocar grupo_criar usuario_criar " "$(f "" "$(iso '-1 day')" "" "")"
igual "acao_nova conf_definir sessao_desconectar grupo_membros shr_ajustar shr_criar senha_trocar grupo_criar " "$(f "$(iso '-29 days')" "" "" "")"
igual "senha_trocar grupo_criar " "$(f "$(iso '-3 days')" "$(iso '-3 days')" "" "")"
caso "afetado: valor exato de qualquer chave, inclusive dentro de listas"
igual "sessao_desconectar senha_trocar grupo_criar " "$(f "" "" ana "")" "ana: usuario=, nome=, membros="
igual "grupo_membros grupo_criar " "$(f "" "" bia "")" "bia: membros= e sairam="
igual "shr_ajustar shr_criar " "$(f "" "" /srv/docs "")" "pasta"
igual "" "$(f "" "" an "")" "parte do nome não conta"
igual "" "$(f "" "" ninguem "")"
caso "tipo"
igual "senha_trocar usuario_criar " "$(f "" "" "" usuarios)"
igual "grupo_membros grupo_criar " "$(f "" "" "" grupos)"
igual "shr_ajustar shr_criar " "$(f "" "" "" shr)"
igual "sessao_desconectar " "$(f "" "" "" sessoes)"
igual "conf_definir " "$(f "" "" "" preparacao)"
igual "sessao_fim sessao_inicio " "$(f "" "" "" uso)"
caso "filtros juntos"
igual "grupo_criar " "$(f "$(iso '-5 days')" "" ana grupos)"
caso "sem log: nada"
igual "" "$(p "DEBKIT_LOG='$SANDBOX/nao-existe.log'; debkit_aud_filtrar '' '' '' ''")"
caso "ação em palavras; desconhecida aparece como veio"
igual "criar compartilhamento" "$(p "debkit_aud_rotulo shr_criar")"
igual "acao_nova" "$(p "debkit_aud_rotulo acao_nova")"
igual "create share" "$(p "DEBKIT_IDIOMA=en; debkit_aud_rotulo shr_criar")"

# ════════════════════════════════════════════════════════════════════════════
# Tela
# ════════════════════════════════════════════════════════════════════════════
caso "tela: Enter em tudo = 30 dias, todos menos o uso"
saida=$(tela ":" "" "" "")
contem "Filtro: últimos 30 dias, todos os tipos" "$saida"
contem "$(br today) 08:00  root    criar compartilhamento" "$saida"
contem "membros do grupo" "$saida"; contem "grupo=gp_x entraram=carla sairam=bia resultado=ok" "$saida"
contem "thiago" "$saida"; nao_contem "abriu o debkit" "$saida"; nao_contem "antigo" "$saida" "40 dias atrás fica fora"
contem "8 ação(ões)." "$saida"
contem "✘ $(br '-3 days') 10:00  thiago  trocar senha" "$saida"; contem "1 com falha (marcadas com ✘)." "$saida"
contem "RC=0" "$saida"
caso "tela: um dia, um afetado e um tipo"
saida=$(tela ":" "$(br '-3 days')" ana 1)
contem "Filtro: dia $(br '-3 days'), ana, Usuários" "$saida"
contem "trocar senha" "$saida"; nao_contem "criar grupo" "$saida"; contem "1 ação(ões)." "$saida"
caso "tela: últimos N dias e o uso"
saida=$(tela ":" 60 "" 6)
contem "Filtro: últimos 60 dias, Uso do debkit" "$saida"; contem "abriu o debkit" "$saida"; contem "saiu do debkit" "$saida"
caso "tela: período e tipo inválidos pedem de novo"
saida=$(tela ":" abc 0 31/02/2026 7 "" 9 "")
contem "Período inválido: 'abc'" "$saida"; contem "Período inválido: '0'" "$saida"; contem "Período inválido: '31/02/2026'" "$saida"
contem "Opção inválida: '9'" "$saida"; contem "Filtro: últimos 7 dias, todos os tipos" "$saida"
caso "tela: nada encontrado"
contem "Nenhuma ação encontrada com esse filtro." "$(tela ":" "" ninguem "")"
caso "tela: limite de linhas"
contem "Mostrando as 3 mais recentes de 8" "$(tela "DEBKIT_AUD_MAX=3" "" "" "")"
caso "tela: log vazio"
contem "Nada registrado ainda em $SANDBOX/vazio.log" "$(tela "DEBKIT_LOG='$SANDBOX/vazio.log'" "")"
caso "menu Samba > 4) Diagnóstico > 4) Auditoria"
saida=$(pty 0.6 "bash $DEBKIT" 1 4 4 "" "" "" "" 0 0 0)
contem "4) Auditoria (o que foi feito pelo debkit)" "$saida"; contem "Filtro: últimos 30 dias" "$saida"
caso "inglês"
saida=$(tela "DEBKIT_IDIOMA=en" "" "" "")
contem "Filter: last 30 days, all types" "$saida"; contem "create share" "$saida"; contem "1 failed" "$saida"

real_intacto
resumo
