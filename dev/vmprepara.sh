#!/usr/bin/env bash
# dev/vmprepara.sh - instala na VM de DESENVOLVIMENTO (ex: logo depois do
# dev/vmnova.sh) as ferramentas que a suíte de testes usa.
#
# NÃO instala o Samba nem prepara o servidor: isso é trabalho do próprio
# debkit (./debkit --preparar), e é justamente o que se testa numa VM limpa.
# O debkit nunca instala estas ferramentas no servidor de quem usa.
#
#   - "shellcheck": qualidade do código (tests/t01)
#   - "smbclient": login de verdade no Samba (provas reais t07b/t09b)
#   - "ufw": prova do firewall (t05b) - instalado e mantido INATIVO
#
# Uso: dev/vmprepara.sh [--simular]
# Repetir não estraga nada (o apt só instala o que falta).

REPO="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
FERRAMENTAS=(shellcheck smbclient ufw)
[ -n "${VMPREPARA_FERRAMENTAS:-}" ] && read -ra FERRAMENTAS <<< "$VMPREPARA_FERRAMENTAS"   # (testes)
APT="${VMPREPARA_APT:-apt-get}"
simular=0

erro() { echo "vmprepara: $*" >&2; exit 1; }

case "${1:-}" in
    "")         ;;
    --simular)  simular=1 ;;
    -h|--ajuda) sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          erro "opção desconhecida: $1 (veja --ajuda)" ;;
esac

[ "$EUID" -eq 0 ] || erro "precisa ser executado como root"
virt=$(systemd-detect-virt 2>/dev/null)
if [ -z "$virt" ] || [ "$virt" == "none" ]; then
    erro "esta máquina não parece virtual (systemd-detect-virt: ${virt:-?}). O vmprepara.sh é só para a VM de desenvolvimento."
fi

faltam=()
for f in "${FERRAMENTAS[@]}"; do command -v "$f" >/dev/null || faltam+=("$f"); done
ufw_antes="ausente"; command -v ufw >/dev/null && ufw_antes=$(LC_ALL=C ufw status 2>/dev/null | awk '/^Status:/ {print $2}')

echo "Ferramentas de desenvolvimento: ${FERRAMENTAS[*]}"
if [ ${#faltam[@]} -eq 0 ]; then
    echo "  todas já instaladas"
else
    echo "  a instalar: ${faltam[*]} (apt-get install --no-install-recommends)"
fi
if [ "$simular" -eq 1 ]; then
    echo "(simulação: nada foi feito)"
    exit 0
fi

if [ ${#faltam[@]} -gt 0 ]; then
    export DEBIAN_FRONTEND=noninteractive
    "$APT" -o DPkg::Lock::Timeout=120 update -qq || echo "  [!] apt-get update falhou; tentando instalar mesmo assim"
    "$APT" -o DPkg::Lock::Timeout=120 install -y -qq --no-install-recommends "${faltam[@]}" >/dev/null \
        || erro "a instalação falhou (sem internet? repositórios?)"
fi

# Conferência: tudo instalado; o ufw continua inativo (a prova t05b exige)
ok=1
for f in "${FERRAMENTAS[@]}"; do
    if command -v "$f" >/dev/null; then echo "  ✔ $f"; else echo "  ✘ $f não instalado"; ok=0; fi
done
ufw_depois=$(LC_ALL=C ufw status 2>/dev/null | awk '/^Status:/ {print $2}')
if [ "$ufw_depois" == "active" ]; then
    echo "  [!] o ufw está ATIVO (estava: $ufw_antes). A prova t05b precisa dele inativo: ufw disable"
    ok=0
else
    echo "  ✔ ufw inativo"
fi
[ "$ok" -eq 1 ] || exit 1

cat <<EOF

Pronto. Próximos passos (em $REPO):
  ./debkit --preparar                     # o debkit prepara o servidor sozinho (instala o Samba...)
  tests/run.sh                            # suíte normal
  DEBKIT_TESTE_REAL=1 tests/run.sh t04b_ssh_real.sh t05b_ufw_real.sh t07b_usuario_real.sh t09b_home_real.sh
EOF
