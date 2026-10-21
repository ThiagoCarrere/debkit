#!/usr/bin/env bash
# Testes da tarefa 4.4 - debkit --desinstalar [--tudo] (seção 3.9): tira o
# comando e o programa instalado pelo install.sh; a proteção SSH só sai com
# o grupo de proteção vazio; a configuração, o log e os backups ficam (com
# --tudo, saem); usuários, grupos e compartilhamentos nunca são tocados.
# Tudo no sandbox (instalação em DEBKIT_INSTALAR_DIR/LINK do sandbox).
source "$(dirname "$0")/lib.sh"
sandbox
preparar_sandbox
cp -p "$SANDBOX/debkit.conf" "$SANDBOX/debkit.conf.orig"

DEST="$SANDBOX/opt/debkit"; LNK="$SANDBOX/sbin/debkit"
export DEBKIT_INSTALAR_DIR="$DEST" DEBKIT_INSTALAR_LINK="$LNK"
instalar() { rm -rf "$DEST" "$LNK"; printf 's\nn\n' | bash "$REPO/install.sh" >/dev/null 2>&1; }
desi() { "${PROG_T:-$LNK}" --desinstalar "$@" 2>&1; echo "RC=$?"; }
LOG() { cat "$SANDBOX/debkit.log" 2>/dev/null; }
limpar_dkt() { local x; for x in $(getent passwd | cut -d: -f1 | grep '^dkt_d'); do userdel "$x" >/dev/null 2>&1; done; }
trap 'limpar_dkt; rm -rf -- "${SANDBOX:?}"; getent group "$GRUPO_TESTE" >/dev/null && groupdel "$GRUPO_TESTE"' EXIT

caso "uso: --tudo só com --desinstalar; sem root, recusado"
saida=$(bash "$DEBKIT" --tudo 2>&1; echo "RC=$?"); contem "só vale com --desinstalar" "$saida"; contem "RC=2" "$saida"
saida=$(setpriv --reuid=65534 --regid=65534 --clear-groups bash "$DEBKIT" --desinstalar 2>&1; echo "RC=$?")
contem "precisa ser executado como root" "$saida"; contem "RC=1" "$saida"
caso "a ajuda cita a desinstalação"
contem "--desinstalar" "$(bash "$DEBKIT" --ajuda)"

caso "resposta n: nada sai"
instalar
saida=$(desi < /dev/null)
contem "A desinstalação vai remover:" "$saida"; contem "O comando $LNK" "$saida"; contem "O programa em $DEST" "$saida"
contem "Cancelado. Nada foi feito." "$saida"; contem "RC=1" "$saida"
verdadeiro "tudo continua" test -L "$LNK" -a -f "$DEST/debkit"
contem "resposta=nao" "$(LOG)"

caso "desinstalar a instalação por cópia: comando, programa e a proteção (grupo vazio) saem; dados ficam"
saida=$(printf 's\n' | desi)
contem "RC=0" "$saida"; contem "debkit desinstalado." "$saida"
contem "A proteção SSH ($SANDBOX/sshd_debkit.conf) e o grupo $GRUPO_TESTE, que está vazio" "$saida"
contem "use --tudo para remover também" "$saida"; contem "Os usuários, grupos e compartilhamentos e o smb.conf" "$saida"
verdadeiro "comando removido" test ! -e "$LNK" -a ! -L "$LNK"
verdadeiro "programa removido" test ! -e "$DEST"
verdadeiro "grupo de proteção (vazio) removido" bash -c "! getent group $GRUPO_TESTE"
verdadeiro "configuração fica" test -f "$SANDBOX/debkit.conf"
verdadeiro "log fica" test -f "$SANDBOX/debkit.log"
verdadeiro "backups ficam" test -d "$SANDBOX/backups"
contem "desinstalar item=programa" "$(LOG)" "auditado"; contem "sessao_fim motivo=normal" "$(LOG)"

caso "com usuário de arquivos no grupo de proteção: a proteção fica (e o porquê)"
preparar_sandbox; instalar
useradd -M -s /usr/sbin/nologin -U dkt_d1; gpasswd -a dkt_d1 "$GRUPO_TESTE" >/dev/null
saida=$(printf 's\n' | desi)
contem "RC=0" "$saida"; contem "há 1 usuário(s) de arquivos; sem ela eles poderiam entrar por SSH" "$saida"
nao_contem "que está vazio" "$saida"
verdadeiro "grupo continua, com o usuário" bash -c "getent group $GRUPO_TESTE | grep -q dkt_d1"
verdadeiro "usuário intocado" id dkt_d1
limpar_dkt

caso "--tudo: também a configuração, o log (e os girados), a regra e os backups"
preparar_sandbox; instalar
echo "antigo" > "$SANDBOX/debkit.log.1"; echo "x" | gzip > "$SANDBOX/debkit.log.2.gz"
mkdir -p "$SANDBOX/conf-bkp"; echo a > "$SANDBOX/conf-bkp/smb.conf.01-10-2026-10-00-00"; echo b > "$SANDBOX/conf-bkp/outro.txt"
saida=$(printf 's\n' | desi --tudo)
contem "RC=0" "$saida"; contem "A configuração $SANDBOX/debkit.conf" "$saida"
for f in debkit.conf debkit.log debkit.log.1 debkit.log.2.gz logrotate-debkit backups conf-bkp/smb.conf.01-10-2026-10-00-00; do
    verdadeiro "$f removido" test ! -e "$SANDBOX/$f"
done
igual "b" "$(cat "$SANDBOX/conf-bkp/outro.txt")" "arquivo que não é backup do debkit fica"
verdadeiro "o log não é recriado pelo fim da sessão" test ! -e "$SANDBOX/debkit.log"
verdadeiro "smb.conf do sandbox fica" test -f "$SANDBOX/smb.conf"

caso "rodando do repositório (sem a marca do install.sh): o programa fica"
# a configuração saiu no caso anterior: volta a do sandbox
cp -p "$SANDBOX/debkit.conf.orig" "$SANDBOX/debkit.conf"; preparar_sandbox
ln -s "$REPO/debkit" "$LNK"
useradd -M -s /usr/sbin/nologin -U dkt_d2; gpasswd -a dkt_d2 "$GRUPO_TESTE" >/dev/null
saida=$(printf 's\n' | PROG_T="$REPO/debkit" desi)
contem "é um repositório (não foi copiado pelo install.sh)" "$saida"; contem "RC=0" "$saida"
verdadeiro "link para o repositório removido" test ! -e "$LNK"
verdadeiro "repositório intacto" test -f "$REPO/debkit" -a -d "$REPO/.git"
caso "nada para remover"
saida=$(printf 's\n' | PROG_T="$REPO/debkit" desi); contem "Nada do debkit para remover." "$saida"; contem "RC=0" "$saida"
limpar_dkt

caso "inglês: --uninstall --all"
saida=$(DEBKIT_IDIOMA=en bash "$REPO/debkit" --uninstall --all < /dev/null 2>&1)
contem "The uninstall will remove:" "$saida"; contem "Cancelled" "$saida"

real_intacto
resumo
