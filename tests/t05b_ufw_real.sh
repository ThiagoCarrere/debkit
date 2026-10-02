#!/usr/bin/env bash
# Prova com o ufw REAL (tarefa 0.5): os comandos que o gsb usa para criar,
# reconhecer e remover as regras funcionam de verdade.
#
# Só roda com GSB_TESTE_REAL=1 e com o ufw instalado e INATIVO: com o ufw
# inativo as regras ficam só na configuração e NÃO filtram nada (provado
# abaixo comparando o "nft list ruleset" antes e depois). Nunca mexe num ufw
# ativo. Ao final, a configuração do ufw volta a ser idêntica.
source "$(dirname "$0")/lib.sh"

if [ "${GSB_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com o ufw real - rode com GSB_TESTE_REAL=1)"
    exit 0
fi
if ! command -v ufw >/dev/null; then
    echo "  (pulado: ufw não instalado)"
    exit 0
fi
if LC_ALL=C ufw status | grep -q '^Status: active'; then
    echo "  ufw ATIVO neste servidor: o teste não mexe em firewall em uso - abortando"
    exit 1
fi
caixa_de_areia

regras_ufw() { LC_ALL=C ufw show added 2>/dev/null; }
REGRAS_ANTES=$(regras_ufw)
TABELAS_ANTES=$(nft list tables 2>/dev/null)
# Filtragem efetiva = chains/regras no kernel. (O próprio "ufw allow" com o
# ufw INATIVO cria as tabelas "ip filter"/"ip6 filter" VAZIAS - sem chains,
# não filtram nada; com o ufw ativo, que é o uso real do gsb, elas já existem.)
filtragem() { nft list ruleset 2>/dev/null | grep -cE '^[[:space:]]*(chain|type filter|policy|ip |tcp |udp |counter|drop|reject|accept)'; }
FILTRAGEM_ANTES=$(filtragem)
# Remove as tabelas vazias que o ufw criar, se não existiam antes
limpar_tabelas_vazias() {
    local t
    for t in "ip filter" "ip6 filter"; do
        grep -qx "table $t" <<< "$TABELAS_ANTES" && continue
        # shellcheck disable=SC2086  # "ip filter" precisa virar 2 argumentos
        nft list table $t 2>/dev/null | grep -q chain || nft delete table $t 2>/dev/null
    done
}
trap 'limpar_tabelas_vazias; rm -rf -- "${AREIA:?}"; getent group "$GRUPO_TESTE" >/dev/null && groupdel "$GRUPO_TESTE"' EXIT
s() { bash -c "source '$GSB'; gsb_conf_carregar \"\$GSB_CONF_ARQUIVO\"; GSB_FW_TIPO=ufw; $1" 2>&1; }

caso "ufw inativo: o gsb não o considera um firewall ativo"
contem "Nenhum firewall ativo" "$(s 'gsb_verificar_ambiente >/dev/null; printf "%s\n" "${GSB_VERIF[@]}"')"

caso "criar as regras com o ufw real"
saida=$(s 'gsb_acao_firewall; echo RC=$?; printf "CRIADAS=%s\n" "${GSB_FW_CRIADAS[*]}"')
contem "RC=0" "$saida"
regras=$(regras_ufw)
for rede in $(bash -c "source '$GSB'; gsb_redes_locais"); do
    contem "ufw allow from $rede to any port 445 proto tcp comment 'gsb: Samba'" "$regras" "regra para $rede"
done
caso "o reconhecimento do gsb vê as regras reais"
igual 0 "$(s 'gsb_fw_ufw_libera; echo $?')"

caso "desfazer remove exatamente as regras do gsb"
s "GSB_FW_CRIADAS=($(bash -c "source '$GSB'; gsb_redes_locais" | tr '\n' ' ')); gsb_fw_desfazer" >/dev/null
igual "$REGRAS_ANTES" "$(regras_ufw)" "configuração do ufw idêntica à do início"
igual 1 "$(s 'gsb_fw_ufw_libera; echo $?')" "não reconhece mais liberação"

caso "nada passou a ser filtrado"
verdadeiro "ufw continua inativo" bash -c '! LC_ALL=C ufw status | grep -q "Status: active"'
igual "$FILTRAGEM_ANTES" "$(filtragem)" "nenhuma chain/regra nova no kernel (nft)"
limpar_tabelas_vazias
igual "$TABELAS_ANTES" "$(nft list tables 2>/dev/null)" "tabelas do kernel iguais ao início"

resumo
