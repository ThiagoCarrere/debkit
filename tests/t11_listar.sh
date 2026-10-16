#!/usr/bin/env bash
# Testes de listar usuários (Fase 1): quem aparece (só contas comuns), tipo
# (arquivos, servidor, admin, nologin), Samba (ativa, desativada, sem conta,
# só no Samba), pasta pessoal, grupos comuns e os alertas. Usuários/grupos
# dkt_* reais (removidos no fim); base do Samba da areia.
source "$(dirname "$0")/lib.sh"
caixa_de_areia

if getent passwd | cut -d: -f1 | grep -q '^dkt_'; then echo "  já existem usuários dkt_* - abortando"; exit 1; fi
limpar_usuarios() {
    local x
    for x in $(getent passwd | cut -d: -f1 | grep '^dkt_'); do
        pdbedit -s "$AREIA/smb.conf" -x -u "$x" >/dev/null 2>&1; userdel "$x" >/dev/null 2>&1
    done
    for x in $(pdbedit -s "$AREIA/smb.conf" -L 2>/dev/null | cut -d: -f1 | grep '^dkt_'); do pdbedit -s "$AREIA/smb.conf" -x -u "$x" >/dev/null 2>&1; done
    for x in $(getent group | cut -d: -f1 | grep '^dkt_'); do groupdel "$x" >/dev/null 2>&1; done
}
trap 'limpar_usuarios; rm -rf -- "${AREIA:?}"' EXIT

preparar_areia
CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;"
l() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
criar() {  # criar <nome> <tipo> <gecos> "<grupos>"
    l "DEBKIT_U_NOME='$1'; DEBKIT_U_TIPO='$2'; DEBKIT_U_GECOS='$3'; DEBKIT_U_GRUPOS=($4); DEBKIT_U_HOME=0;
       DEBKIT_U_SENHA='senha12'; DEBKIT_U_SENHA_LINUX='senha12'; debkit_usuario_criar" >/dev/null
}
samba_add() { printf 'senha12\nsenha12\n' | smbpasswd -c "$AREIA/smb.conf" -s -a "$1" >/dev/null; }

groupadd dkt_lg1; groupadd dkt_lg2; groupadd --system dkt_lsys
criar dkt_la arquivos "José Conceição - Vendas" "dkt_lg1 dkt_lg2"
criar dkt_ls servidor "Servidor Teste" "dkt_lg2"
criar dkt_ld arquivos "" ""
pdbedit -s "$AREIA/smb.conf" -c "[D]" -u dkt_ld >/dev/null              # conta Samba desativada
useradd -M -s /usr/sbin/nologin -c "Fulano de Tal,,," dkt_ln            # nologin fora do grupo de proteção
useradd -M -s /bin/bash dkt_lad; gpasswd -a dkt_lad sudo >/dev/null       # admin
samba_add dkt_lad
useradd -M -s /bin/bash dkt_lso                                           # só no Linux
mkdir -p "$AREIA/home_lh"; useradd -M -d "$AREIA/home_lh" -s /bin/bash dkt_lh; samba_add dkt_lh   # pasta existente
useradd -M -s /bin/bash dkt_lorfa; samba_add dkt_lorfa; userdel dkt_lorfa  # só no Samba
usermod -aG dkt_lsys dkt_la                                               # grupo de sistema: não aparece

dados=$(l debkit_samba_usuarios_dados)
linha() { grep "^$1|" <<< "$dados"; }

caso "dados: usuário de arquivos (nome completo, grupos comuns, Samba ativa)"
igual "dkt_la|José Conceição - Vendas|arquivos|ativa||dkt_lg1,dkt_lg2|" "$(linha dkt_la)"
caso "dados: usuário com acesso ao servidor"
igual "dkt_ls|Servidor Teste|servidor|ativa||dkt_lg2|" "$(linha dkt_ls)"
caso "dados: conta Samba desativada"
igual "dkt_ld||arquivos|desativada|||" "$(linha dkt_ld)"
caso "dados: nologin fora do grupo de proteção (alerta de túnel) e nome com ',,,'"
igual "dkt_ln|Fulano de Tal|nologin|nao|||tunel" "$(linha dkt_ln)"
caso "dados: admin (membro do sudo)"
igual "dkt_lad||admin|ativa|||" "$(linha dkt_lad)"
caso "dados: só no Linux"
igual "dkt_lso||servidor|nao|||so_linux" "$(linha dkt_lso)"
caso "dados: pasta pessoal existente aparece; /nonexistent não"
igual "dkt_lh||servidor|ativa|$AREIA/home_lh||" "$(linha dkt_lh)"
caso "dados: conta só no Samba (sem usuário Linux) vem no fim"
igual "dkt_lorfa||||||so_samba" "$(linha dkt_lorfa)"
igual "dkt_lorfa" "$(grep '|so_samba$' <<< "$dados" | tail -1 | cut -d'|' -f1)" "na parte das contas só no Samba"
igual "$(grep -n '|so_samba$' <<< "$dados" | head -1 | cut -d: -f1)" "$(( $(grep -vc '|so_samba$' <<< "$dados") + 1 ))" "depois de todos os usuários Linux"
caso "dados: quem NÃO aparece"
for x in root daemon nobody www-data; do nao_contem "$x|" "$dados" "$x (sistema)"; done
nao_contem "dkt_lsys" "$dados" "grupo de sistema fora da coluna de grupos"
nao_contem "$GRUPO_TESTE" "$dados" "grupo de proteção fora da coluna de grupos"
nao_contem ",dkt_la," ",$(linha dkt_la | cut -d'|' -f6)," "grupo pessoal fora"
caso "dados: ordem pelo login"
nomes=$(grep -v '|so_samba$' <<< "$dados" | cut -d'|' -f1)
igual "$(sort <<< "$nomes")" "$nomes"

# ── Tabela ───────────────────────────────────────────────────────────────────
saida=$(l debkit_samba_listar_usuarios)
caso "tabela: cabeçalho e linhas"
contem "Login" "$saida"; contem "Nome completo" "$saida"; contem "Pasta pessoal" "$saida"
contem "José Conceição - Vendas" "$saida"; contem "dkt_lg1, dkt_lg2" "$saida" "grupos separados por vírgula"
contem "desativada" "$saida"; contem "só Samba" "$saida"
caso "tabela: alertas"
contem "dkt_ln: shell sem login, mas fora do grupo de proteção $GRUPO_TESTE" "$saida"
contem "dkt_lso: sem conta no Samba" "$saida"
contem "dkt_lorfa: conta só no Samba" "$saida"
nao_contem "dkt_la:" "$saida" "sem alerta para quem está certo"
caso "tabela: total confere com os dados"
n_tot=$(grep -vc '|so_samba$' <<< "$dados"); n_arq=$(grep -c '^[^|]*|[^|]*|arquivos|' <<< "$dados")
n_srv=$(grep -c '^[^|]*|[^|]*|servidor|' <<< "$dados"); n_adm=$(grep -c '^[^|]*|[^|]*|admin|' <<< "$dados"); n_out=$(grep -c '^[^|]*|[^|]*|nologin|' <<< "$dados")
contem "$n_tot usuário(s): $n_arq de arquivos, $n_srv com acesso ao servidor, $n_adm admin, $n_out outro(s)." "$saida"
caso "tabela: colunas alinhadas mesmo com acentos"
pos_la=$(grep "  dkt_la " <<< "$saida" | sed 's/^  //'); pos_ls=$(grep "  dkt_ls " <<< "$saida" | sed 's/^  //')
p1=$(LC_ALL=C.UTF-8 bash -c 's="$1"; t="${s%%arquivos*}"; echo ${#t}' _ "$pos_la")
p2=$(LC_ALL=C.UTF-8 bash -c 's="$1"; t="${s%%servidor*}"; echo ${#t}' _ "$pos_ls")
igual "$p1" "$p2" "coluna Tipo na mesma posição (em caracteres)"
caso "debkit_pad: conta caracteres e corta com …"
igual "[José  ]" "[$(l "debkit_pad 'José' 6")]"
igual "[abcd…]" "[$(l "debkit_pad abcdefghij 5")]"
caso "tabela em inglês"
saida=$(l "DEBKIT_IDIOMA=en; debkit_samba_listar_usuarios")
contem "Full name" "$saida"; contem "files" "$saida"; contem "Samba only" "$saida"; contem "Attention:" "$saida"

caso "menu do Samba: 1) Listar usuários"
saida=$(pty 0.6 "bash $DEBKIT" 1 1 "" 0 0)
contem "Usuários do servidor" "$saida"; contem "dkt_la" "$saida"; contem "Atenção:" "$saida"

limpar_usuarios
caso "limpeza"
verdadeiro "nenhum usuário dkt_" bash -c "! getent passwd | grep -q '^dkt_'"
nao_contem "dkt_lad" "$(getent group sudo)" "fora do sudo"
real_intacto
resumo
