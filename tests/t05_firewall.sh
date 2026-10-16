#!/usr/bin/env bash
# Testes da tarefa 0.5 - firewall (ufw/firewalld/ip SIMULADOS).
# A prova com o ufw real fica em t05b_ufw_real.sh (só com DEBKIT_TESTE_REAL=1).
source "$(dirname "$0")/lib.sh"
caixa_de_areia

# Estado dos simuladores (arquivos na areia)
#   ufw: $AREIA/ufw.ativo (existe = ativo), $AREIA/ufw.padrao (allow|deny),
#        $AREIA/ufw.regras (linhas "ufw allow ..."), $AREIA/ufw.falhar (rede que falha)
#   firewalld: $AREIA/fwd.ativo, $AREIA/fwd.regras (rich rules), $AREIA/fwd.servicos
#   comandos: $AREIA/cmds (registro dos comandos de alteração)
SIM="
ip() { printf '%s\n' \"\$(cat '$AREIA/rotas')\"; };
debkit_tem_comando() { case \"\$1\" in ufw) [ -e '$AREIA/tem_ufw' ];; firewall-cmd) [ -e '$AREIA/tem_fwd' ];; nft|iptables) [ -e '$AREIA/tem_nft' ];; *) command -v \"\$1\" >/dev/null 2>&1;; esac; };
nft() { cat '$AREIA/nft' 2>/dev/null; };
debkit_ufw() {
  case \"\$1\" in
    status) if [ -e '$AREIA/ufw.ativo' ]; then echo 'Status: active'; [ \"\$2\" == verbose ] && echo \"Default: \$(cat '$AREIA/ufw.padrao' 2>/dev/null || echo deny) (incoming), allow (outgoing)\"; else echo 'Status: inactive'; fi ;;
    show)   cat '$AREIA/ufw.regras' 2>/dev/null ;;
    allow)  echo \"ufw \$*\" >> '$AREIA/cmds'; [[ \"\$*\" == *\"\$(cat '$AREIA/ufw.falhar' 2>/dev/null || echo NADA)\"* ]] && return 1
            shift; echo \"ufw allow \$*\" | sed \"s/ comment .*//; s/\$/ comment 'debkit: Samba'/\" >> '$AREIA/ufw.regras' ;;
    delete) echo \"ufw \$*\" >> '$AREIA/cmds'; shift 2; grep -vF \"ufw allow \$*\" '$AREIA/ufw.regras' > '$AREIA/ufw.tmp'; mv '$AREIA/ufw.tmp' '$AREIA/ufw.regras' ;;
  esac
};
firewall-cmd() {
  case \"\$*\" in
    --state) [ -e '$AREIA/fwd.ativo' ] ;;
    --get-default-zone) echo public ;;
    *--query-service=samba*) grep -qx samba '$AREIA/fwd.servicos' 2>/dev/null ;;
    *--query-port=*) return 1 ;;
    *--list-rich-rules*) cat '$AREIA/fwd.regras' 2>/dev/null ;;
    *--get-target*) echo default ;;
    *--add-rich-rule=*) echo \"fwd \$*\" >> '$AREIA/cmds'; echo \"\${*##*--add-rich-rule=}\" >> '$AREIA/fwd.regras' ;;
    *--remove-rich-rule=*) echo \"fwd \$*\" >> '$AREIA/cmds'; r=\"\${*##*--remove-rich-rule=}\"; grep -vxF \"\$r\" '$AREIA/fwd.regras' > '$AREIA/fwd.tmp'; mv '$AREIA/fwd.tmp' '$AREIA/fwd.regras' ;;
    --reload) echo 'fwd reload' >> '$AREIA/cmds' ;;
  esac
};"
f() { bash -c "source '$DEBKIT'; debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\"; $SIM $1" 2>&1; }
estado() {   # zera o estado dos simuladores
    rm -f "$AREIA"/{ufw.*,fwd.*,tem_*,cmds,nft}
    printf '10.99.8.0/21 dev wg0 proto kernel scope link src 10.99.8.1\n192.168.76.0/22 dev eth0 proto dhcp scope link src 192.168.76.200 metric 1002\n' > "$AREIA/rotas"
}
verif_fw() { f 'debkit_verificar_ambiente >/dev/null; printf "%s\n" "${DEBKIT_VERIF[@]}" | grep "^firewall"; debkit_montar_plano; echo "TIPO=$DEBKIT_FW_TIPO LIBERA=$DEBKIT_FW_LIBERA PLANO=${DEBKIT_PLANO[*]}"'; }

# ── Redes locais ─────────────────────────────────────────────────────────────
caso "redes locais: DHCP conta, docker/bridge/link-local/rota de host não"
estado
printf '%s\n' \
  '192.168.76.0/22 dev eth0 proto dhcp scope link src 192.168.76.200 metric 1002' \
  '10.99.8.0/21 dev wg0 proto kernel scope link src 10.99.8.1' \
  '172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1' \
  '172.18.0.0/16 dev br-1a2b3c proto kernel scope link src 172.18.0.1' \
  '192.168.122.0/24 dev virbr0 proto kernel scope link src 192.168.122.1' \
  '169.254.0.0/16 dev eth0 scope link metric 1000' \
  '192.168.76.1 dev eth0 scope link' \
  '10.0.0.0/24 dev eth0 proto kernel scope link src 10.0.0.5' > "$AREIA/rotas"
igual "10.0.0.0/24 10.99.8.0/21 192.168.76.0/22" "$(f 'debkit_redes_locais' | tr '\n' ' ' | sed 's/ $//')"

# ── Detecção ─────────────────────────────────────────────────────────────────
caso "nenhum firewall"
estado
saida=$(verif_fw)
contem "Nenhum firewall ativo" "$saida"; contem "TIPO= LIBERA=0" "$saida"; nao_contem "firewall" "$(grep PLANO <<< "$saida")"
caso "ufw instalado mas inativo = nenhum firewall"
estado; touch "$AREIA/tem_ufw"
contem "Nenhum firewall ativo" "$(verif_fw)"
caso "ufw ativo, padrão deny, sem regra: bloqueia e entra no plano"
estado; touch "$AREIA/tem_ufw" "$AREIA/ufw.ativo"
saida=$(verif_fw)
contem "ufw ativo e NÃO libera o Samba" "$saida"; contem "TIPO=ufw LIBERA=0" "$saida"; contem "PLANO=" "$saida"
contem "firewall" "$(grep PLANO <<< "$saida")"
caso "ufw ativo com política padrão allow: libera"
echo allow > "$AREIA/ufw.padrao"
contem "ufw ativo e libera o Samba (porta 445)" "$(verif_fw)"
caso "ufw ativo com regra do administrador para 445: libera (não duplica)"
echo deny > "$AREIA/ufw.padrao"; echo "ufw allow 445/tcp" > "$AREIA/ufw.regras"
saida=$(verif_fw)
contem "libera o Samba" "$saida"; nao_contem "firewall" "$(grep PLANO <<< "$saida")"
caso "firewalld ativo sem samba: bloqueia; com o serviço samba: libera"
estado; touch "$AREIA/tem_fwd" "$AREIA/fwd.ativo"
contem "firewalld ativo e NÃO libera" "$(verif_fw)"
echo samba > "$AREIA/fwd.servicos"
contem "firewalld ativo e libera" "$(verif_fw)"
caso "regras nftables próprias: só aviso"
estado; touch "$AREIA/tem_nft"
printf 'table inet filter {\n  chain input {\n    type filter hook input priority 0; policy drop;\n  }\n}\n' > "$AREIA/nft"
saida=$(verif_fw)
contem "Regras próprias de nftables/iptables" "$saida"; nao_contem "firewall" "$(grep PLANO <<< "$saida")"

# ── Ação ─────────────────────────────────────────────────────────────────────
caso "ufw: cria uma regra por rede local, só porta 445/tcp, com comentário"
estado; touch "$AREIA/tem_ufw" "$AREIA/ufw.ativo"
saida=$(f 'debkit_verificar_ambiente >/dev/null; debkit_montar_plano; debkit_mostrar_plano; DEBKIT_PLANO=(firewall); debkit_executar_plano; echo RC=$?')
contem "Liberar o Samba (porta 445/tcp) no ufw só para as redes locais: 10.99.8.0/21, 192.168.76.0/22" "$saida" "descrição mostra as redes"
contem "RC=0" "$saida"
cmds=$(cat "$AREIA/cmds")
contem "ufw allow from 10.99.8.0/21 to any port 445 proto tcp comment debkit: Samba" "$cmds"
contem "ufw allow from 192.168.76.0/22 to any port 445 proto tcp comment debkit: Samba" "$cmds"
igual 2 "$(grep -c '^ufw allow' "$AREIA/cmds")" "exatamente 2 regras"
nao_contem "any port 445 proto tcp" "$(grep -v 'from' "$AREIA/cmds")" "nenhuma regra sem origem (para qualquer um)"

caso "ufw: falha na 2ª regra desfaz a 1ª e mantém regras do administrador"
estado; touch "$AREIA/tem_ufw" "$AREIA/ufw.ativo"
echo "ufw allow 22/tcp" > "$AREIA/ufw.regras"
echo "192.168.76.0/22" > "$AREIA/ufw.falhar"
saida=$(f 'debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(firewall); debkit_executar_plano; echo RC=$?')
contem "RC=1" "$saida"; contem "Não foi possível criar a regra no ufw (192.168.76.0/22)" "$saida"
contem "ufw delete allow from 10.99.8.0/21 to any port 445 proto tcp" "$(cat "$AREIA/cmds")" "remove a regra que criou"
igual "ufw allow 22/tcp" "$(cat "$AREIA/ufw.regras")" "regra do administrador intacta; nada do debkit sobrou"

caso "ufw: regra criada mas não confirmada: desfaz"
estado; touch "$AREIA/tem_ufw" "$AREIA/ufw.ativo"
saida=$(f 'debkit_verificar_ambiente >/dev/null; debkit_fw_ufw_libera() { return 1; }; DEBKIT_PLANO=(firewall); debkit_executar_plano; echo RC=$?')
contem "RC=1" "$saida"; contem "não foi confirmada" "$saida"
igual 2 "$(grep -c '^ufw delete' "$AREIA/cmds")" "as 2 regras removidas"

caso "sem redes locais: não faz nada"
estado; touch "$AREIA/tem_ufw" "$AREIA/ufw.ativo"; : > "$AREIA/rotas"
saida=$(f 'debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(firewall); debkit_executar_plano; echo RC=$?')
contem "Nenhuma rede local encontrada" "$saida"; verdadeiro "nenhum comando" test ! -e "$AREIA/cmds"

caso "firewalld: regras rich por rede, reload, e desfazer remove as mesmas"
estado; touch "$AREIA/tem_fwd" "$AREIA/fwd.ativo"
saida=$(f 'debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(firewall); debkit_executar_plano; echo RC=$?')
contem "RC=0" "$saida"
contem 'rule family="ipv4" source address="192.168.76.0/22" port port="445" protocol="tcp" accept' "$(cat "$AREIA/fwd.regras")"
contem "fwd reload" "$(cat "$AREIA/cmds")"
f 'debkit_verificar_ambiente >/dev/null; DEBKIT_FW_CRIADAS=(10.99.8.0/21 192.168.76.0/22); debkit_fw_desfazer' >/dev/null
igual "" "$(cat "$AREIA/fwd.regras")" "desfazer removeu as duas"

caso "o firewall real não foi tocado"
verdadeiro "ufw não instalado/ativo de verdade" bash -c '! command -v ufw >/dev/null || ! LC_ALL=C ufw status 2>/dev/null | grep -q "Status: active"'

real_intacto

resumo
