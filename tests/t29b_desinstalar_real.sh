#!/usr/bin/env bash
# Prova REAL do debkit --desinstalar (tarefa 4.4) na VM de desenvolvimento
# (repositório em /opt/debkit, com usuários de arquivos no grupo de
# proteção): cria o comando pelo install.sh e desinstala sem --tudo. Só o
# comando sai; o repositório, a proteção SSH (há usuários de arquivos), a
# configuração e o smb.conf ficam. Só roda com:
#   DEBKIT_TESTE_REAL=1 tests/run.sh t29b_desinstalar_real.sh
# Configuração real com o log no sandbox. (A desinstalação completa, com
# --tudo e o grupo vazio, é provada no CI, no container.)
source "$(dirname "$0")/lib.sh"

if [ "${DEBKIT_TESTE_REAL:-}" != "1" ]; then
    echo "  (pulado: teste com /usr/local/sbin e o SSH reais - rode com DEBKIT_TESTE_REAL=1)"
    exit 0
fi
sandbox

LINK=/usr/local/sbin/debkit
if [ "$REPO" != "/opt/debkit" ]; then echo "  o repositório não está em /opt/debkit ($REPO) - pulado"; exit 0; fi
if [ -e "$LINK" ] || [ -L "$LINK" ]; then echo "  $LINK já existe - abortando (o teste cria e remove o comando)"; exit 1; fi
[ -f /etc/debkit/debkit.conf ] || { echo "  sem /etc/debkit/debkit.conf - abortando"; exit 1; }
n=$(getent group debkit_usuarios | cut -d: -f4 | tr ',' '\n' | sed '/^$/d' | wc -l)
[ "$n" -gt 0 ] || { echo "  o grupo de proteção real está vazio (a desinstalação tiraria a proteção) - abortando"; exit 1; }
trap 'rm -f -- "$LINK"; rm -rf -- "${SANDBOX:?}"' EXIT
{ cat /etc/debkit/debkit.conf; echo "LOG=$SANDBOX/debkit.log"; echo "TRAVA=$SANDBOX/debkit.lock"; echo "BACKUP_DIR=$SANDBOX/backups"; } > "$SANDBOX/real.conf"; chmod 644 "$SANDBOX/real.conf"
export DEBKIT_CONF_ARQUIVO="$SANDBOX/real.conf"
antes_ssh=$(sshd -T 2>/dev/null | grep -i '^denygroups'); antes_smb=$(md5sum < /etc/samba/smb.conf)
git_antes=$(git -C "$REPO" status --porcelain)

caso "comando criado pelo install.sh"
printf 's\nn\n' | env -u DEBKIT_APT -u DEBKIT_DPKG_ADMIN bash "$REPO/install.sh" >/dev/null 2>&1
igual "/opt/debkit/debkit" "$(readlink "$LINK")"
caso "desinstalar (sem --tudo): só o comando sai"
saida=$(printf 's\n' | env -u DEBKIT_APT -u DEBKIT_DPKG_ADMIN "$LINK" --desinstalar 2>&1; echo "RC=$?")
contem "RC=0" "$saida"; contem "O comando $LINK" "$saida"
contem "é um repositório (não foi copiado pelo install.sh)" "$saida"
contem "há $n usuário(s) de arquivos" "$saida"
verdadeiro "comando removido" test ! -e "$LINK" -a ! -L "$LINK"
caso "o resto fica"
verdadeiro "repositório" test -f "$REPO/debkit" -a -d "$REPO/.git"
igual "$git_antes" "$(git -C "$REPO" status --porcelain)" "git status igual"
igual "$antes_ssh" "$(sshd -T 2>/dev/null | grep -i '^denygroups')" "proteção SSH em vigor igual"
verdadeiro "grupo de proteção" getent group debkit_usuarios
verdadeiro "configuração" test -f /etc/debkit/debkit.conf
igual "$antes_smb" "$(md5sum < /etc/samba/smb.conf)" "smb.conf igual"
contem "desinstalar item=link resultado=ok" "$(cat "$SANDBOX/debkit.log")" "auditado (no sandbox)"

real_intacto
resumo
