#!/usr/bin/env bash
# Testes de grupo e permissões dos compartilhamentos (Fase 2, tarefa 2.2;
# decisões na seção 3.7): quais estão no padrão, trocar o grupo (smb.conf
# pela edição segura, conteúdo para o grupo novo, quem perde o acesso),
# ajustar as permissões do conteúdo e recusar remover um grupo usado no
# Samba. smb.conf e base do Samba da areia; pastas em /srv/dkt-teste.*
# (apagadas no fim). A prova com o Samba de verdade está em
# t18b_permissoes_real.sh.
source "$(dirname "$0")/lib.sh"
caixa_de_areia

if getent passwd | cut -d: -f1 | grep -q '^dkt_'; then echo "  já existem usuários dkt_* - abortando"; exit 1; fi
T=$(mktemp -d /srv/dkt-teste.XXXXXX); chmod 755 "$T"
limpar_tudo() {
    local x
    mountpoint -q "$T/a/montado" 2>/dev/null && umount "$T/a/montado"
    [ -e "$T/a/preso" ] && chattr -i "$T/a/preso" 2>/dev/null
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
param() { testparm -s --section-name="$1" --parameter-name="$2" "$AREIA/smb.conf" 2>/dev/null; }
sem_secao() { awk -v s="[$1]" '/^\[/ { em = ($0 == s) } !em && NF'; }
groupadd dkt_fa; groupadd dkt_fb; groupadd dkt_fc
useradd -M -s /usr/sbin/nologin -U dkt_ua; useradd -M -s /usr/sbin/nologin -U dkt_ub; useradd -M -s /usr/sbin/nologin -U dkt_uab
gpasswd -M dkt_ua,dkt_uab dkt_fa >/dev/null; gpasswd -M dkt_ub,dkt_uab dkt_fb >/dev/null
GA=$(getent group dkt_fa | cut -d: -f3); GB=$(getent group dkt_fb | cut -d: -f3)
UA=$(id -u dkt_ua)
mkdir "$T/base"
p "debkit_shr_definir_base '$T/base'" >/dev/null

criar() { p "DEBKIT_S_NOME='$1'; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$2'; DEBKIT_S_GRUPO='$3'; debkit_shr_criar; echo RC=\$?"; }
trocar() { p "${3:-} DEBKIT_S_NOME='$1'; DEBKIT_S_GRUPO='$2'; debkit_shr_trocar_grupo; echo RC=\$?"; }
pend() { p "debkit_shr_pendentes '$1' $2"; }

# ════════════════════════════════════════════════════════════════════════════
# Quais estão no padrão
# ════════════════════════════════════════════════════════════════════════════
contem "RC=0" "$(criar dkt-a "$T/a" dkt_fa)"
mkdir "$T/manual" "$T/dois" "$T/users" "$T/livre"
cat >> "$AREIA/smb.conf" <<EOF

[Manual]
   comment = Feito a mao
   path = $T/manual
   Valid Users = @dkt_fa
   writeable = yes
   writelist = @dkt_fa, \\
      @dkt_fa
   group = dkt_fa
   create mask = 0640
[dkt-dois]
   path = $T/dois
   valid users = @dkt_fa @dkt_fb
   read only = no
[dkt-users]
   path = $T/users
   valid users = @users
   read only = no
[dkt-sem-pasta]
   path = $T/nao_existe
   valid users = @dkt_fa
   read only = no
[dkt-livre]
   path = $T/livre
   read only = no
EOF
caso "no padrão: um grupo gerenciado com acesso total e a pasta existindo (inclusive feito à mão)"
saida=$(p debkit_shr_gerenciaveis)
contem "dkt-a|$T/a|dkt_fa" "$saida"; contem "Manual|$T/manual|dkt_fa" "$saida" "feito à mão, com sinônimos"
for n in dkt-dois dkt-users dkt-sem-pasta dkt-livre global homes printers; do nao_contem "$n|" "$saida" "$n fora"; done
caso "no padrão: só pasta segura (dentro de /mnt ou /srv, só deste compartilhamento)"
cp -p "$AREIA/smb.conf" "$AREIA/smb.conf.antes"
printf '\n[dkt-opt]\n   path = /opt\n   valid users = @dkt_fa\n   read only = no\n' >> "$AREIA/smb.conf"
saida=$(p debkit_shr_gerenciaveis); nao_contem "dkt-opt|" "$saida" "fora de /mnt e /srv"; contem "dkt-a|" "$saida"
printf '\n[dkt-dentro]\n   path = %s/a/sub\n   valid users = @dkt_fb\n   read only = no\n' "$T" >> "$AREIA/smb.conf"
mkdir -p "$T/a/sub"
saida=$(p debkit_shr_gerenciaveis); nao_contem "dkt-a|" "$saida" "contém a pasta de outro"; nao_contem "dkt-dentro|" "$saida" "dentro da pasta de outro"
contem "RC=1" "$(p "debkit_shr_ajustar_conteudo '$T/a' dkt_fa; echo RC=\$?")" "o ajuste também recusa"
rmdir "$T/a/sub"
cat "$AREIA/smb.conf.antes" > "$AREIA/smb.conf"
printf '\n[dkt-igual]\n   path = %s/a/\n   valid users = @dkt_fa\n   read only = no\n' "$T" >> "$AREIA/smb.conf"
saida=$(p debkit_shr_gerenciaveis); nao_contem "dkt-a|" "$saida" "mesma pasta em dois"; nao_contem "dkt-igual|" "$saida"
contem "não está no padrão do debkit" "$(trocar dkt-a dkt_fb)"
cat "$AREIA/smb.conf.antes" > "$AREIA/smb.conf"
mkdir -p "$T/homes"
saida=$(p "DEBKIT_HOMES_BASE='$T'; debkit_shr_gerenciaveis"); nao_contem "dkt-a|" "$saida" "dentro da base das pastas pessoais"
rmdir "$T/homes"
contem "dkt-a|" "$(p debkit_shr_gerenciaveis)" "de volta"

# ════════════════════════════════════════════════════════════════════════════
# Ajustar o conteúdo
# ════════════════════════════════════════════════════════════════════════════
mkdir -p "$T/a/sub/fundo" "$T/fora"
echo x > "$T/a/doc.txt"; chown dkt_ua:dkt_ua "$T/a/doc.txt"; chmod 644 "$T/a/doc.txt"
echo x > "$T/a/sub/fundo/f.txt"; chown dkt_ub:dkt_fb "$T/a/sub/fundo/f.txt"; chmod 600 "$T/a/sub/fundo/f.txt"
echo x > "$T/a/prog"; chown dkt_ua:dkt_fa "$T/a/prog"; chmod 6755 "$T/a/prog"
chown dkt_ua:dkt_ua "$T/a/sub"; chmod 755 "$T/a/sub"
echo x > "$T/fora/alvo"; chmod 644 "$T/fora/alvo"; ln -s "$T/fora/alvo" "$T/a/link"; ln -s "$T/fora" "$T/a/linkpasta"
caso "pendentes: conta o que está fora do padrão"
igual 6 "$(p "debkit_shr_contar '$T/a'")" "a, doc, sub, fundo, f.txt, prog (links não contam)"
igual 5 "$(pend "$T/a" "$GA")" "doc (grupo e outros), sub, fundo, f.txt, prog (setuid)"
caso "ajustar: tudo para o grupo, rw para o grupo, sem outros, sem setuid; donos e links como estão"
saida=$(p "debkit_shr_ajustar_conteudo '$T/a' dkt_fa; echo RC=\$?")
contem "RC=0" "$saida"; contem "Permissões de $T/a ajustadas: 6 item(ns)" "$saida"
igual "0 $GA 2770" "$(stat -c '%u %g %a' "$T/a")" "a pasta"
igual "$UA $GA 660" "$(stat -c '%u %g %a' "$T/a/doc.txt")" "arquivo: dono igual, grupo, 660"
igual "$(id -u dkt_ub) $GA 660" "$(stat -c '%u %g %a' "$T/a/sub/fundo/f.txt")" "arquivo fundo"
igual "$UA $GA 2770" "$(stat -c '%u %g %a' "$T/a/sub")" "subpasta 2770, dono igual"
igual "2770" "$(stat -c '%a' "$T/a/sub/fundo")"
igual "770" "$(stat -c '%a' "$T/a/prog")" "executável continua executável, sem setuid/setgid"
igual "0 0 644" "$(stat -c '%u %g %a' "$T/fora/alvo")" "alvo do link fora não mudou"
igual "0 0 755" "$(stat -c '%u %g %a' "$T/fora")" "pasta do link fora não mudou"
igual 0 "$(pend "$T/a" "$GA")"
contem "shr_ajustar pasta=$T/a grupo=dkt_fa itens=6 resultado=ok" "$(LOG)"
caso "ajustar: rodar de novo não muda nada"
antes=$(find "$T/a" -printf '%p %u %g %m\n' | sort)
contem "RC=0" "$(p "debkit_shr_ajustar_conteudo '$T/a' dkt_fa; echo RC=\$?")"
igual "$antes" "$(find "$T/a" -printf '%p %u %g %m\n' | sort)"
caso "ajustar: não entra em outro disco montado dentro da pasta"
mkdir "$T/a/montado"; mount -t tmpfs -o size=1m tmpfs "$T/a/montado"; echo x > "$T/a/montado/m.txt"; chmod 644 "$T/a/montado/m.txt"
contem "RC=0" "$(p "debkit_shr_ajustar_conteudo '$T/a' dkt_fa; echo RC=\$?")"
igual "0 644" "$(stat -c '%g %a' "$T/a/montado/m.txt")" "arquivo do outro disco intocado"
umount "$T/a/montado"; rmdir "$T/a/montado"
caso "ajustar: o que não dá para mudar é informado (e auditado)"
echo x > "$T/a/preso"; chmod 644 "$T/a/preso"; chattr +i "$T/a/preso"
saida=$(p "debkit_shr_ajustar_conteudo '$T/a' dkt_fa; echo RC=\$?")
contem "RC=1" "$saida"; contem "1 item(ns) ainda fora do padrão" "$saida"; contem "Rode de novo" "$saida"
contem "resultado=falha" "$(LOG)"
chattr -i "$T/a/preso"; rm -f "$T/a/preso"
caso "ajustar: pasta ou grupo que não existe"
contem "a pasta precisa existir dentro de /mnt ou /srv" "$(p "debkit_shr_ajustar_conteudo '$T/nada' dkt_fa; echo RC=\$?")"
contem "RC=1" "$(p "debkit_shr_ajustar_conteudo '$T/a' dkt_nao_existe; echo RC=\$?")"

# ════════════════════════════════════════════════════════════════════════════
# Trocar o grupo
# ════════════════════════════════════════════════════════════════════════════
caso "trocar: smb.conf, conteúdo para o grupo novo e quem perde o acesso"
antes=$(efetivo); : > "$AREIA/reloads"
saida=$(trocar dkt-a dkt_fb)
contem "RC=0" "$saida"; contem "Compartilhamento dkt-a agora é do grupo dkt_fb" "$saida"
igual "@dkt_fb" "$(param dkt-a 'valid users')"; igual "dkt_fb" "$(param dkt-a 'force group')"; igual "No" "$(param dkt-a 'read only')"
igual "$(sem_secao dkt-a <<< "$antes")" "$(efetivo | sem_secao dkt-a)" "o resto do smb.conf não mudou"
igual 1 "$(grep -c reload "$AREIA/reloads")" "Samba recarregado"
igual "0 $GB 2770" "$(stat -c '%u %g %a' "$T/a")"; igual "$GB" "$(stat -c %g "$T/a/doc.txt")" "conteúdo no grupo novo"
contem "RECONECTAR: dkt_ua" "$saida" "dkt_ua perde (dkt_uab está nos dois)"; nao_contem "dkt_uab" "$(grep RECONECTAR <<< "$saida")"
contem "shr_grupo nome=dkt-a antigo=dkt_fa novo=dkt_fb resultado=ok" "$(LOG)"
igual "$(grep -c '^\[dkt-a\]' "$AREIA/smb.conf")" 1 "uma seção só"
caso "trocar: feito à mão (sinônimos, maiúsculas, continuação) - só as linhas de acesso mudam"
saida=$(trocar Manual dkt_fc)
contem "RC=0" "$saida"
igual "@dkt_fc" "$(param Manual 'valid users')"; igual "dkt_fc" "$(param Manual 'force group')"; igual "No" "$(param Manual 'read only')"
igual "" "$(param Manual 'write list')" "write list saiu (com a continuação)"
igual "Feito a mao" "$(param Manual comment)"; igual "0640" "$(param Manual 'create mask')" "o resto da seção fica"
nao_contem "@dkt_fa" "$(sed -n '/^\[Manual\]/,/^\[/p' "$AREIA/smb.conf")" "nenhuma linha antiga sobrou"
contem "RECONECTAR: dkt_ua dkt_uab" "$saida"

caso "trocar: recusas antes de mexer em qualquer coisa"
md5=$(md5sum < "$AREIA/smb.conf")
contem "já é o grupo do compartilhamento" "$(trocar dkt-a dkt_fb)"
for n in dkt-dois dkt-users dkt-sem-pasta dkt-livre homes nao_existe ""; do
    contem "não está no padrão do debkit" "$(trocar "$n" dkt_fa)" "share $n"
done
for g in sudo users dkt_ua "$GRUPO_TESTE" dkt_nao_existe "dkt_fa dkt_fb"; do
    contem "não é um grupo comum que o debkit gerencia" "$(trocar dkt-a "$g")" "grupo $g"
done
contem "Informe o grupo" "$(trocar dkt-a "")"
igual "$md5" "$(md5sum < "$AREIA/smb.conf")" "smb.conf intacto"; igual "$GB" "$(stat -c %g "$T/a")" "pasta intacta"
caso "trocar: conferência falha - nada muda"
saida=$(trocar dkt-a dkt_fa "debkit_shr_conferir_grupo() { return 1; };")
contem "RC=1" "$saida"; contem "a alteração do smb.conf não foi feita" "$saida"
igual "$md5" "$(md5sum < "$AREIA/smb.conf")"; igual "$GB" "$(stat -c %g "$T/a/doc.txt")" "conteúdo intacto"
contem "shr_grupo nome=dkt-a antigo=dkt_fb novo=dkt_fa resultado=falha" "$(LOG)"
caso "trocar: reload falha - smb.conf restaurado e conteúdo intacto"
saida=$(trocar dkt-a dkt_fa "debkit_samba_recarregar() { return 1; };")
contem "RC=1" "$saida"; contem "restaurado do backup" "$saida"
igual "$md5" "$(md5sum < "$AREIA/smb.conf")"; igual "$GB" "$(stat -c %g "$T/a/doc.txt")"
caso "trocar: conteúdo que não muda é informado, o compartilhamento já fica com o grupo novo"
echo x > "$T/a/preso"; chattr +i "$T/a/preso"
saida=$(trocar dkt-a dkt_fa)
contem "RC=1" "$saida"; contem "agora é do grupo dkt_fa" "$saida"; contem "Rode de novo" "$saida"
igual "@dkt_fa" "$(param dkt-a 'valid users')"
chattr -i "$T/a/preso"; rm -f "$T/a/preso"
contem "RC=0" "$(p "debkit_shr_ajustar_conteudo '$T/a' dkt_fa; echo RC=\$?")" "rodar de novo resolve"

# ════════════════════════════════════════════════════════════════════════════
# Remover grupo usado no Samba: recusado
# ════════════════════════════════════════════════════════════════════════════
caso "remover grupo usado num compartilhamento: recusado"
saida=$(p "debkit_grupo_remover dkt_fa; echo RC=\$?")
contem "RC=1" "$saida"; contem "O grupo dkt_fa é usado no Samba ([dkt-a] [dkt-dois] [dkt-sem-pasta])" "$saida"
contem "Trocar o grupo" "$saida"; verdadeiro "continua" getent group dkt_fa

# ════════════════════════════════════════════════════════════════════════════
# Telas
# ════════════════════════════════════════════════════════════════════════════
tela() { local f="$1"; shift; printf '%s\n' "$@" | p "$f; echo RC=\$?"; }
idx_s() { p "debkit_shr_gerenciaveis" | cut -d'|' -f1 | grep -nx -- "$1" | cut -d: -f1; }
idx_o() { p "debkit_samba_grupos_comuns" | grep -vx "$2" | grep -nx "$1" | cut -d: -f1; }
caso "tela trocar: lista, grupo atual fora da lista, resumo, quem perde, conteúdo e 's'"
chmod o+r "$T/a/doc.txt"
saida=$(tela debkit_shr_tela_trocar "$(idx_s dkt-a)" "$(idx_o dkt_fb dkt_fa)" s "")
contem "dkt-a (grupo dkt_fa, $T/a)" "$saida"; contem "Grupo atual: dkt_fa" "$saida"
contem "Grupo: dkt_fa -> dkt_fb" "$saida"; contem "Perdem o acesso (membros de dkt_fa que não estão em dkt_fb): dkt_ua" "$saida"
contem "fora do padrão" "$saida"; contem "Os donos dos arquivos não mudam" "$saida"
contem "agora é do grupo dkt_fb" "$saida"; igual "@dkt_fb" "$(param dkt-a 'valid users')"
igual "$GB 660" "$(stat -c '%g %a' "$T/a/doc.txt")"
nao_contem ") dkt_fa" "$saida" "o grupo atual não está entre as opções"
caso "tela trocar: 'n' e Enter cancelam"
contem "Cancelado" "$(tela debkit_shr_tela_trocar "$(idx_s dkt-a)" "$(idx_o dkt_fa dkt_fb)" n "")"
contem "Cancelado" "$(tela debkit_shr_tela_trocar "")"
igual "@dkt_fb" "$(param dkt-a 'valid users')"
caso "tela ajustar: mostra o que está fora e ajusta com 's'; tudo certo não pergunta"
chmod o+r "$T/a/doc.txt"
saida=$(tela debkit_shr_tela_ajustar "$(idx_s dkt-a)" s "")
contem "1 fora do padrão" "$saida"; contem "Permissões de $T/a ajustadas" "$saida"; igual "660" "$(stat -c %a "$T/a/doc.txt")"
saida=$(tela debkit_shr_tela_ajustar "$(idx_s dkt-a)" "")
contem "todos já no padrão" "$saida"; nao_contem "Ajustar as permissões do conteúdo de" "$saida"
caso "tela: nenhum compartilhamento no padrão"
contem "Nenhum compartilhamento no padrão" "$(tela "debkit_shr_gerenciaveis() { :; }; debkit_shr_tela_trocar")"
caso "tela criar: pasta com arquivos oferece ajustar o conteúdo"
mkdir "$T/cheia"; echo x > "$T/cheia/x.txt"; chmod 644 "$T/cheia/x.txt"
idx_g() { p "debkit_samba_grupos_comuns" | grep -nx "$1" | cut -d: -f1; }
saida=$(tela debkit_shr_tela_criar "dkt-cheia" "" "$T/cheia" "$(idx_g dkt_fc)" s s "")
contem "Compartilhamento dkt-cheia criado" "$saida"; contem "1 fora do padrão" "$saida"; contem "Permissões de $T/cheia ajustadas" "$saida"
igual "$(getent group dkt_fc | cut -d: -f3) 660" "$(stat -c '%g %a' "$T/cheia/x.txt")"
caso "menu Samba > Compartilhamentos"
saida=$(pty 0.6 "bash $DEBKIT" 1 3 "" 0 0 0)
contem "3) Trocar o grupo de um compartilhamento" "$saida"; contem "4) Ajustar as permissões do conteúdo" "$saida"
contem "5) Remover um compartilhamento" "$saida"; contem "7) Pastas pessoais" "$saida"
caso "inglês"
contem "now belongs to group dkt_fc" "$(p "DEBKIT_IDIOMA=en; DEBKIT_S_NOME=dkt-a; DEBKIT_S_GRUPO=dkt_fc; debkit_shr_trocar_grupo")"

limpar_tudo; trap - EXIT
caso "limpeza"
verdadeiro "nenhum usuário dkt_" bash -c "! getent passwd | grep -q '^dkt_'"
verdadeiro "pasta de teste apagada" test ! -e "$T"
real_intacto
resumo
