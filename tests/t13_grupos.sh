#!/usr/bin/env bash
# Testes de grupos (Fase 1, decisão de 19/10/2026): nome, criar, entrar e
# sair, remover, uso no smb.conf e arquivos do grupo no disco. Usuários e
# grupos dkt_* reais (removidos no fim); base do Samba e smb.conf da areia.
source "$(dirname "$0")/lib.sh"
caixa_de_areia

if getent passwd | cut -d: -f1 | grep -q '^dkt_'; then echo "  já existem usuários dkt_* - abortando"; exit 1; fi
if getent group | cut -d: -f1 | grep -v "^$GRUPO_TESTE\$" | grep -q '^dkt_'; then echo "  já existem grupos dkt_* - abortando"; exit 1; fi
limpar_usuarios() {
    local x
    for x in $(getent passwd | cut -d: -f1 | grep '^dkt_'); do
        pdbedit -s "$AREIA/smb.conf" -x -u "$x" >/dev/null 2>&1; userdel "$x" >/dev/null 2>&1
    done
    for x in $(getent group | cut -d: -f1 | grep '^dkt_'); do groupdel "$x" >/dev/null 2>&1; done
}
trap 'limpar_usuarios; rm -rf -- "${AREIA:?}"' EXIT

CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;
     debkit_samba_recarregar() { echo reload >> '$AREIA/reloads'; };"
p() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
membros() { getent group "$1" | cut -d: -f4; }
gid_de() { getent group "$1" | cut -d: -f3; }
LOG() { cat "$AREIA/debkit.log" 2>/dev/null; }

# ════════════════════════════════════════════════════════════════════════════
# Nome do grupo
# ════════════════════════════════════════════════════════════════════════════
useradd -M -s /usr/sbin/nologin -N -g users dkt_semgrupo     # usuário sem grupo pessoal
nome() { p "debkit_grupo_nome_problema '$1'; echo RC=\$?"; }
caso "nome: válidos"
for n in dkt_gp_rh dkt_vendas dkt_fin_2026 dkt_x9 "dkt_$(printf 'g%.0s' {1..28})"; do contem "RC=0" "$(nome "$n")" "$n"; done
caso "nome: formato e tamanho"
contem "Informe o nome do grupo" "$(nome '')"
contem "use de 2 a 32" "$(nome a)"; contem "use de 2 a 32" "$(nome "$(printf 'g%.0s' {1..33})")"
for n in Gp_rh gp-rh gp.rh "gp rh" gp__rh _gp gp_ 1gp ção gp_rç Dkt.G 'gp;rm' 'gp$x'; do
    contem "Nome inválido" "$(nome "$n")" "$n"
done
caso "nome: reservados, debkit*, já existe como grupo ou usuário"
for n in root users sudo wheel adm staff admin nobody; do contem "nome reservado" "$(nome "$n")" "$n"; done
for n in debkit debkit_rh debkitx; do contem "reservados para os grupos do próprio debkit" "$(nome "$n")" "$n"; done
contem "Já existe um grupo 'daemon'" "$(nome daemon)"
contem "Já existe um usuário 'dkt_semgrupo'" "$(nome dkt_semgrupo)"

# ════════════════════════════════════════════════════════════════════════════
# Criar
# ════════════════════════════════════════════════════════════════════════════
copiar_smb_conf "$AREIA/smb.conf"
preparar_areia
caso "nome: o grupo de proteção (já existe)"
contem "Já existe um grupo '$GRUPO_TESTE'" "$(nome "$GRUPO_TESTE")"
for u in dkt_a dkt_b dkt_c dkt_d; do useradd -M -U -s /usr/sbin/nologin "$u"; done
criar() { p "${3:-} DEBKIT_G_NOME='$1'; DEBKIT_G_MEMBROS=($2); debkit_grupo_criar; echo RC=\$?"; }

caso "criar: sem membros"
saida=$(criar dkt_g0 "")
contem "RC=0" "$saida"; contem "Grupo dkt_g0 criado" "$saida"
igual "" "$(membros dkt_g0)" "sem membros"
verdadeiro "GID comum" p "debkit_gid_comum $(gid_de dkt_g0)"
contem "grupo_criar nome=dkt_g0 gid=$(gid_de dkt_g0) membros= resultado=ok" "$(LOG)"
caso "criar: com membros (repetido não duplica)"
saida=$(criar dkt_g1 "dkt_b dkt_a dkt_b")
contem "RC=0" "$saida"; igual "dkt_a,dkt_b" "$(membros dkt_g1)" "membros"
igual "dkt_a,dkt_b" "$(getent gshadow dkt_g1 | cut -d: -f4)" "gshadow igual"
caso "criar: aparece nos grupos comuns (lista da criação de usuário)"
saida=$(p "debkit_samba_grupos_comuns")
contem "dkt_g0" "$saida"; contem "dkt_g1" "$saida"
nao_contem "dkt_a" "$saida" "grupo pessoal fora"; nao_contem "$GRUPO_TESTE" "$saida" "grupo de proteção fora"
caso "criar: recusas antes de mexer em qualquer coisa"
contem "Já existe um grupo 'dkt_g1'" "$(criar dkt_g1 "")"
contem "não é um usuário comum" "$(criar dkt_g2 "dkt_a daemon")"
contem "não é um usuário comum" "$(criar dkt_g2 "dkt_nao_existe")"
contem "não é um usuário comum" "$(criar dkt_g2 "root")"
contem "Nome inválido" "$(criar Dkt_G2 "")"
verdadeiro "nada criado" bash -c "! getent group dkt_g2 && ! getent group Dkt_G2"
caso "criar: groupadd falha - nada fica"
saida=$(criar dkt_g2 "dkt_a" "groupadd() { return 1; };")
contem "RC=1" "$saida"; contem "o groupadd falhou" "$saida"
verdadeiro "não existe" bash -c "! getent group dkt_g2"
contem "grupo_criar nome=dkt_g2 resultado=falha" "$(LOG)"
caso "criar: membros falham - o grupo criado é apagado"
saida=$(criar dkt_g2 "dkt_a" "gpasswd() { return 1; };")
contem "RC=1" "$saida"; contem "não foi possível definir os membros" "$saida"; contem "nada ficou pela metade" "$saida"
verdadeiro "não existe" bash -c "! getent group dkt_g2"
contem "grupo_criar nome=dkt_g2 resultado=desfeito" "$(LOG)"
caso "criar: GID fora da faixa comum - desfeito"
saida=$(criar dkt_g2 "" "groupadd() { command groupadd -r \"\$@\"; };")
contem "RC=1" "$saida"; contem "fora da faixa de grupos comuns" "$saida"
verdadeiro "não existe" bash -c "! getent group dkt_g2"
caso "criar: membros diferentes do pedido - desfeito"
saida=$(criar dkt_g2 "dkt_a" "gpasswd() { command gpasswd -M dkt_b \"\${@:3}\"; };")
contem "RC=1" "$saida"; contem "conferência final não bateu (membros)" "$saida"
verdadeiro "não existe" bash -c "! getent group dkt_g2"

# ════════════════════════════════════════════════════════════════════════════
# Entrar e sair
# ════════════════════════════════════════════════════════════════════════════
alterar() { p "${4:-} DEBKIT_G_ENTRAR=($2); DEBKIT_G_SAIR=($3); debkit_grupo_alterar_membros '$1'; echo RC=\$?"; }
gpasswd -a daemon dkt_g1 >/dev/null                # membro de sistema (posto à mão)
caso "entrar: um usuário"
saida=$(alterar dkt_g1 "dkt_c" "")
contem "RC=0" "$saida"; contem "Membros de dkt_g1 atualizados" "$saida"; nao_contem "sessão" "$saida" "ninguém conectado: nada a reconectar"
igual "dkt_a,dkt_b,daemon,dkt_c" "$(membros dkt_g1)" "dkt_c entrou, daemon mantido"
contem "grupo_membros grupo=dkt_g1 entraram=dkt_c sairam= resultado=ok" "$(LOG)"
caso "sair e entrar juntos"
contem "RC=0" "$(alterar dkt_g1 "dkt_d" "dkt_a dkt_b")"
igual "daemon,dkt_c,dkt_d" "$(membros dkt_g1)"
caso "sair: todos os comuns (o de sistema fica)"
contem "RC=0" "$(alterar dkt_g1 "" "dkt_c dkt_d")"
igual "daemon" "$(membros dkt_g1)"
caso "entrar num grupo vazio"
contem "RC=0" "$(alterar dkt_g0 "dkt_a" "")"; igual "dkt_a" "$(membros dkt_g0)"
caso "sair até ficar vazio"
contem "RC=0" "$(alterar dkt_g0 "" "dkt_a")"; igual "" "$(membros dkt_g0)"
caso "recusas: nada muda"
gpasswd -M dkt_a,dkt_b dkt_g1 >/dev/null
contem "já é membro" "$(alterar dkt_g1 "dkt_a" "")"
contem "não é membro" "$(alterar dkt_g1 "" "dkt_c")"
contem "adicionado e removido ao mesmo tempo" "$(alterar dkt_g1 "dkt_c" "dkt_c")"
contem "não é um usuário comum" "$(alterar dkt_g1 "daemon" "")"
contem "não é um usuário comum" "$(alterar dkt_g1 "" "daemon")" "membro de sistema não sai pelo debkit"
contem "não é um usuário comum" "$(alterar dkt_g1 "dkt_nao_existe" "")"
contem "Nenhum usuário para adicionar ou remover" "$(alterar dkt_g1 "" "")"
igual "dkt_a,dkt_b" "$(membros dkt_g1)" "membros iguais"
caso "recusas: grupos que o debkit não gerencia"
for g in sudo users daemon "$GRUPO_TESTE" dkt_a dkt_nao_existe; do
    contem "não é um grupo comum que o debkit gerencia" "$(alterar "$g" "dkt_c" "")" "$g"
done
nao_contem "dkt_c" "$(getent group sudo)"; nao_contem "dkt_c" "$(getent group "$GRUPO_TESTE")"
caso "grupo principal de um usuário: não entra nem sai"
groupadd dkt_gp; useradd -M -s /usr/sbin/nologin -g dkt_gp dkt_p
contem "tem dkt_gp como grupo principal" "$(alterar dkt_gp "dkt_p" "")"
contem "tem dkt_gp como grupo principal" "$(alterar dkt_gp "" "dkt_p")"
contem "RC=0" "$(alterar dkt_gp "dkt_a" "")" "outros entram normalmente"
caso "gpasswd falha: lista anterior mantida"
saida=$(alterar dkt_g1 "dkt_c" "" "gpasswd() { [ \"\$2\" == 'dkt_a,dkt_b' ] && command gpasswd \"\$@\"; [ \"\$2\" == 'dkt_a,dkt_b' ]; };")
contem "RC=1" "$saida"; contem "a lista anterior foi mantida" "$saida"
igual "dkt_a,dkt_b" "$(membros dkt_g1)"
contem "grupo_membros grupo=dkt_g1 resultado=falha" "$(LOG)"
caso "resultado diferente do pedido: volta a lista anterior"
saida=$(alterar dkt_g1 "dkt_c" "" "gpasswd() { if [ \"\$2\" == 'dkt_a,dkt_b' ]; then command gpasswd \"\$@\"; else command gpasswd -M dkt_d \"\${@:3}\"; fi; };")
contem "RC=1" "$saida"; contem "a lista anterior foi mantida" "$saida"
igual "dkt_a,dkt_b" "$(membros dkt_g1)"
caso "nem a lista anterior volta: avisa para conferir à mão"
saida=$(alterar dkt_g1 "dkt_c" "" "gpasswd() { command gpasswd -M dkt_d \"\${@:3}\"; };")
contem "RC=1" "$saida"; contem "confira à mão" "$saida"
gpasswd -M dkt_a,dkt_b dkt_g1 >/dev/null

caso "grupos citados no sudoers (%grupo, %#gid, sudoers.d): ficam de fora"
groupadd dkt_adm; groupadd dkt_adm2; groupadd dkt_adm3
mkdir -p "$AREIA/sudoers.d"
printf '%%sudo ALL=(ALL:ALL) ALL\n# %%dkt_adm3 ALL=(ALL) ALL\n%%dkt_adm ALL=(ALL) ALL\n' > "$AREIA/sudoers"
printf 'User_Alias ADM = joao, %%#%s\nADM ALL=(ALL) ALL\n' "$(gid_de dkt_adm2)" > "$AREIA/sudoers.d/x"
SUD="DEBKIT_ARQ_SUDOERS='$AREIA/sudoers'; DEBKIT_DIR_SUDOERS_D='$AREIA/sudoers.d';"
saida=$(p "$SUD debkit_samba_grupos_comuns")
verdadeiro "%grupo fora" bash -c "! grep -qx dkt_adm <<< '$saida'"
verdadeiro "%#gid (sudoers.d, alias) fora" bash -c "! grep -qx dkt_adm2 <<< '$saida'"
verdadeiro "comentado não conta" grep -qx dkt_adm3 <<< "$saida"
contem "não é um grupo comum que o debkit gerencia" "$(alterar dkt_adm "dkt_a" "" "$SUD")" "não recebe membros"
contem "não é um grupo comum que o debkit gerencia" "$(p "$SUD debkit_grupo_remover dkt_adm")" "não é removido"
igual "" "$(membros dkt_adm)"; verdadeiro "continua" getent group dkt_adm
verdadeiro "sem citação no sudoers real: gerenciado" grep -qx dkt_adm <<< "$(p "debkit_samba_grupos_comuns")"
groupdel dkt_adm; groupdel dkt_adm2; groupdel dkt_adm3
caso "nome citado no sudoers (grupo ainda não existe): recusado"
contem "é citado no sudoers" "$(p "$SUD debkit_grupo_nome_problema dkt_adm")"
contem "RC=1" "$(criar dkt_adm "" "$SUD")"; verdadeiro "não criado" bash -c "! getent group dkt_adm"

# ════════════════════════════════════════════════════════════════════════════
# Uso no smb.conf e arquivos no disco
# ════════════════════════════════════════════════════════════════════════════
mkdir -p "$AREIA/dados/rh/sub" "$AREIA/dados/vendas" "$AREIA/homes/dkt_a" "$AREIA/fora"
ln -s "$AREIA/fora" "$AREIA/link"
cat > "$AREIA/usos.conf" <<EOF
[global]
   server role = standalone server
   valid users = @dkt_g1
[a]
   path = $AREIA/dados/rh
   valid users = @dkt_g1, dkt_b
[b]
   path = $AREIA/dados/vendas/
   write list = dkt_c +dkt_g1
[c]
   path = $AREIA/dados
   force group = +dkt_g1
[d]
   path = $AREIA/link
   valid users = dkt_g1
[e]
   path = $AREIA/nao_existe
   valid users = @dkt_g10, @xdkt_g1
[f]
   path = $AREIA/dados/%U
   read list = "&dkt_g1"
[g]
   path = $AREIA/fora
   invalid users = &+dkt_g1
   admin users = @dkt_g0
[homes]
   valid users = %S, @dkt_g1
EOF
USOS="DEBKIT_SMB_CONF='$AREIA/usos.conf'; DEBKIT_HOMES_BASE='$AREIA/homes';"
caso "smb.conf: compartilhamentos que usam o grupo"
igual "$(printf '%s\n' a b c f g global homes)" "$(p "$USOS debkit_samba_grupo_usos dkt_g1")" "@ + & e force group; nome solto (usuário) e parecidos não contam"
igual "g" "$(p "$USOS debkit_samba_grupo_usos dkt_g0")"
igual "" "$(p "$USOS debkit_samba_grupo_usos dkt_g")" "nome parcial não conta"
caso "pastas de dados: base das homes e caminhos (sem repetir, sem %, link, inexistente)"
igual "$(printf '%s\n' "$AREIA/dados" "$AREIA/fora" "$AREIA/homes")" "$(p "$USOS debkit_samba_pastas_dados")"
caso "arquivos do grupo: conta e limita"
G1=$(gid_de dkt_g1)
touch "$AREIA/dados/rh/x" "$AREIA/dados/rh/sub/y" "$AREIA/homes/dkt_a/z" "$AREIA/fora/w"
chgrp dkt_g1 "$AREIA/dados/rh/x" "$AREIA/dados/rh/sub" "$AREIA/dados/rh/sub/y" "$AREIA/homes/dkt_a/z" "$AREIA/fora/w"
igual 5 "$(p "$USOS debkit_grupo_contar_arquivos $G1")" "5 itens (pastas também)"
igual 3 "$(p "$USOS DEBKIT_GRP_ARQUIVOS_MAX=3; debkit_grupo_contar_arquivos $G1")" "limitado"
igual 0 "$(p "$USOS debkit_grupo_contar_arquivos $(gid_de dkt_g0)")" "outro grupo: nenhum"
igual 4 "$(p "DEBKIT_SMB_CONF='$AREIA/usos.conf'; DEBKIT_HOMES_BASE=''; debkit_grupo_contar_arquivos $G1")" "sem HOMES_BASE"

# ════════════════════════════════════════════════════════════════════════════
# Remover
# ════════════════════════════════════════════════════════════════════════════
remover() { p "${2:-} debkit_grupo_remover '$1'; echo RC=\$?"; }
caso "remover: grupo principal de um usuário é recusado"
saida=$(remover dkt_gp)
contem "RC=1" "$saida"; contem "dkt_gp é o grupo principal de: dkt_p" "$saida"
verdadeiro "continua" getent group dkt_gp
caso "remover: grupos que o debkit não gerencia"
for g in sudo users daemon "$GRUPO_TESTE" dkt_a dkt_nao_existe; do
    contem "não é um grupo comum que o debkit gerencia" "$(remover "$g")" "$g"
done
verdadeiro "continuam" bash -c "getent group sudo && getent group '$GRUPO_TESTE' && getent group dkt_a"
caso "remover: groupdel falha"
saida=$(remover dkt_g0 "groupdel() { return 1; };")
contem "RC=1" "$saida"; contem "Não foi possível remover o grupo dkt_g0" "$saida"
verdadeiro "continua" getent group dkt_g0
caso "remover: com membros (os usuários continuam)"
G0=$(gid_de dkt_g1)
saida=$(remover dkt_g1)
contem "RC=0" "$saida"; contem "Grupo dkt_g1 removido" "$saida"
verdadeiro "não existe mais" bash -c "! getent group dkt_g1 && ! getent gshadow dkt_g1"
verdadeiro "usuários continuam" bash -c "getent passwd dkt_a && getent passwd dkt_b"
contem "grupo_remover nome=dkt_g1 gid=$G0 membros=dkt_a,dkt_b resultado=ok" "$(LOG)"

# ════════════════════════════════════════════════════════════════════════════
# Telas
# ════════════════════════════════════════════════════════════════════════════
tela() { local f="$1"; shift; printf '%s\n' "$@" | p "$f; echo RC=\$?"; }
idx_u() { p "debkit_samba_usuarios_comuns" | grep -nx "$1" | cut -d: -f1; }
idx_g() { p "debkit_samba_grupos_comuns" | grep -nx "$1" | cut -d: -f1; }

caso "tela criar: nome inválido, depois válido, membros e confirmação"
saida=$(tela debkit_samba_tela_criar_grupo "Gp-RH" "dkt_rh" "$(idx_u dkt_a),$(idx_u dkt_c)" "s" "")
contem "Nome inválido" "$saida"; contem "Grupo: dkt_rh" "$saida"; contem "Membros: dkt_a, dkt_c" "$saida"
contem "Grupo dkt_rh criado" "$saida"; igual "dkt_a,dkt_c" "$(membros dkt_rh)"
caso "tela criar: número inválido repete; sem membros"
saida=$(cd "$AREIA" && tela debkit_samba_tela_criar_grupo "dkt_rh2" "*" "999" "" "s" "")
contem "Escolha inválida: '*'" "$saida" "* não vira lista de arquivos"; contem "Escolha inválida: '999'" "$saida"; contem "Membros: (nenhum)" "$saida"; contem "RC=0" "$saida"
caso "tela criar: recusar a confirmação e Enter vazio cancelam"
saida=$(tela debkit_samba_tela_criar_grupo "dkt_rh3" "" "n" "")
contem "Cancelado" "$saida"; verdadeiro "não criado" bash -c "! getent group dkt_rh3"
contem "Cancelado" "$(tela debkit_samba_tela_criar_grupo "")"
contem "Cancelado" "$(tela debkit_samba_tela_criar_grupo)" "fim da entrada"

caso "tela membros: mostra membros e coloca"
saida=$(tela debkit_samba_tela_membros "$(idx_g dkt_rh)" 1 "$(p "debkit_samba_usuarios_comuns" | grep -vxE 'dkt_a|dkt_c' | grep -nx dkt_b | cut -d: -f1)" s "")
contem "Membros: dkt_a, dkt_c" "$saida"; contem "Membros de dkt_rh atualizados" "$saida"
igual "dkt_a,dkt_c,dkt_b" "$(membros dkt_rh)"
caso "tela membros: tira (lista só os membros)"
saida=$(tela debkit_samba_tela_membros "$(idx_g dkt_rh)" 2 "1 2" s "")
contem "Membros de dkt_rh atualizados" "$saida"; igual "dkt_c" "$(membros dkt_rh)"
caso "tela membros: principal e de sistema aparecem, mas não saem"
gpasswd -a daemon dkt_gp >/dev/null
saida=$(tela debkit_samba_tela_membros "$(idx_g dkt_gp)" 2 "")
contem "Grupo principal de: dkt_p (não podem ser removidos)" "$saida"; contem "Outros membros (de sistema; o debkit não mexe): daemon" "$saida"
nao_contem "2) daemon" "$saida"; contem "Cancelado" "$saida"
caso "tela membros: confirmação negada não muda nada"
saida=$(tela debkit_samba_tela_membros "$(idx_g dkt_rh)" 2 1 n "")
contem "Cancelado" "$saida"; igual "dkt_c" "$(membros dkt_rh)"

caso "tela remover: grupo usado no smb.conf é recusado antes de perguntar"
rm -rf -- "$AREIA/dados/rh" "$AREIA/homes" "$AREIA/fora/w"      # arquivos do dkt_g1 removido (GID pode voltar)
cat >> "$AREIA/smb.conf" <<EOF

[dkt_teste]
   path = $AREIA/dados
   valid users = @dkt_rh
EOF
saida=$(tela debkit_samba_tela_remover_grupo "$(idx_g dkt_rh)" s "")
contem "O grupo dkt_rh é usado no Samba ([dkt_teste])" "$saida"; nao_contem "Procurando arquivos" "$saida" "para antes dos avisos"
contem "RC=1" "$saida"; verdadeiro "continua" getent group dkt_rh
contem "é usado no Samba ([dkt_teste])" "$(remover dkt_rh)" "a função também recusa"
caso "tela remover: avisos (membros, arquivos) e 'n' cancela"
sed -i 's/^   valid users = @dkt_rh$/   valid users = @dkt_g0/' "$AREIA/smb.conf"   # a pasta continua num compartilhamento
chgrp dkt_rh "$AREIA/dados/vendas"
saida=$(tela debkit_samba_tela_remover_grupo "$(idx_g dkt_rh)" n "")
contem "1 membro(s) perdem o acesso dado por este grupo: dkt_c" "$saida"
contem "1 arquivo(s)/pasta(s) pertencem ao grupo" "$saida"
contem "Cancelado" "$saida"; verdadeiro "continua" getent group dkt_rh
caso "tela remover: 's' remove"
saida=$(tela debkit_samba_tela_remover_grupo "$(idx_g dkt_rh)" s "")
contem "Grupo dkt_rh removido" "$saida"; verdadeiro "removido" bash -c "! getent group dkt_rh"
caso "tela remover: grupo sem membros e sem arquivos"
saida=$(tela debkit_samba_tela_remover_grupo "$(idx_g dkt_rh2)" s "")
contem "O grupo não tem membros" "$saida"; contem "Nenhum arquivo do grupo" "$saida"; contem "removido" "$saida"
caso "tela remover: grupo principal é recusado antes de perguntar"
saida=$(tela debkit_samba_tela_remover_grupo "$(idx_g dkt_gp)" s "")
contem "é o grupo principal de: dkt_p" "$saida"; nao_contem "Procurando arquivos" "$saida" "para antes dos avisos"
verdadeiro "continua" getent group dkt_gp

caso "listar: grupos, GID, membros, principal e uso no Samba"
groupadd dkt_rh; gpasswd -M dkt_a,dkt_b dkt_rh >/dev/null
saida=$(p "debkit_samba_listar_grupos")
sed -i 's/^   valid users = @dkt_g0$/   valid users = @dkt_rh/' "$AREIA/smb.conf"
saida=$(p "debkit_samba_listar_grupos")
contem "dkt_rh" "$saida"; contem "dkt_a, dkt_b" "$saida"; contem "usado no Samba: [dkt_teste]" "$saida"
contem "dkt_p (principal)" "$saida"; nao_contem "$GRUPO_TESTE" "$saida"
caso "menu Samba > 2) Grupos"
saida=$(pty 0.6 "bash $DEBKIT" 1 2 1 "" 0 0 0)
contem "Samba: grupos" "$saida"; contem "Grupos do servidor" "$saida"
caso "inglês"
contem "Group dkt_en created." "$(p "DEBKIT_IDIOMA=en; DEBKIT_G_NOME=dkt_en; DEBKIT_G_MEMBROS=(); debkit_grupo_criar")"

# ════════════════════════════════════════════════════════════════════════════
# Reconexão automática (sessões abertas do Samba)
# ════════════════════════════════════════════════════════════════════════════
sessao() { sleep 60 >/dev/null 2>&1 & echo $!; }     # processo descartável no papel da sessão
FAKE() {  # FAKE <pid> <usuário>: smbstatus mostra a sessão; smbcontrol encerra (ou não, com $3=nao)
    echo "smbstatus() { printf 'PID     Username     Group\n-----\n%s  %s  %s  127.0.0.1\n' '$1' '$2' '$2'; };
          smbcontrol() { echo \"\$*\" >> '$AREIA/smbcontrol'; [ '${3:-sim}' == sim ] && kill \"\$3\"; return 0; };"
}
caso "reconectar: encerra só as sessões do usuário e confere"
P=$(sessao); : > "$AREIA/smbcontrol"
saida=$(p "$(FAKE "$P" dkt_a) debkit_samba_reconectar dkt_a dkt_b; echo RC=\$?")
contem "RC=0" "$saida"; contem "dkt_a: 1 sessão(ões) do Samba reconectada(s)" "$saida"; nao_contem "dkt_b:" "$saida" "sem sessão: nada"
verdadeiro "sessão encerrada" bash -c "! kill -0 $P"
contem "-s $AREIA/smb.conf $P shutdown" "$(cat "$AREIA/smbcontrol")"
contem "samba_reconectar usuario=dkt_a pids=$P resultado=ok" "$(LOG)"
caso "reconectar: sessão que não acaba (e não é smbd) - avisa, não mata outro processo"
P=$(sessao)
saida=$(p "$(FAKE "$P" dkt_a nao) debkit_samba_reconectar dkt_a; echo RC=\$?")
contem "RC=1" "$saida"; contem "não foi possível encerrar a sessão" "$saida"
verdadeiro "processo que não é smbd continua" kill -0 "$P"
contem "samba_reconectar usuario=dkt_a pids=$P resultado=falha" "$(LOG)"
kill "$P"
caso "entrar/sair: reconecta quem entrou ou saiu"
P=$(sessao)
saida=$(p "$(FAKE "$P" dkt_c) DEBKIT_G_ENTRAR=(dkt_c); DEBKIT_G_SAIR=(); debkit_grupo_alterar_membros dkt_rh; echo RC=\$?")
contem "RC=0" "$saida"; contem "dkt_c: 1 sessão(ões)" "$saida"; verdadeiro "encerrada" bash -c "! kill -0 $P"
P=$(sessao)
saida=$(p "$(FAKE "$P" dkt_b) DEBKIT_G_ENTRAR=(); DEBKIT_G_SAIR=(dkt_c); debkit_grupo_alterar_membros dkt_rh; echo RC=\$?")
contem "RC=0" "$saida"; nao_contem "sessão(ões)" "$saida" "dkt_b não foi mexido"; verdadeiro "sessão de outro continua" kill -0 "$P"
kill "$P"
caso "criar e remover: reconectam os membros"
P=$(sessao)
contem "dkt_a: 1 sessão(ões)" "$(p "$(FAKE "$P" dkt_a) DEBKIT_G_NOME=dkt_ses; DEBKIT_G_MEMBROS=(dkt_a); debkit_grupo_criar")"
P=$(sessao)
contem "dkt_a: 1 sessão(ões)" "$(p "$(FAKE "$P" dkt_a) debkit_grupo_remover dkt_ses")"
caso "telas: avisam antes da confirmação quem está conectado"
P=$(sessao)
saida=$(printf '%s\n' "$(idx_g dkt_rh)" 1 "$(p "debkit_samba_usuarios_comuns" | grep -vxE 'dkt_a|dkt_b' | grep -nx dkt_c | cut -d: -f1)" n "" | p "$(FAKE "$P" dkt_c) debkit_samba_tela_membros")
contem "Conectado(s) ao Samba agora: dkt_c" "$saida"; contem "Cancelado" "$saida"
verdadeiro "cancelado: sessão intacta" kill -0 "$P"
kill "$P"

limpar_usuarios
caso "limpeza"
verdadeiro "nenhum usuário dkt_" bash -c "! getent passwd | grep -q '^dkt_'"
verdadeiro "nenhum grupo dkt_ (fora o de teste)" bash -c "! getent group | cut -d: -f1 | grep -v '^$GRUPO_TESTE\$' | grep -q '^dkt_'"
nao_contem "dkt_" "$(getent group daemon sudo users)"
real_intacto
resumo
