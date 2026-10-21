#!/usr/bin/env bash
# Prova REAL do install.sh (tarefa 4.3) na VM de desenvolvimento, onde o
# repositório está clonado em /opt/debkit: é o caso "repositório já no
# lugar" com os caminhos de verdade.
#
# ATENÇÃO: cria o comando /usr/local/sbin/debkit (link para
# /opt/debkit/debkit) e confere que ele funciona pelo PATH. Por isso só roda
# com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t28b_instalar_real.sh
# No fim o link sai (se não existia antes) e o repositório continua sem
# mudanças (git status). Configuração real com o log no sandbox.
# (A instalação por cópia em /opt/debkit, num servidor novo, é provada no
# CI: dev/ci.sh roda o install.sh --sim no container.)
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com /opt/debkit e /usr/local/sbin reais - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

LINK=/usr/local/sbin/debkit
if [ "$REPO" != "/opt/debkit" ]; then echo "  o repositório não está em /opt/debkit ($REPO) - pulado"; exit 0; fi
link_antes=""
if [ -L "$LINK" ]; then
    link_antes=$(readlink "$LINK")
    [ "$link_antes" == "/opt/debkit/debkit" ] || { echo "  $LINK aponta para $link_antes - abortando"; exit 1; }
elif [ -e "$LINK" ]; then
    echo "  $LINK existe e não é link - abortando"; exit 1
fi
limpar_real() {
    [ -z "$link_antes" ] && [ -L "$LINK" ] && rm -f -- "$LINK"
    rm -rf -- "${SANDBOX:?}"
}
trap limpar_real EXIT
git_antes=$(git -C "$REPO" status --porcelain 2>/dev/null)
{ cat /etc/debkit/debkit.conf 2>/dev/null; echo "LOG=$SANDBOX/debkit.log"; } > "$SANDBOX/real.conf"; chmod 644 "$SANDBOX/real.conf"

caso "install.sh no próprio repositório (/opt/debkit), sem preparar"
saida=$(printf 's\nn\n' | env DEBKIT_CONF_ARQUIVO="$SANDBOX/real.conf" bash "$REPO/install.sh" 2>&1; echo "RC=$?")
contem "Usar o debkit que já está em /opt/debkit" "$saida"; contem "RC=0" "$saida"
igual "/opt/debkit/debkit" "$(readlink "$LINK")" "comando $LINK"
caso "o comando funciona pelo PATH (como sudo debkit)"
igual "$(bash "$REPO/debkit" --versao)" "$(env PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin debkit --versao)"
contem "Uso: debkit" "$(env PATH=/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin debkit --ajuda)"
caso "o repositório não mudou"
igual "$git_antes" "$(git -C "$REPO" status --porcelain 2>/dev/null)" "git status igual ao do início"
contem "instalar versao=" "$(cat "$SANDBOX/debkit.log")" "auditado (no log do sandbox)"

limpar_real; trap - EXIT
caso "limpeza"
if [ -z "$link_antes" ]; then verdadeiro "link removido (não existia)" test ! -e "$LINK"
else igual "$link_antes" "$(readlink "$LINK")" "link como estava"; fi
resumo
