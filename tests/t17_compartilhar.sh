#!/usr/bin/env bash
# Testes de criar e listar compartilhamentos (Fase 2, tarefa 2.1; decisões
# na seção 3.7): nome, descrição, pasta só em /mnt ou /srv, base, um grupo
# com acesso total, criação tudo ou nada e listagem
# (inclusive dos feitos à mão). smb.conf e base do Samba da areia; pastas em
# /srv/dkt-teste.* (apagadas no fim). A prova com o Samba de verdade está
# em t17b_compartilhar_real.sh.
source "$(dirname "$0")/lib.sh"
caixa_de_areia

if getent passwd | cut -d: -f1 | grep -q '^dkt_'; then echo "  já existem usuários dkt_* - abortando"; exit 1; fi
T=$(mktemp -d /srv/dkt-teste.XXXXXX); chmod 755 "$T"
limpar_tudo() {
    local x
    mountpoint -q "$T/tmpfs" && umount "$T/tmpfs"
    for x in $(getent passwd | cut -d: -f1 | grep '^dkt_'); do userdel "$x" >/dev/null 2>&1; done
    for x in $(getent group | cut -d: -f1 | grep '^dkt_'); do groupdel "$x" >/dev/null 2>&1; done
    rm -rf -- "${T:?}" "${AREIA:?}"
}
trap limpar_tudo EXIT

copiar_smb_conf "$AREIA/smb.conf"
# Só as seções padrão: os compartilhamentos que já existam na VM (ex: os de
# demonstração) não interferem nos nomes nem na contagem
awk '/^[ \t]*\[/ { s = tolower($0); gsub(/[ \t\[\]]/, "", s); fora = (s != "global" && s != "homes" && s != "printers" && s != "print$") } !fora' \
    "$AREIA/smb.conf" > "$AREIA/smb.conf.novo" && cat "$AREIA/smb.conf.novo" > "$AREIA/smb.conf" && rm -f "$AREIA/smb.conf.novo"
preparar_areia
CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;
     debkit_samba_recarregar() { echo reload >> '$AREIA/reloads'; };"
p() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
LOG() { cat "$AREIA/debkit.log" 2>/dev/null; }
efetivo() { testparm -s "$AREIA/smb.conf" 2>/dev/null; }
param() { testparm -s --section-name="$1" --parameter-name="$2" "$AREIA/smb.conf" 2>/dev/null; }
sem_secao() { awk -v s="[$1]" '/^\[/ { em = ($0 == s) } !em'; }
groupadd dkt_fin; groupadd dkt_dir; groupadd dkt_ti
useradd -M -s /usr/sbin/nologin -U dkt_u1
GFIN=$(getent group dkt_fin | cut -d: -f3)

# ════════════════════════════════════════════════════════════════════════════
# Regras
# ════════════════════════════════════════════════════════════════════════════
nome() { p "debkit_shr_nome_problema '$1'; echo RC=\$?"; }
caso "nome: válidos"
for n in financeiro ti-docs rh_2026 ab x1 "$(printf 'a%.0s' {1..32})"; do contem "RC=0" "$(nome "$n")" "$n"; done
caso "nome: só minúsculas, sem acento, sem espaço, começa por letra, termina em letra/número"
for n in Financeiro FINANCEIRO "ti docs" ção 1ab -ab ab- ab_ 'ab$' 'a.b' 'a/b' 'a@b'; do contem "Nome inválido" "$(nome "$n")" "$n"; done
contem "use de 2 a 32" "$(nome a)"; contem "use de 2 a 32" "$(nome "$(printf 'a%.0s' {1..33})")"
contem "Informe o nome" "$(nome '')"
caso "nome: reservados e seções que já existem (sem diferenciar maiúsculas)"
for n in global homes printers; do contem "nome reservado do Samba" "$(nome "$n")" "$n"; done
printf '\n[Manual_X]\n   path = %s\n' "$T" >> "$AREIA/smb.conf"
contem "Já existe um compartilhamento" "$(nome manual_x)"
caso "descrição"
contem "RC=0" "$(p "debkit_shr_comentario_problema 'Setor Financeiro - Contábil'; echo RC=\$?")"
contem "RC=0" "$(p "debkit_shr_comentario_problema ''; echo RC=\$?")" "vazia"
for c in 'a\b' '100%' "$(printf 'a\tb')"; do contem "Descrição inválida" "$(p "debkit_shr_comentario_problema '$c'")" "$c"; done
contem "muito longa" "$(p "debkit_shr_comentario_problema '$(printf 'x%.0s' {1..101})'")"

raiz() { p "debkit_shr_raiz_problema '$1'; echo RC=\$?"; }
pasta() { p "${2:-} debkit_shr_pasta_problema '$1'; echo RC=\$?"; }
caso "pasta: só dentro de /mnt ou /srv"
contem "RC=0" "$(raiz "$T/nova")"; contem "RC=0" "$(raiz /mnt/dados/x)"
for d in /mnt /srv /home/x /tmp/x /var/lib/x /etc/x /opt/x /srvx/a /mntdados; do contem "dentro de /mnt ou /srv" "$(raiz "$d")" "$d"; done
contem "caminho completo" "$(raiz srv/x)"
caso "pasta: link, arquivo, tmpfs"
ln -s "$T" "$T/link"; contem "caminho real" "$(raiz "$T/link/x")"
touch "$T/arquivo"; contem "não é uma pasta" "$(pasta "$T/arquivo")"
mkdir "$T/tmpfs"; mount -t tmpfs -o size=1m tmpfs "$T/tmpfs"
contem "não é um disco de dados" "$(raiz "$T/tmpfs/x")"
umount "$T/tmpfs"
caso "pasta: a de cima precisa existir"
contem "a pasta de cima" "$(pasta "$T/nao/existe")"
caso "pasta: não se mistura com a base das pastas pessoais nem com outro compartilhamento"
mkdir -p "$T/homes"
H="DEBKIT_HOMES_BASE='$T/homes';"
contem "base das pastas pessoais" "$(pasta "$T/homes" "$H")"; contem "base das pastas pessoais" "$(pasta "$T/homes/x" "$H")"
contem "base das pastas pessoais" "$(pasta "$T" "$H")" "contém a base"
contem "pasta de outro compartilhamento" "$(pasta "$T")" "o [Manual_X] usa $T"
sed -i "/^\[Manual_X\]/,\$d" "$AREIA/smb.conf"
contem "RC=0" "$(pasta "$T/livre")"

caso "base: sugestão (disco de dados em /mnt ou /srv/samba) e definir"
igual "/mnt/disco1/compartilhamentos" "$(p "debkit_samba_discos_dados() { echo /media/x; echo /mnt/disco1; }; debkit_shr_sugerir_base")"
igual "/srv/samba" "$(p "debkit_samba_discos_dados() { :; }; debkit_shr_sugerir_base")"
saida=$(p "debkit_shr_definir_base '$T/base'; echo RC=\$?")
contem "RC=0" "$saida"; contem "Base dos compartilhamentos: $T/base" "$saida"
igual "0 0 755" "$(stat -c '%u %g %a' "$T/base")" "base root 755"
contem "SHARES_BASE=$T/base" "$(cat "$AREIA/debkit.conf")"
contem "dentro de /mnt ou /srv" "$(p "debkit_shr_definir_base /home/base")"

# ════════════════════════════════════════════════════════════════════════════
# Criar
# ════════════════════════════════════════════════════════════════════════════
criar() {  # criar <nome> <pasta> <grupo> [prefixo]
    p "${4:-} DEBKIT_S_NOME='$1'; DEBKIT_S_COMENTARIO='${COMENT:-}'; DEBKIT_S_PASTA='$2';
       DEBKIT_S_GRUPO='$3'; debkit_shr_criar; echo RC=\$?"
}
caso "criar: pasta nova, um grupo com acesso total"
antes=$(efetivo); : > "$AREIA/reloads"
saida=$(COMENT="Setor Financeiro" criar financeiro "$T/base/financeiro" "dkt_fin")
contem "RC=0" "$saida"; contem "Compartilhamento financeiro criado" "$saida"
igual "0 $GFIN 2770" "$(stat -c '%u %g %a' "$T/base/financeiro")" "pasta root:grupo 2770"
igual "$T/base/financeiro" "$(param financeiro path)"
igual "@dkt_fin" "$(param financeiro 'valid users')"
igual "" "$(param financeiro 'write list')"; igual "No" "$(param financeiro 'read only')"
igual "dkt_fin" "$(param financeiro 'force group')"
igual "0660" "$(param financeiro 'create mask')"; igual "02770" "$(param financeiro 'directory mask')"
igual "Setor Financeiro" "$(param financeiro comment)"
igual "$(sem_secao financeiro <<< "$antes")" "$(efetivo | sem_secao financeiro)" "o resto do smb.conf não mudou"
contem "# debkit: compartilhamento criado em" "$(cat "$AREIA/smb.conf")"
igual 1 "$(grep -c reload "$AREIA/reloads")" "Samba recarregado"
verdadeiro "backup do smb.conf" test -n "$(find "$AREIA/conf-bkp" -name 'smb.conf.*')"
contem "shr_criar nome=financeiro pasta=$T/base/financeiro grupo=dkt_fin resultado=ok" "$(LOG)"
caso "criar: o mesmo grupo pode ter mais de um compartilhamento"
contem "RC=0" "$(criar consulta "$T/base/consulta" "dkt_fin")"
igual "@dkt_fin" "$(param consulta 'valid users')"; igual "$GFIN" "$(stat -c %g "$T/base/consulta")"
caso "criar: pasta que já existe (vazia) tem dono e permissões ajustados"
mkdir "$T/existente"; chown dkt_u1:dkt_u1 "$T/existente"; chmod 755 "$T/existente"
contem "RC=0" "$(criar existente "$T/existente" "dkt_ti")"
igual "0 $(getent group dkt_ti | cut -d: -f3) 2770" "$(stat -c '%u %g %a' "$T/existente")"

caso "criar: recusas antes de mexer em qualquer coisa"
md5=$(md5sum < "$AREIA/smb.conf")
contem "Informe o grupo" "$(criar r1 "$T/r1" "")"
for g in sudo users daemon dkt_u1 "$GRUPO_TESTE" dkt_nao_existe "dkt_fin dkt_ti"; do
    contem "não é um grupo comum que o debkit gerencia" "$(criar r1 "$T/r1" "$g")" "$g"
done
contem "Já existe um compartilhamento" "$(criar financeiro "$T/r1" "dkt_fin")"
contem "Nome inválido" "$(criar R1 "$T/r1" "dkt_fin")"
contem "dentro de /mnt ou /srv" "$(criar r1 /home/r1 "dkt_fin")"
contem "pasta de outro compartilhamento" "$(criar r1 "$T/base/financeiro/sub" "dkt_fin")"
contem "Descrição inválida" "$(COMENT='50%' criar r1 "$T/r1" "dkt_fin")"
igual "$md5" "$(md5sum < "$AREIA/smb.conf")" "smb.conf intacto"; verdadeiro "nenhuma pasta criada" test ! -e "$T/r1"
caso "criar: conferência do smb.conf falha - nada fica (pasta nova apagada)"
saida=$(criar r2 "$T/r2" "dkt_fin" "debkit_shr_conferir_criar() { return 1; };")
contem "RC=1" "$saida"; contem "mais do que o pretendido" "$saida"
verdadeiro "pasta apagada" test ! -e "$T/r2"; igual "$md5" "$(md5sum < "$AREIA/smb.conf")" "smb.conf intacto"
contem "shr_criar nome=r2 resultado=falha" "$(LOG)"
caso "criar: reload falha - smb.conf restaurado e pasta já existente volta como era"
mkdir "$T/r3"; chown dkt_u1:dkt_u1 "$T/r3"; chmod 750 "$T/r3"
saida=$(criar r3 "$T/r3" "dkt_fin" "debkit_samba_recarregar() { return 1; };")
contem "RC=1" "$saida"; contem "restaurado do backup" "$saida"
igual "$md5" "$(md5sum < "$AREIA/smb.conf")" "smb.conf de volta"
igual "$(id -u dkt_u1) $(id -g dkt_u1) 750" "$(stat -c '%u %g %a' "$T/r3")" "dono e permissões de antes"

# ════════════════════════════════════════════════════════════════════════════
# Listar (inclusive feitos à mão)
# ════════════════════════════════════════════════════════════════════════════
cat >> "$AREIA/smb.conf" <<EOF

[manual1]
   path = $T/existente
   valid users = @dkt_ti dkt_u1
   write list = dkt_u1
[manual2]
   path = $T/nao_existe
   guest ok = yes
   read only = no
[manual3]
   path = $T/base
   valid users = @dkt_fin, +dkt_dir
   read list = @dkt_dir
   read only = no
[manual4]
   path = $T/base
   valid users = @dkt_fin @dkt_ti
   read only = no
EOF
dados() { p "debkit_shr_dados" | grep "^$1|"; }
caso "dados: escrita e leitura calculadas como o Samba faz"
igual "financeiro|$T/base/financeiro|@dkt_fin||" "$(dados financeiro)" "padrão do debkit: sem alerta"
igual "consulta|$T/base/consulta|@dkt_fin||" "$(dados consulta)"
igual "manual1|$T/existente|dkt_u1|@dkt_ti|fora_padrao" "$(dados manual1)" "usuário no write list escreve; o resto só lê"
igual "manual2|$T/nao_existe|*||convidado,sem_pasta,todos" "$(dados manual2)" "sem valid users, read only = no, guest ok, pasta inexistente"
igual "manual3|$T/base|@dkt_fin|@dkt_dir|fora_padrao" "$(dados manual3)" "read list vence o read only = no; + vira grupo"
igual "manual4|$T/base|@dkt_fin,@dkt_ti||fora_padrao" "$(dados manual4)" "dois grupos com escrita"
nao_contem "global|" "$(p debkit_shr_dados)"; nao_contem "homes|" "$(p debkit_shr_dados)"; nao_contem "printers|" "$(p debkit_shr_dados)"
caso "listar: tabela e alertas"
saida=$(p debkit_shr_listar)
contem "Grupo (acesso total)" "$saida"; contem "financeiro" "$saida"; contem "dkt_fin" "$saida"; contem "qualquer usuário" "$saida"
contem "dkt_u1 (usuário), dkt_ti (somente leitura)" "$saida"; contem "dkt_fin, dkt_dir (somente leitura)" "$saida"
contem "manual1: fora do padrão do debkit" "$saida"; contem "manual4: fora do padrão do debkit" "$saida"
nao_contem "financeiro: fora do padrão" "$saida"; nao_contem "manual2: fora do padrão" "$saida"
contem "manual2: aberto para convidado" "$saida"; contem "manual2: a pasta $T/nao_existe não existe" "$saida"
contem "manual2: sem \"valid users\"" "$saida"
igual "" "$(grep '^    ! ' <<< "$saida" | grep -E 'total\).|senha.|Samba acessa.')" "cada alerta uma vez (nada repetido depois da mensagem)"
contem "7 compartilhamento(s)" "$saida"
sed -i "/^\[manual1\]/,\$d" "$AREIA/smb.conf"

# ════════════════════════════════════════════════════════════════════════════
# Telas
# ════════════════════════════════════════════════════════════════════════════
tela() { printf '%s\n' "$@" | p "${PRE:-} debkit_shr_tela_criar; echo RC=\$?"; }
idx_g() { p "debkit_samba_grupos_comuns" | grep -nx "$1" | cut -d: -f1; }
caso "tela: base já definida, pasta sugerida (Enter), um grupo, confirmação"
saida=$(tela "TI" "ti" "Equipe de TI" "" "$(idx_g dkt_ti)" s "")
contem "Nome inválido: 'TI'" "$saida"; contem "Compartilhamento: ti" "$saida"; contem "Descrição: Equipe de TI" "$saida"
contem "acesso total à pasta" "$saida"
contem "Pasta: $T/base/ti (será criada)" "$saida"; contem "Grupo (acesso total): dkt_ti" "$saida"
contem "Compartilhamento ti criado" "$saida"; verdadeiro "pasta criada" test -d "$T/base/ti"
igual "@dkt_ti" "$(param ti 'valid users')"
caso "tela: número inválido repete a pergunta; 'n' cancela; Enter no grupo cancela"
saida=$(tela "rh" "" "" "99" "x" "$(idx_g dkt_fin)" n "")
contem "Opção inválida" "$saida"; contem "Cancelado" "$saida"
contem "Cancelado" "$(tela "rh" "" "" "")"
verdadeiro "nada criado" bash -c "! testparm -s '$AREIA/smb.conf' 2>/dev/null | grep -qx '\[rh\]' && test ! -e '$T/base/rh'"
caso "tela: pasta que já tem arquivos avisa"
mkdir "$T/cheia"; touch "$T/cheia/x"
saida=$(tela "cheia" "" "$T/cheia" "$(idx_g dkt_fin)" n "")
contem "já existe; dono e permissões da pasta serão ajustados" "$saida"; contem "já tem arquivos" "$saida"
caso "tela: primeira vez pergunta a base e grava"
sed -i '/^SHARES_BASE=/d' "$AREIA/debkit.conf"
saida=$(tela "doc" "" "$T/base2" s "" "$(idx_g dkt_fin)" s "")
contem "Os compartilhamentos ficam numa base dentro de /mnt ou /srv" "$saida"
contem "Base dos compartilhamentos: $T/base2" "$saida"; contem "Compartilhamento doc criado ($T/base2/doc)" "$saida"
contem "SHARES_BASE=$T/base2" "$(cat "$AREIA/debkit.conf")"
caso "tela: sem grupo para dar acesso"
contem "crie um grupo antes" "$(PRE="debkit_samba_grupos_comuns() { :; };" tela "")"
caso "menu Samba > Compartilhamentos > 1) Listar"
saida=$(pty 0.6 "bash $DEBKIT" 1 3 1 "" 0 0 0)
contem "2) Criar compartilhamento" "$saida"; contem "6) Pastas pessoais" "$saida"; contem "Compartilhamentos do servidor" "$saida"
caso "inglês"
contem "Share en1 created" "$(p "DEBKIT_IDIOMA=en; DEBKIT_S_NOME=en1; DEBKIT_S_COMENTARIO=''; DEBKIT_S_PASTA='$T/base/en1'; DEBKIT_S_GRUPO=dkt_fin; debkit_shr_criar")"

limpar_tudo; trap - EXIT
caso "limpeza"
verdadeiro "nenhum usuário dkt_" bash -c "! getent passwd | grep -q '^dkt_'"
verdadeiro "pasta de teste apagada" test ! -e "$T"
real_intacto
resumo
