#!/usr/bin/env bash
# Roda todos os testes do gsb (tests/t*.sh). Precisa ser root.
# Uso: tests/run.sh [arquivo_de_teste ...]
#
# TRAVA DE SEGURANÇA: antes e depois de cada arquivo de teste é tirada uma
# "impressão digital" do sistema REAL (smb.conf, configuração efetiva do
# SSH, sshd_config.d, grupos e pastas do gsb). Se qualquer coisa mudar, a
# suíte falha e mostra o que mudou - nenhum teste pode alterar o servidor
# sem ser percebido. (Os testes que precisam tocar no sistema real, como
# t04b_ssh_real.sh, só rodam com GSB_TESTE_REAL=1 e devem restaurá-lo.)

cd "$(dirname "$0")" || exit 1
[ "$EUID" -eq 0 ] || { echo "Os testes precisam ser executados como root." >&2; exit 1; }

impressao_digital() {
    echo "smb.conf:        $(md5sum < /etc/samba/smb.conf 2>/dev/null)"
    echo "sshd -T:         $(sshd -T 2>/dev/null | md5sum)"
    echo "sshd_config.d:   $(ls -A /etc/ssh/sshd_config.d 2>/dev/null | tr '\n' ' ')"
    echo "grupos gsb:      $(getent group | cut -d: -f1 | grep -E '^gsbt?_' | tr '\n' ' ')"
    echo "usuários gsbt:   $(getent passwd | cut -d: -f1 | grep -E '^gsbt_' | tr '\n' ' ')"
    echo "Samba gsbt:      $(pdbedit -L 2>/dev/null | cut -d: -f1 | grep -E '^gsbt_' | tr '\n' ' ')"
    for p in /etc/gsb /var/backups/gsb /var/log/gsb.log /etc/samba/gsb-shares.conf /run/gsb.lock; do
        [ -e "$p" ] && echo "existe:          $p"
    done
}

arquivos=("$@")
[ ${#arquivos[@]} -eq 0 ] && arquivos=(t*.sh)

falhas=0
for t in "${arquivos[@]}"; do
    echo "▶ $t"
    antes=$(impressao_digital)
    bash "$t" || falhas=$((falhas + 1))
    depois=$(impressao_digital)
    if [ "$antes" != "$depois" ]; then
        echo "  ✘✘ O TESTE ALTEROU O SISTEMA REAL ✘✘"
        diff <(echo "$antes") <(echo "$depois") | sed 's/^/     /'
        falhas=$((falhas + 1))
    fi
    echo ""
done

if [ "$falhas" -eq 0 ]; then
    echo "TODOS OS TESTES PASSARAM (${#arquivos[@]} arquivo(s)) - sistema real intacto"
else
    echo "$falhas FALHA(S) (arquivos com falha ou alteração do sistema real)"
    exit 1
fi
