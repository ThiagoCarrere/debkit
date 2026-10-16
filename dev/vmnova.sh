#!/usr/bin/env bash
# dev/vmnova.sh - volta a VM de DESENVOLVIMENTO ao snapshot limpo (Timeshift).
#
# O Timeshift restaura o sistema e REINICIA a máquina (a conexão SSH cai).
# O repositório (/opt/debkit) e o /root ficam fora dos snapshots: o código
# não volta para trás, mas o que não foi enviado ao GitHub corre risco se o
# disco tiver problema - por isso o script exige tudo commitado e enviado.
#
# SÓ para a VM de desenvolvimento. Recusa: máquina que não é virtual,
# repositório fora das exclusões do Timeshift, mudança sem commit ou commit
# sem push (salvo --forcar). Pede para digitar RESTAURAR.
#
# Uso: dev/vmnova.sh [--simular] [--snapshot NOME] [--forcar]
#   (sem opção)       snapshot mais recente cuja descrição começa com "limpa"
#   --snapshot NOME   outro snapshot (ex: 2026-10-16_09-56-40)
#   --simular         mostra o que faria e o comando, sem executar nada
#   --forcar          aceita repositório com mudanças/commits não enviados
# Depois que a VM voltar: dev/vmprepara.sh (ferramentas de desenvolvimento).

REPO="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
DESCRICAO="${VMNOVA_DESCRICAO:-limpa}"      # início da descrição do snapshot limpo
TS_CONF="${VMNOVA_TS_CONF:-/etc/timeshift/timeshift.json}"
TIMESHIFT="${VMNOVA_TIMESHIFT:-timeshift}"  # os testes usam um falso
simular=0; forcar=0; snapshot=""

erro()  { echo "vmnova: $*" >&2; exit 1; }
aviso() { echo "  [!] $*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --simular)  simular=1 ;;
        --forcar)   forcar=1 ;;
        --snapshot) [ -n "${2:-}" ] || erro "--snapshot precisa do nome"; snapshot="$2"; shift ;;
        -h|--ajuda) sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          erro "opção desconhecida: $1 (veja --ajuda)" ;;
    esac
    shift
done

[ "$EUID" -eq 0 ] || erro "precisa ser executado como root"
command -v "$TIMESHIFT" >/dev/null || erro "timeshift não instalado"

# ── Só em máquina virtual ────────────────────────────────────────────────────
virt=$(systemd-detect-virt 2>/dev/null)
if [ -z "$virt" ] || [ "$virt" == "none" ]; then
    erro "esta máquina não parece virtual (systemd-detect-virt: ${virt:-?}). O vmnova.sh é só para a VM de desenvolvimento."
fi

# ── Snapshot ─────────────────────────────────────────────────────────────────
# Linhas da lista: "<num>  [>]  <nome aaaa-mm-dd_hh-mm-ss>  <tags>  <descrição>"
lista=$(LC_ALL=C "$TIMESHIFT" --list 2>/dev/null) || erro "não foi possível listar os snapshots (timeshift --list)"
declare -a nomes=() descricoes=()
while IFS= read -r linha; do
    if [[ "$linha" =~ ^[[:space:]]*[0-9]+[[:space:]]+(\>[[:space:]]+)?([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2})[[:space:]]+([A-Z]*)[[:space:]]*(.*)$ ]]; then
        nomes+=("${BASH_REMATCH[2]}")
        descricoes+=("${BASH_REMATCH[4]%"${BASH_REMATCH[4]##*[![:space:]]}"}")
    fi
done <<< "$lista"
[ ${#nomes[@]} -gt 0 ] || erro "nenhum snapshot encontrado"

escolhido=""; desc_escolhida=""
for i in "${!nomes[@]}"; do
    if [ -n "$snapshot" ]; then
        [ "${nomes[$i]}" == "$snapshot" ] && { escolhido="${nomes[$i]}"; desc_escolhida="${descricoes[$i]}"; }
    elif [[ "${descricoes[$i]}" == "$DESCRICAO"* ]] && [[ -z "$escolhido" || "${nomes[$i]}" > "$escolhido" ]]; then
        escolhido="${nomes[$i]}"; desc_escolhida="${descricoes[$i]}"
    fi
done
if [ -z "$escolhido" ]; then
    echo "Snapshots disponíveis:" >&2
    for i in "${!nomes[@]}"; do echo "  ${nomes[$i]}  ${descricoes[$i]}" >&2; done
    if [ -n "$snapshot" ]; then erro "snapshot '$snapshot' não existe"; fi
    erro "nenhum snapshot com descrição começando por '$DESCRICAO' (use --snapshot NOME)"
fi

# ── Destino: a partição do / ─────────────────────────────────────────────────
alvo=$(findmnt -n -o SOURCE /)
[[ "$alvo" == /dev/* ]] || erro "não foi possível descobrir a partição do / ($alvo)"

# ── O repositório sobrevive ao restore? ──────────────────────────────────────
problemas=()
if ! grep -qF "\"$REPO/**\"" "$TS_CONF" 2>/dev/null; then
    problemas+=("$REPO não está nas exclusões do Timeshift ($TS_CONF): o restore voltaria o código para trás")
fi
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
    [ -z "$(git -C "$REPO" status --porcelain)" ] || problemas+=("há mudanças sem commit em $REPO")
    git -C "$REPO" fetch -q 2>/dev/null || problemas+=("não foi possível consultar o GitHub (git fetch)")
    if upstream=$(git -C "$REPO" rev-parse --abbrev-ref '@{u}' 2>/dev/null); then
        nao_enviados=$(git -C "$REPO" rev-list --count "$upstream..HEAD" 2>/dev/null)
        [ "${nao_enviados:-0}" -eq 0 ] || problemas+=("$nao_enviados commit(s) ainda não enviados ao GitHub ($upstream)")
    else
        problemas+=("a branch atual não tem branch remota")
    fi
fi

# ── Resumo ───────────────────────────────────────────────────────────────────
echo "VM de desenvolvimento ($virt) -> snapshot $escolhido"
echo "  descrição: $desc_escolhida"
echo "  partição:  $alvo"
echo "  comando:   timeshift --restore --snapshot '$escolhido' --target $alvo --skip-grub --yes"
for p in "${problemas[@]}"; do aviso "$p"; done
if [ ${#problemas[@]} -gt 0 ] && [ "$forcar" -eq 0 ] && [ "$simular" -eq 0 ]; then
    erro "resolva os itens acima (ou use --forcar)"
fi
if [ "$simular" -eq 1 ]; then
    echo "(simulação: nada foi feito)"
    exit 0
fi

echo ""
echo "A máquina vai voltar ao snapshot e REINICIAR (a conexão SSH cai)."
read -rp "Digite RESTAURAR para continuar: " resp || exit 1
[ "$resp" == "RESTAURAR" ] || { echo "Cancelado. Nada foi feito."; exit 1; }
exec "$TIMESHIFT" --restore --snapshot "$escolhido" --target "$alvo" --skip-grub --yes
