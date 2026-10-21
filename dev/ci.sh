#!/usr/bin/env bash
# dev/ci.sh - roda a suíte do debkit num Debian 13 NOVO, dentro de um
# container com systemd (systemd-nspawn). É o que o GitHub Actions executa
# a cada push (.github/workflows/ci.yml) e pode ser rodado igual na VM de
# desenvolvimento.
#
# Passos: cria o sistema (debootstrap, guardado em cache), copia o
# repositório (com o que ainda não foi commitado) para /usr/local/src/debkit,
# liga o
# container, roda "./debkit --preparar --sim" (a preparação de verdade, num
# servidor limpo), confere "./debkit --verificar", roda tests/run.sh e, por
# fim, instala de verdade (install.sh --sim: /opt/debkit e o comando
# debkit), usa o comando instalado e desinstala (debkit --desinstalar
# --tudo --sim). Nada disso toca no
# sistema da máquina: usuários, grupos, Samba e SSH são os do container,
# que é apagado no fim.
#
# Uso: dev/ci.sh [--com-rede] [--reais] [--manter] [--novo]
#   (sem opção)  container sem rede: Samba e logrotate já vêm no sistema e
#                a preparação só configura (a VM tem o próprio Samba na
#                porta 445; um container na rede dela brigaria pela porta)
#   --com-rede   container na rede da máquina: a preparação INSTALA o
#                Samba pelo apt, como num servidor novo (usado no GitHub)
#   --reais      roda também as provas reais (DEBKIT_TESTE_REAL=1), que
#                no container mexem só no Samba/SSH dele; menos a t04b
#                (precisa de sessões SSH abertas) e a t05b (precisa das
#                redes da máquina), que ficam para a VM
#   --manter     não apaga o container no fim (para investigar)
#   --novo       refaz o sistema base em vez de usar o cache
#
# Precisa: root, debootstrap, systemd-nspawn e machinectl (pacotes
# debootstrap e systemd-container). Pasta de trabalho: DEBKIT_CI_DIR
# (padrão /root/.cache/debkit-ci, fora dos snapshots da VM).
# Código de saída: o da suíte (0 = tudo passou).

REPO="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
CI_DIR="${DEBKIT_CI_DIR:-/root/.cache/debkit-ci}"
SUITE="trixie"
ESPELHO="${DEBKIT_CI_ESPELHO:-http://deb.debian.org/debian}"
MAQUINA="debkit-ci-$$"
# Sistema do container. e2fsprogs: discos de teste (t09) e chattr (t18,
# t19). Dev: git (t10), shellcheck, smbclient e ufw (instalado e inativo),
# como o dev/vmprepara.sh deixa a VM.
PACOTES=(systemd systemd-sysv dbus iproute2 procps openssh-server e2fsprogs git shellcheck smbclient ufw)
PACOTES_SEM_REDE=(samba logrotate)     # sem rede o apt do container não baixa nada
com_rede=0; reais=0; manter=0; novo=0

erro() { echo "ci: $*" >&2; exit 1; }
info() { echo "ci: $*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --com-rede) com_rede=1 ;;
        --reais)    reais=1 ;;
        --manter)   manter=1 ;;
        --novo)     novo=1 ;;
        -h|--ajuda) sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          erro "opção desconhecida: $1 (veja --ajuda)" ;;
    esac
    shift
done

[ "$EUID" -eq 0 ] || erro "precisa ser executado como root"
for c in debootstrap systemd-nspawn machinectl systemd-run; do
    command -v "$c" >/dev/null || erro "falta o comando $c (apt-get install debootstrap systemd-container)"
done

# ── Sistema base (cache) ─────────────────────────────────────────────────────
lista=("${PACOTES[@]}")
[ "$com_rede" -eq 0 ] && lista+=("${PACOTES_SEM_REDE[@]}")
assinatura="$SUITE $(IFS=,; echo "${lista[*]}")"
base="$CI_DIR/base-$(printf '%s' "$assinatura" | md5sum | cut -c1-12)"
mkdir -p -- "$CI_DIR" || erro "não foi possível criar $CI_DIR"
if [ "$novo" -eq 1 ] || [ "$(cat "$base/.debkit-ci" 2>/dev/null)" != "$assinatura" ]; then
    info "criando o Debian $SUITE base em $base (debootstrap; leva 1-3 minutos)..."
    rm -rf -- "$base" "$base.novo"
    chave=()
    # Fora do Debian (ex: o Ubuntu do GitHub) o debootstrap precisa da chave
    # do repositório do Debian
    [ -f /usr/share/keyrings/debian-archive-keyring.gpg ] && chave=(--keyring=/usr/share/keyrings/debian-archive-keyring.gpg)
    # debootstrap antigo sem o roteiro do trixie: o do sid serve
    roteiro=()
    [ -e "/usr/share/debootstrap/scripts/$SUITE" ] || roteiro=(/usr/share/debootstrap/scripts/sid)
    if ! debootstrap "${chave[@]}" --variant=minbase --include="$(IFS=,; echo "${lista[*]}")" \
            "$SUITE" "$base.novo" "$ESPELHO" "${roteiro[@]}" > "$CI_DIR/debootstrap.log" 2>&1; then
        tail -n 20 "$CI_DIR/debootstrap.log" >&2
        erro "o debootstrap falhou (log: $CI_DIR/debootstrap.log)"
    fi
    echo "$assinatura" > "$base.novo/.debkit-ci"
    mv -- "$base.novo" "$base"
fi

# ── Container ────────────────────────────────────────────────────────────────
raiz="$CI_DIR/$MAQUINA"
# shellcheck disable=SC2317  # chamada pelo trap
limpar() {
    machinectl terminate "$MAQUINA" >/dev/null 2>&1
    for _ in $(seq 1 30); do machinectl show "$MAQUINA" >/dev/null 2>&1 || break; sleep 1; done
    if [ "$manter" -eq 1 ]; then
        info "container mantido em $raiz (ligar de novo: systemd-nspawn -b -D $raiz)"
    else
        rm -rf -- "$raiz"
    fi
}
trap limpar EXIT

info "copiando o sistema e o repositório..."
cp -a -- "$base" "$raiz" || erro "não foi possível copiar o sistema base"
echo "$MAQUINA" > "$raiz/etc/hostname"
# O nmbd (NetBIOS, que o debkit não usa) espera rede para subir e atrasa o
# boot do container sem rede: mascarado
ln -sf /dev/null "$raiz/etc/systemd/system/nmbd.service"
# O repositório dentro do container (legível por todos: há testes sem root;
# o /opt/debkit fica para a instalação de verdade)
REPO_C=/usr/local/src/debkit
mkdir -p -- "$raiz$REPO_C"
# O repositório inteiro (com .git e o que ainda não foi commitado). Lá dentro
# ele é do root e sem escrita para grupo/outros, como o debkit exige (no
# GitHub os arquivos são do usuário do runner).
tar -C "$REPO" -cf - . | tar -C "$raiz$REPO_C" -xf - || erro "não foi possível copiar o repositório"
chown -R 0:0 -- "$raiz$REPO_C" && chmod -R go-w -- "$raiz$REPO_C"

rede=(--private-network)
[ "$com_rede" -eq 1 ] && rede=()
# Discos de teste (t09): o container usa dispositivos de loop da máquina.
# Os nós /dev/loopN são criados antes (no container o /dev é outro e um
# loop novo não apareceria lá).
loops=(--bind=/dev/loop-control --property=DeviceAllow="block-loop rwm" --property=DeviceAllow="/dev/loop-control rwm")
for i in $(seq 0 7); do
    [ -b "/dev/loop$i" ] || mknod -m 660 "/dev/loop$i" b 7 "$i" 2>/dev/null
    [ -b "/dev/loop$i" ] && loops+=(--bind="/dev/loop$i")
done
info "ligando o container $MAQUINA..."
systemd-nspawn -q -b -D "$raiz" --machine="$MAQUINA" "${rede[@]}" "${loops[@]}" > "$CI_DIR/$MAQUINA.console" 2>&1 &
for _ in $(seq 1 60); do
    systemctl -M "$MAQUINA" is-system-running --wait >/dev/null 2>&1
    case "$(systemctl -M "$MAQUINA" is-system-running 2>/dev/null)" in
        running|degraded) break ;;
    esac
    sleep 2
done
estado=$(systemctl -M "$MAQUINA" is-system-running 2>/dev/null)
case "$estado" in
    running|degraded) info "container no ar ($estado)" ;;
    *) tail -n 20 "$CI_DIR/$MAQUINA.console" >&2; erro "o container não subiu (estado: ${estado:-?})" ;;
esac

# Roda um comando no container (como root, na pasta do repositório)
dentro() {
    systemd-run -M "$MAQUINA" -q --wait --pipe -p WorkingDirectory="$REPO_C" \
        -E LANG=C.UTF-8 -E TERM=dumb -E DEBKIT_TESTE_REAL="${DEBKIT_TESTE_REAL:-}" -- "$@"
}

saida="$CI_DIR/$MAQUINA.log"
rc=0
{
    echo "━━ preparação (./debkit --preparar --sim) ━━"
    dentro "$REPO_C/debkit" --preparar --sim || rc=1
    echo "━━ verificação (./debkit --verificar) ━━"
    dentro "$REPO_C/debkit" --verificar || rc=1
    if [ "$rc" -eq 0 ]; then
        echo "━━ suíte (tests/run.sh) ━━"
        dentro "$REPO_C/tests/run.sh" || rc=1
        if [ "$reais" -eq 1 ]; then
            echo "━━ provas reais (DEBKIT_TESTE_REAL=1) ━━"
            # shellcheck disable=SC2016  # expandido dentro do container
            DEBKIT_TESTE_REAL=1 dentro bash -c 'cd tests && ./run.sh $(ls t*b_*.sh | grep -vE "^t0[45]b_")' || rc=1
        fi
        echo "━━ instalação de verdade (install.sh --sim) ━━"
        if dentro "$REPO_C/install.sh" --sim && dentro /usr/local/sbin/debkit --versao \
           && dentro bash -lc 'debkit --verificar >/dev/null && debkit samba usuario listar >/dev/null'; then
            echo "instalação: ok"
        else
            echo "instalação: FALHOU"; rc=1
        fi
        echo "━━ desinstalação de verdade (debkit --desinstalar --tudo --sim) ━━"
        # shellcheck disable=SC2016  # expandido dentro do container
        if dentro bash -lc 'debkit --desinstalar --tudo --sim && [ ! -e /opt/debkit ] && [ ! -e /usr/local/sbin/debkit ] \
                && [ ! -e /etc/debkit/debkit.conf ] && [ ! -e /var/log/debkit.log ] && ! getent group debkit_usuarios \
                && ! sshd -T 2>/dev/null | grep -qi "^denygroups.*debkit_usuarios" && [ -f /etc/samba/smb.conf ]'; then
            echo "desinstalação: ok"
        else
            echo "desinstalação: FALHOU"; rc=1
        fi
    fi
    exit "$rc"
} 2>&1 | tee "$saida"
rc=${PIPESTATUS[0]}

# No GitHub, cada falha vira uma anotação (aparece no resumo do run; o
# GitHub mostra até 10 por passo) e, se falhou, uma última com os detalhes
if [ "${GITHUB_ACTIONS:-}" == "true" ]; then
    limpo=$(sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$saida")
    grep -E '^ +FALHA |✘✘|FALHA\(S\)|\[X\]' <<< "$limpo" | head -n 9 \
        | while IFS= read -r linha; do echo "::error::${linha#"${linha%%[! ]*}"}"; done
    if [ "$rc" -ne 0 ]; then
        # os detalhes de cada falha (as linhas recuadas depois dela) e o fim do log
        fim=$( { grep -A12 -E '^ +FALHA |✘✘' <<< "$limpo" | grep -vE '^ +ok ' | head -n 150; echo "────"; grep -vE '^ +ok ' <<< "$limpo" | tail -n 15; } )
        fim="${fim//'%'/'%25'}"; fim="${fim//$'\r'/}"; fim="${fim//$'\n'/'%0A'}"
        echo "::error title=fim do log::$fim"
    fi
fi
if [ "$rc" -eq 0 ]; then info "TUDO CERTO (log: $saida)"; else info "FALHOU (log: $saida)"; fi
exit "$rc"
