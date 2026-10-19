#!/usr/bin/env bash
# Testes do item da preparação "map to guest = never" (Fase 2, decisão de
# 19/10/2026): com "bad user" (padrão do Debian), quem entra com um nome que
# não existe vira convidado em vez de ser recusado. smb.conf da areia; a
# prova com login de verdade está em t16b_convidado_real.sh.
source "$(dirname "$0")/lib.sh"
caixa_de_areia

CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;
     debkit_samba_recarregar() { echo reload >> '$AREIA/reloads'; };"
p() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
efetivo() { testparm -s "$AREIA/smb.conf" 2>/dev/null; }
valor() { testparm -s --parameter-name='map to guest' "$AREIA/smb.conf" 2>/dev/null; }
smb_teste() { printf '%b' "$1" > "$AREIA/smb.conf"; isolar_smb_conf "$AREIA/smb.conf"; rm -rf "$AREIA/conf-bkp"; : > "$AREIA/reloads"; }
plano() { p "debkit_verificar_ambiente >/dev/null; printf '%s\n' \"\${DEBKIT_VERIF[@]}\" | grep '^samba'; debkit_montar_plano; echo \"PLANO=\${DEBKIT_PLANO[*]}\""; }
aplicar() { p "debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(samba_sem_convidado); debkit_executar_plano; echo RC=\$?"; }
SMB_DEBIAN='[global]\n   workgroup = TESTE\n   server role = standalone server\n# Isto faz quem não existe virar convidado\n   map to guest = bad user\n   usershare allow guests = yes\n\n[dados]\n   path = /tmp\n'

caso "bad user: avisa e entra no plano"
smb_teste "$SMB_DEBIAN"
saida=$(plano)
contem "\"map to guest = Bad User\"" "$saida"; contem "vira convidado em vez de ser recusado" "$saida"
contem "samba_sem_convidado" "$(grep '^PLANO=' <<< "$saida")"
contem "Recusar no $AREIA/smb.conf o login de quem não existe" "$(p "debkit_verificar_ambiente >/dev/null; debkit_montar_plano; debkit_mostrar_plano")"
caso "bad user: muda para never pela edição segura (linha trocada no lugar, só isso muda)"
antes=$(efetivo)
contem "RC=0" "$(aplicar)"
igual "Never" "$(valor)"
igual "$(grep -vxF $'\tmap to guest = Bad User' <<< "$antes")" "$(efetivo)" "configuração em vigor: só a linha do map to guest saiu"
contem "   map to guest = never" "$(sed -n '/Isto faz quem não existe/{n;p}' "$AREIA/smb.conf")" "no mesmo lugar, depois do comentário"
igual 1 "$(grep -ci 'map to guest' "$AREIA/smb.conf")" "uma linha só"
contem "usershare allow guests = yes" "$(cat "$AREIA/smb.conf")" "o resto do [global] não muda"
verdadeiro "backup em conf-bkp" test -n "$(find "$AREIA/conf-bkp" -name 'smb.conf.*')"
igual 1 "$(grep -c reload "$AREIA/reloads")" "Samba recarregado"
caso "idempotente: depois não entra mais no plano"
nao_contem "samba_sem_convidado" "$(plano)"; nao_contem "vira convidado" "$(plano)"
caso "bad password e nome sem espaços / repetido"
smb_teste '[global]\n\tmap to guest=bad user\n   MapToGuest = Bad Password\n[dados]\n   path = /tmp\n'   # vale a última
contem "\"map to guest = Bad Password\"" "$(plano)" "bad password também"
contem "RC=0" "$(aplicar)"
igual 1 "$(grep -ciE 'map ?to ?guest' "$AREIA/smb.conf")" "repetida saiu"; igual "Never" "$(valor)"
caso "never ou ausente (padrão): nada no plano"
smb_teste '[global]\n   workgroup = TESTE\n[dados]\n   path = /tmp\n'
nao_contem "samba_sem_convidado" "$(plano)"
smb_teste '[global]\n   map to guest = Never\n[dados]\n   path = /tmp\n'
nao_contem "samba_sem_convidado" "$(plano)"
caso "map to guest fora do [global] não é mexido"
smb_teste '[global]\n   map to guest = bad user\n[dados]\n   path = /tmp\n   comment = map to guest = bad user\n'
contem "RC=0" "$(aplicar)"
contem "comment = map to guest = bad user" "$(cat "$AREIA/smb.conf")"
caso "passo seguinte falha: o smb.conf volta"
smb_teste "$SMB_DEBIAN"; cp "$AREIA/smb.conf" "$AREIA/smb.antes"
saida=$(p "debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(samba_sem_convidado grupo); groupadd() { return 1; }; debkit_executar_plano; echo RC=\$?")
contem "RC=1" "$saida"; contem "restaurado do backup" "$saida"
verdadeiro "smb.conf de volta" cmp -s "$AREIA/smb.antes" "$AREIA/smb.conf"
caso "filtro com defeito: a conferência recusa e nada muda"
smb_teste "$SMB_DEBIAN"; md5=$(md5sum < "$AREIA/smb.conf")
saida=$(p "debkit_samba_filtro_sem_convidado() { sed 's/workgroup = TESTE/workgroup = OUTRO/; s/map to guest = bad user/map to guest = never/'; }; debkit_acao_samba_sem_convidado; echo RC=\$?")
contem "RC=1" "$saida"; contem "mais do que o pretendido" "$saida"; igual "$md5" "$(md5sum < "$AREIA/smb.conf")"
caso "filtro genérico: sem a linha, põe no fim do [global]"
igual "$(printf '[global]\n   workgroup = X\n   map to guest = never\n[d]\n   path = /tmp')" \
      "$(printf '[global]\n   workgroup = X\n[d]\n   path = /tmp\n' | p "debkit_samba_filtro_global 'map to guest' never")"
caso "inglês"
smb_teste "$SMB_DEBIAN"
contem "becomes a guest instead of being refused" "$(p "DEBKIT_IDIOMA=en; debkit_verificar_ambiente >/dev/null; printf '%s\n' \"\${DEBKIT_VERIF[@]}\"")"

real_intacto
resumo
