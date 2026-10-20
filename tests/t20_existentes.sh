#!/usr/bin/env bash
# Testes dos compartilhamentos já existentes, feitos à mão (Fase 2, tarefa
# 2.4; decisões na seção 3.7, item 6): quais podem ser trazidos para o
# padrão, trazer para o padrão (só as linhas que o debkit gerencia mudam;
# o resto da seção fica; conteúdo para o grupo; sessões de quem tinha o
# acesso) e remover os que estão fora do padrão (a pasta fora de /mnt e
# /srv, inexistente ou de outro compartilhamento não muda). smb.conf e base
# do Samba da areia; pastas em /srv/dkt-teste.* (apagadas no fim). A prova
# com o Samba de verdade está em t20b_existentes_real.sh.
source "$(dirname "$0")/lib.sh"
caixa_de_areia

if getent passwd | cut -d: -f1 | grep -q '^dkt_'; then echo "  já existem usuários dkt_* - abortando"; exit 1; fi
T=$(mktemp -d /srv/dkt-teste.XXXXXX); chmod 755 "$T"
limpar_tudo() {
    local x
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
groupadd dkt_xa; groupadd dkt_xb
useradd -M -s /usr/sbin/nologin -U dkt_x1; useradd -M -s /usr/sbin/nologin -U dkt_x2; useradd -M -s /usr/sbin/nologin -U dkt_x3
gpasswd -M dkt_x1 dkt_xa >/dev/null; gpasswd -M dkt_x2 dkt_xb >/dev/null
GB=$(getent group dkt_xb | cut -d: -f3)
mkdir "$T/base"
p "debkit_shr_definir_base '$T/base'" >/dev/null

padronizar() { p "${3:-} DEBKIT_S_NOME='$1'; DEBKIT_S_GRUPO='$2'; debkit_shr_padronizar; echo RC=\$?"; }
remover() { p "DEBKIT_S_NOME='$1'; debkit_shr_remover; echo RC=\$?"; }

contem "RC=0" "$(p "DEBKIT_S_NOME=dkt-a; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$T/a'; DEBKIT_S_GRUPO=dkt_xa; debkit_shr_criar; echo RC=\$?")"
mkdir "$T/velho" "$T/users" "$T/livre" "$T/dup"
echo x > "$T/velho/doc.txt"; chown dkt_x3:dkt_x3 "$T/velho/doc.txt"; chmod 644 "$T/velho/doc.txt"
cat >> "$AREIA/smb.conf" <<EOF

# compartilhamento antigo, feito à mão
[Velho]
   comment = Setor \\
      antigo
   path = $T/velho
   Valid Users = @dkt_xa, dkt_x3
   write list = dkt_x3
   read only = yes
   guest ok = yes
   create mode = 0644
   force user = dkt_x3
   browseable = no
   veto files = /*.tmp/
[dkt-users]
   path = $T/users
   valid users = @users
   read only = no
[dkt-livre]
   path = $T/livre
   read only = no
[dkt-fora]
   path = /opt
   valid users = @dkt_xa
   read only = no
[dkt-sem-pasta]
   path = $T/nao_existe
   valid users = @dkt_xa
   read only = no
[dkt-dup1]
   path = $T/dup
   valid users = @dkt_xa @dkt_xb
[dkt-dup2]
   path = $T/dup
   valid users = @dkt_xb
   read only = no
EOF

# ════════════════════════════════════════════════════════════════════════════
# Quais podem ser trazidos para o padrão
# ════════════════════════════════════════════════════════════════════════════
caso "padronizáveis: fora do padrão, com a pasta dentro de /mnt ou /srv, só deste compartilhamento"
saida=$(p debkit_shr_padronizaveis)
contem "Velho|$T/velho|dkt_x3|@dkt_xa|" "$saida"; contem "dkt-users|$T/users|@users||" "$saida" "um grupo que o debkit não gerencia"
contem "dkt-livre|$T/livre|*||todos" "$saida" "sem valid users"
for n in dkt-a dkt-fora dkt-sem-pasta dkt-dup1 dkt-dup2 homes global; do nao_contem "$n|" "$saida" "$n fora"; done
caso "usuários com acesso por uma lista"
igual "$(printf 'dkt_x1\ndkt_x3')" "$(p "debkit_shr_usuarios '@dkt_xa,dkt_x3'")"
igual "$(printf 'dkt_x1\ndkt_x2')" "$(p "debkit_shr_usuarios '@dkt_xb,,@dkt_xa'")"

# ════════════════════════════════════════════════════════════════════════════
# Trazer para o padrão
# ════════════════════════════════════════════════════════════════════════════
caso "padronizar: só as linhas que o debkit gerencia mudam; o resto da seção fica"
antes=$(efetivo); : > "$AREIA/reloads"
saida=$(padronizar Velho dkt_xb)
contem "RC=0" "$saida"; contem "Compartilhamento Velho no padrão: grupo dkt_xb com acesso total" "$saida"
igual "@dkt_xb" "$(param Velho 'valid users')"; igual "dkt_xb" "$(param Velho 'force group')"; igual "No" "$(param Velho 'read only')"
igual "0660" "$(param Velho 'create mask')"; igual "02770" "$(param Velho 'directory mask')"
igual "No" "$(param Velho 'guest ok')" "guest ok saiu"; igual "" "$(param Velho 'force user')" "force user saiu"
igual "" "$(param Velho 'write list')" "write list saiu"
igual "Setor antigo" "$(param Velho comment)" "comentário (com continuação) fica"
igual "No" "$(param Velho browseable)"; igual "/*.tmp/" "$(param Velho 'veto files')" "o resto da seção fica"
igual "$(sem_secao Velho <<< "$antes")" "$(efetivo | sem_secao Velho)" "o resto do smb.conf não mudou"
igual 1 "$(grep -c reload "$AREIA/reloads")" "Samba recarregado"
contem "# compartilhamento antigo, feito à mão" "$(cat "$AREIA/smb.conf")" "comentário antes da seção fica"
caso "padronizar: pasta e conteúdo para o grupo; sessões de quem tinha o acesso refeitas"
igual "0 $GB 2770" "$(stat -c '%u %g %a' "$T/velho")"
igual "$(id -u dkt_x3) $GB 660" "$(stat -c '%u %g %a' "$T/velho/doc.txt")" "dono igual, grupo novo"
contem "RECONECTAR: dkt_x1 dkt_x3" "$saida"
contem "shr_padrao nome=Velho antes=dkt_x3;leitura:@dkt_xa grupo=dkt_xb resultado=ok" "$(LOG)"
caso "padronizar: agora está no padrão (e sai da lista dos padronizáveis e dos alertas)"
contem "Velho|$T/velho|dkt_xb" "$(p debkit_shr_gerenciaveis)"; nao_contem "Velho|" "$(p debkit_shr_padronizaveis)"
nao_contem "Velho: fora do padrão" "$(p debkit_shr_listar)"
caso "padronizar: sem valid users (qualquer usuário)"
saida=$(padronizar dkt-livre dkt_xa)
contem "RC=0" "$saida"; igual "@dkt_xa" "$(param dkt-livre 'valid users')"

caso "padronizar: recusas antes de mexer em qualquer coisa"
md5=$(md5sum < "$AREIA/smb.conf")
for n in dkt-a dkt-fora dkt-sem-pasta dkt-dup1 homes nao_existe ""; do
    contem "não existe, já está no padrão ou a pasta não pode ser usada" "$(padronizar "$n" dkt_xa)" "share $n"
done
for g in sudo users dkt_x1 "$GRUPO_TESTE" dkt_nao_existe "dkt_xa dkt_xb"; do
    contem "não é um grupo comum que o debkit gerencia" "$(padronizar dkt-users "$g")" "grupo $g"
done
contem "Informe o grupo" "$(padronizar dkt-users "")"
igual "$md5" "$(md5sum < "$AREIA/smb.conf")" "smb.conf intacto"
caso "padronizar: conferência falha - nada muda"
saida=$(padronizar dkt-users dkt_xa "debkit_shr_conferir_padrao() { return 1; };")
contem "RC=1" "$saida"; contem "a alteração do smb.conf não foi feita" "$saida"
igual "$md5" "$(md5sum < "$AREIA/smb.conf")"; igual "0 0 755" "$(stat -c '%u %g %a' "$T/users")" "pasta intacta"
contem "shr_padrao nome=dkt-users antes=@users grupo=dkt_xa resultado=falha" "$(LOG)"
caso "padronizar: reload falha - smb.conf restaurado e pasta intacta"
saida=$(padronizar dkt-users dkt_xa "debkit_samba_recarregar() { return 1; };")
contem "RC=1" "$saida"; contem "restaurado do backup" "$saida"
igual "$md5" "$(md5sum < "$AREIA/smb.conf")"; igual "0 0 755" "$(stat -c '%u %g %a' "$T/users")"

# ════════════════════════════════════════════════════════════════════════════
# Remover os que estão fora do padrão
# ════════════════════════════════════════════════════════════════════════════
caso "remover: pasta fora de /mnt e /srv não muda"
opt=$(stat -c '%u %g %a' /opt)
saida=$(remover dkt-fora)
contem "RC=0" "$saida"; contem "Compartilhamento dkt-fora removido" "$saida"; contem "A pasta /opt não foi alterada" "$saida"
nao_contem "[dkt-fora]" "$(efetivo)"; igual "$opt" "$(stat -c '%u %g %a' /opt)" "/opt intacta"
contem "RECONECTAR: dkt_x1" "$saida"
contem "shr_remover nome=dkt-fora pasta=/opt acesso=@dkt_xa resultado=ok pasta=intocada" "$(LOG)"
caso "remover: sem a pasta"
saida=$(remover dkt-sem-pasta)
contem "RC=0" "$saida"; contem "não foi alterada" "$saida"; nao_contem "[dkt-sem-pasta]" "$(efetivo)"
caso "remover: pasta usada por outro compartilhamento não muda"
dup=$(stat -c '%u %g %a' "$T/dup")
saida=$(remover dkt-dup1)
contem "RC=0" "$saida"; nao_contem "[dkt-dup1]" "$(efetivo)"; contem "[dkt-dup2]" "$(efetivo)" "o outro fica"
igual "$dup" "$(stat -c '%u %g %a' "$T/dup")" "pasta intacta"
contem "RECONECTAR: dkt_x1 dkt_x2" "$saida"

# ════════════════════════════════════════════════════════════════════════════
# Telas
# ════════════════════════════════════════════════════════════════════════════
tela() { local f="$1"; shift; printf '%s\n' "$@" | p "$f; echo RC=\$?"; }
idx_p() { p "debkit_shr_padronizaveis" | cut -d'|' -f1 | grep -nx -- "$1" | cut -d: -f1; }
idx_d() { p "debkit_shr_dados" | cut -d'|' -f1 | grep -nx -- "$1" | cut -d: -f1; }
idx_g() { p "debkit_samba_grupos_comuns" | grep -nx "$1" | cut -d: -f1; }
caso "tela padronizar: lista, acesso atual, resumo, linhas do smb.conf, conteúdo e 'n'/Enter cancelam"
saida=$(tela debkit_shr_tela_padronizar "$(idx_p dkt-users)" "$(idx_g dkt_xb)" n "")
contem "dkt-users (acesso: users; $T/users)" "$saida"; contem "Acesso atual: users (pasta $T/users)" "$saida"
contem "Acesso: users -> dkt_xb (acesso total)" "$saida"; contem "valid users = @dkt_xb" "$saida"
contem "O resto da seção não muda" "$saida"; contem "Conteúdo de $T/users" "$saida"; contem "Cancelado" "$saida"
contem "Cancelado" "$(tela debkit_shr_tela_padronizar "")"
igual "@users" "$(param dkt-users 'valid users')" "continua"
caso "tela padronizar: quem perde o acesso e 's'"
printf '\n[dkt-perde]\n   path = %s/perde\n   valid users = @dkt_xa @dkt_xb\n   read only = no\n' "$T" >> "$AREIA/smb.conf"; mkdir "$T/perde"
saida=$(tela debkit_shr_tela_padronizar "$(idx_p dkt-perde)" "$(idx_g dkt_xb)" s "")
contem "Perdem o acesso: dkt_x1" "$saida"; contem "Compartilhamento dkt-perde no padrão" "$saida"
igual "@dkt_xb" "$(param dkt-perde 'valid users')"
caso "tela padronizar: nenhum"
contem "Nenhum compartilhamento fora do padrão pode ser trazido" "$(tela "debkit_shr_padronizaveis() { :; }; debkit_shr_tela_padronizar")"
caso "tela remover: feito à mão com a pasta de outro - a pasta não muda"
saida=$(tela debkit_shr_tela_remover "$(idx_d dkt-users)" n "")
contem "Pasta: $T/users (os arquivos ficam no disco; só o root acessa)" "$saida"
printf '\n[dkt-dup3]\n   path = %s/dup\n   valid users = @dkt_xa\n' "$T" >> "$AREIA/smb.conf"
saida=$(tela debkit_shr_tela_remover "$(idx_d dkt-dup3)" s "")
contem "dkt-dup3 (acesso: dkt_xa (somente leitura); $T/dup)" "$saida"
contem "Pasta: $T/dup (não muda: fora de /mnt e /srv, inexistente ou usada por outro compartilhamento)" "$saida"
contem "Compartilhamento dkt-dup3 removido" "$saida"; igual "$dup" "$(stat -c '%u %g %a' "$T/dup")"
caso "menu Samba > Compartilhamentos > 6) Trazer para o padrão"
saida=$(pty 0.6 "bash $DEBKIT" 1 3 6 "" "" 0 0 0)
contem "6) Trazer um compartilhamento para o padrão" "$saida"; contem "7) Pastas pessoais" "$saida"
contem "dkt-users (acesso: users" "$saida"
caso "inglês"
contem "Share dkt-users in the pattern" "$(p "DEBKIT_IDIOMA=en; DEBKIT_S_NOME=dkt-users; DEBKIT_S_GRUPO=dkt_xa; debkit_shr_padronizar")"

limpar_tudo; trap - EXIT
caso "limpeza"
verdadeiro "nenhum usuário dkt_" bash -c "! getent passwd | grep -q '^dkt_'"
verdadeiro "pasta de teste apagada" test ! -e "$T"
real_intacto
resumo
