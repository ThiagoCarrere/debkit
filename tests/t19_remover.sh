#!/usr/bin/env bash
# Testes de remover compartilhamento (Fase 2, tarefa 2.3; decisões na
# seção 3.7): tira a seção do smb.conf pela edição segura (com o comentário
# do debkit; o resto do arquivo fica), a pasta e os arquivos ficam, mas a
# pasta passa a ser só do root; quem tinha o acesso tem a sessão refeita.
# smb.conf e base do Samba da areia; pastas em /srv/dkt-teste.* (apagadas
# no fim). A prova com o Samba de verdade está em t19b_remover_real.sh.
source "$(dirname "$0")/lib.sh"
caixa_de_areia

if getent passwd | cut -d: -f1 | grep -q '^dkt_'; then echo "  já existem usuários dkt_* - abortando"; exit 1; fi
T=$(mktemp -d /srv/dkt-teste.XXXXXX); chmod 755 "$T"
limpar_tudo() {
    local x
    [ -e "$T/a" ] && chattr -i "$T/a" 2>/dev/null
    for x in $(getent passwd | cut -d: -f1 | grep '^dkt_'); do userdel "$x" >/dev/null 2>&1; done
    for x in $(getent group | cut -d: -f1 | grep '^dkt_'); do groupdel "$x" >/dev/null 2>&1; done
    rm -rf -- "${T:?}" "${AREIA:?}"
}
trap limpar_tudo EXIT

# Só as seções padrão (os compartilhamentos de demonstração da VM não entram)
awk '/^[ \t]*\[/ { s = tolower($0); gsub(/[ \t\[\]]/, "", s); fora = (s != "global" && s != "homes" && s != "printers" && s != "print$") } !fora' \
    "$AREIA/smb.conf" > "$AREIA/smb.conf.novo" && cat "$AREIA/smb.conf.novo" > "$AREIA/smb.conf" && rm -f "$AREIA/smb.conf.novo"
preparar_areia
CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;
     debkit_samba_recarregar() { echo reload >> '$AREIA/reloads'; };
     debkit_samba_reconectar() { [ \$# -gt 0 ] && echo \"RECONECTAR: \$*\"; return 0; };"
p() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
LOG() { cat "$AREIA/debkit.log" 2>/dev/null; }
efetivo() { testparm -s "$AREIA/smb.conf" 2>/dev/null; }
sem_secao() { awk -v s="[$1]" '/^\[/ { em = ($0 == s) } !em && NF'; }
groupadd dkt_ra; groupadd dkt_rb
useradd -M -s /usr/sbin/nologin -U dkt_r1; useradd -M -s /usr/sbin/nologin -g dkt_ra dkt_r2; useradd -M -s /usr/sbin/nologin -U dkt_r3
gpasswd -M dkt_r1 dkt_ra >/dev/null; gpasswd -M dkt_r3 dkt_rb >/dev/null
GA=$(getent group dkt_ra | cut -d: -f3)
mkdir "$T/base"
p "debkit_shr_definir_base '$T/base'" >/dev/null

criar() { p "DEBKIT_S_NOME='$1'; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$2'; DEBKIT_S_GRUPO='$3'; debkit_shr_criar; echo RC=\$?"; }
remover() { p "${2:-} DEBKIT_S_NOME='$1'; debkit_shr_remover; echo RC=\$?"; }

contem "RC=0" "$(criar dkt-a "$T/a" dkt_ra)"; contem "RC=0" "$(criar dkt-b "$T/b" dkt_rb)"
echo x > "$T/a/doc.txt"; chown dkt_r1:dkt_ra "$T/a/doc.txt"; chmod 660 "$T/a/doc.txt"

# ════════════════════════════════════════════════════════════════════════════
# Remover
# ════════════════════════════════════════════════════════════════════════════
caso "remover: sai do smb.conf (com o comentário do debkit), o resto fica"
antes=$(efetivo); : > "$AREIA/reloads"; cp -p "$AREIA/smb.conf" "$AREIA/smb.conf.antes"
saida=$(remover dkt-a)
contem "RC=0" "$saida"; contem "Compartilhamento dkt-a removido" "$saida"
contem "Os arquivos continuam em $T/a" "$saida"
nao_contem "[dkt-a]" "$(efetivo)" "seção fora da configuração"; nao_contem "[dkt-a]" "$(cat "$AREIA/smb.conf")" "e do arquivo"
igual "$(sem_secao dkt-a <<< "$antes")" "$(efetivo | sem_secao dkt-a)" "o resto do smb.conf não mudou"
igual 1 "$(grep -c '^# debkit: compartilhamento criado' "$AREIA/smb.conf")" "só o comentário do dkt-b ficou"
igual "# debkit: compartilhamento criado em $(date '+%d/%m/%Y')" "$(grep -B1 '^\[dkt-b\]' "$AREIA/smb.conf" | head -1)" "colado no [dkt-b]"
igual "$(sed '/^\[dkt-a\]/,/^\[/{/^\[dkt-b\]/!d}' "$AREIA/smb.conf.antes" | grep -v '^# debkit: compartilhamento criado' | grep -v '^$')" \
      "$(grep -v '^# debkit: compartilhamento criado' "$AREIA/smb.conf" | grep -v '^$')" "fora o bloco do dkt-a, o arquivo é o mesmo"
igual 1 "$(grep -c reload "$AREIA/reloads")" "Samba recarregado"
caso "remover: a pasta e os arquivos ficam; a pasta passa a ser só do root"
igual "0 0 700" "$(stat -c '%u %g %a' "$T/a")" "root:root 0700, sem setgid"
igual "$(id -u dkt_r1) $GA 660 x" "$(stat -c '%u %g %a' "$T/a/doc.txt") $(cat "$T/a/doc.txt")" "arquivo intacto"
caso "remover: sessões de quem tinha o acesso (membros e grupo principal) refeitas"
contem "RECONECTAR: dkt_r1 dkt_r2" "$saida"; nao_contem "dkt_r3" "$(grep RECONECTAR <<< "$saida")"
contem "shr_remover nome=dkt-a pasta=$T/a acesso=@dkt_ra resultado=ok" "$(LOG)"
caso "remover: o grupo deixa de ser usado e pode ser removido"
igual "" "$(p "debkit_samba_grupo_usos dkt_ra")"
caso "criar de novo com a mesma pasta: volta para o grupo"
contem "RC=0" "$(criar dkt-a "$T/a" dkt_ra)"; igual "0 $GA 2770" "$(stat -c '%u %g %a' "$T/a")"

caso "remover: feito à mão (maiúsculas, continuação, repetido, comentários)"
mkdir "$T/manual"
cat >> "$AREIA/smb.conf" <<EOF

; nota do admin sobre o Manual
[Manual]
   comment = Feito \\
      a mao
   path = $T/manual
   Valid Users = @dkt_rb
   writeable = yes
   ; comentário de dentro
   force group = dkt_rb

# comentário do dkt-c
[dkt-c]
   path = $T/c
   valid users = @dkt_rb
   read only = no
[MANUAL]
   create mask = 0660
# fim do arquivo
EOF
mkdir "$T/c" "$T/dois"
contem "Manual|$T/manual|dkt_rb" "$(p debkit_shr_gerenciaveis)" "no padrão"
antes=$(efetivo)
saida=$(remover Manual)
contem "RC=0" "$saida"; nao_contem "anual]" "$(cat "$AREIA/smb.conf")" "as duas seções saíram"
nao_contem "comentário de dentro" "$(cat "$AREIA/smb.conf")"; nao_contem "fim do arquivo" "$(cat "$AREIA/smb.conf")"
contem "; nota do admin sobre o Manual" "$(cat "$AREIA/smb.conf")" "comentário antes da seção (sem ser do debkit) fica"
igual "# comentário do dkt-c" "$(grep -B1 '^\[dkt-c\]' "$AREIA/smb.conf" | head -1)" "o comentário da seção seguinte fica"
igual "$(sem_secao Manual <<< "$antes")" "$(efetivo | sem_secao Manual)" "o resto em vigor não mudou"
contem "RECONECTAR: dkt_r3" "$saida"

# ════════════════════════════════════════════════════════════════════════════
# Recusas e falhas
# ════════════════════════════════════════════════════════════════════════════
cat >> "$AREIA/smb.conf" <<EOF
[dkt-dois]
   path = $T/dois
   valid users = @dkt_ra @dkt_rb
   read only = no
[dkt-sem-pasta]
   path = $T/nao_existe
   valid users = @dkt_ra
   read only = no
EOF
caso "remover: recusa [homes], [global], [printers] e o que não existe, antes de mexer em qualquer coisa"
md5=$(md5sum < "$AREIA/smb.conf")
for n in homes global printers nao_existe ""; do
    contem "não existe" "$(remover "$n")" "share $n"
done
igual "$md5" "$(md5sum < "$AREIA/smb.conf")" "smb.conf intacto"
caso "remover: conferência falha - nada muda"
saida=$(remover dkt-a "debkit_shr_conferir_remover() { return 1; };")
contem "RC=1" "$saida"; contem "a alteração do smb.conf não foi feita" "$saida"
igual "$md5" "$(md5sum < "$AREIA/smb.conf")"; igual "0 $GA 2770" "$(stat -c '%u %g %a' "$T/a")" "pasta intacta"
contem "shr_remover nome=dkt-a pasta=$T/a acesso=@dkt_ra resultado=falha" "$(LOG)"
caso "remover: reload falha - smb.conf restaurado e pasta intacta"
saida=$(remover dkt-a "debkit_samba_recarregar() { return 1; };")
contem "RC=1" "$saida"; contem "restaurado do backup" "$saida"
igual "$md5" "$(md5sum < "$AREIA/smb.conf")"; igual "0 $GA 2770" "$(stat -c '%u %g %a' "$T/a")"
nao_contem "RECONECTAR" "$saida"
caso "remover: a pasta não muda - informado; o compartilhamento já saiu"
chattr +i "$T/a"
saida=$(remover dkt-a)
contem "RC=1" "$saida"; contem "não foi possível deixar a pasta $T/a só para o root" "$saida"
nao_contem "[dkt-a]" "$(efetivo)"; contem "RECONECTAR: dkt_r1 dkt_r2" "$saida" "as sessões são refeitas assim mesmo"
contem "resultado=pasta_falhou" "$(LOG)"
chattr -i "$T/a"

# ════════════════════════════════════════════════════════════════════════════
# Telas
# ════════════════════════════════════════════════════════════════════════════
tela() { local f="$1"; shift; printf '%s\n' "$@" | p "$f; echo RC=\$?"; }
idx_s() { p "debkit_shr_dados" | cut -d'|' -f1 | grep -nx -- "$1" | cut -d: -f1; }
contem "RC=0" "$(criar dkt-e "$T/base/dkt-e" dkt_ra)"
caso "tela remover: lista, resumo (pasta que fica, quem perde) e 'n'/Enter cancelam"
saida=$(tela debkit_shr_tela_remover "$(idx_s dkt-e)" n "")
contem "dkt-e (acesso: dkt_ra; $T/base/dkt-e)" "$saida"; contem "Compartilhamento: dkt-e" "$saida"
contem "Pasta: $T/base/dkt-e (os arquivos ficam no disco; só o root acessa)" "$saida"
contem "Perdem o acesso: dkt_r1, dkt_r2" "$saida"; contem "Cancelado" "$saida"
contem "Cancelado" "$(tela debkit_shr_tela_remover "")"
contem "[dkt-e]" "$(efetivo)" "continua"
caso "tela remover: 's' remove"
saida=$(tela debkit_shr_tela_remover "$(idx_s dkt-e)" s "")
contem "Compartilhamento dkt-e removido" "$saida"; nao_contem "[dkt-e]" "$(efetivo)"
igual "0 0 700" "$(stat -c '%u %g %a' "$T/base/dkt-e")"
caso "tela: nenhum compartilhamento"
contem "Nenhum compartilhamento no servidor" "$(tela "debkit_shr_dados() { :; }; debkit_shr_tela_remover")"
caso "menu Samba > Compartilhamentos > 5) Remover"
saida=$(pty 0.6 "bash $DEBKIT" 1 3 5 "" "" 0 0 0)
contem "5) Remover um compartilhamento" "$saida"; contem "6) Trazer um compartilhamento para o padrão" "$saida"; contem "7) Pastas pessoais" "$saida"; contem "Remover um compartilhamento" "$saida"
caso "inglês"
contem "Share dkt-c removed" "$(p "DEBKIT_IDIOMA=en; DEBKIT_S_NOME=dkt-c; debkit_shr_remover")"

limpar_tudo; trap - EXIT
caso "limpeza"
verdadeiro "nenhum usuário dkt_" bash -c "! getent passwd | grep -q '^dkt_'"
verdadeiro "pasta de teste apagada" test ! -e "$T"
real_intacto
resumo
