#!/usr/bin/env bash
# Testes de "verificar e corrigir contas" (Fase 1, seção 3.4 e regras
# 3.1/3.2): conta só no Samba, só no Linux, shell sem login fora do grupo
# de proteção e usuário de arquivos com senha do Linux utilizável.
# Usuários/grupos dkt_* reais (removidos no fim); base do Samba e smb.conf
# da areia. Nas telas, só os itens dkt_* (os usuários reais do servidor
# também aparecem na areia, cujo grupo de proteção é outro).
source "$(dirname "$0")/lib.sh"
caixa_de_areia

if getent passwd | cut -d: -f1 | grep -q '^dkt_'; then echo "  já existem usuários dkt_* - abortando"; exit 1; fi
limpar_usuarios() {   # limpar_usuarios [manter_grupo_teste]
    local x
    for x in $(getent passwd | cut -d: -f1 | grep '^dkt_'); do userdel "$x" >/dev/null 2>&1; done
    for x in $(pdbedit -s "$AREIA/smb.conf" -L 2>/dev/null | cut -d: -f1 | grep '^dkt_'); do pdbedit -s "$AREIA/smb.conf" -x -u "$x" >/dev/null 2>&1; done
    for x in $(getent group | cut -d: -f1 | grep '^dkt_'); do
        [ -n "${1:-}" ] && [ "$x" == "$GRUPO_TESTE" ] && continue
        groupdel "$x" >/dev/null 2>&1
    done
}
trap 'limpar_usuarios; rm -rf -- "${AREIA:?}"' EXIT

copiar_smb_conf "$AREIA/smb.conf"
preparar_areia
CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;
     debkit_samba_recarregar() { echo reload >> '$AREIA/reloads'; };"
p() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
PDB() { pdbedit -s "$AREIA/smb.conf" "$@" 2>/dev/null; }
SMBPW() { printf '%s\n%s\n' "$2" "$2" | smbpasswd -c "$AREIA/smb.conf" -s -a "$1" >/dev/null; }
LOG() { cat "$AREIA/debkit.log" 2>/dev/null; }
nt_hash() { PDB -w -u "$1" | cut -d: -f4; }
shadow() { getent shadow "$1" | cut -d: -f2; }
itens() { p "debkit_samba_inconsistencias" | grep '|dkt_'; }
criar() {
    p "DEBKIT_U_NOME='$1'; DEBKIT_U_TIPO='$2'; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=(); DEBKIT_U_HOME=0;
       DEBKIT_U_SENHA='Inicial1'; DEBKIT_U_SENHA_LINUX='Inicial1'; debkit_usuario_criar" >/dev/null
}
corrigir() { p "${3:-} DEBKIT_U_SENHA='${4:-NovaSamba1}'; debkit_consist_$1 '$2'; echo RC=\$?"; }

# Cenário: uma conta de cada tipo de problema, e duas certas
criar dkt_ok_arq arquivos; criar dkt_ok_srv servidor
useradd -M -s /usr/sbin/nologin dkt_orfao; SMBPW dkt_orfao Orfao123; userdel dkt_orfao   # só no Samba
useradd -M -s /bin/bash dkt_semsmb; printf 'dkt_semsmb:Linux1234\n' | chpasswd            # servidor, só no Linux
useradd -M -s /usr/sbin/nologin -G "$GRUPO_TESTE" dkt_arqsem                               # arquivos, só no Linux
useradd -M -s /usr/sbin/nologin dkt_tunel; SMBPW dkt_tunel Tunel123                       # fora do grupo de proteção
criar dkt_senha arquivos; printf 'dkt_senha:Vazou123\n' | chpasswd                       # senha Linux utilizável

caso "detecção: um item por problema; contas certas não aparecem"
saida=$(itens)
contem "so_samba|dkt_orfao" "$saida"; contem "so_linux|dkt_semsmb" "$saida"; contem "so_linux|dkt_arqsem" "$saida"
contem "tunel|dkt_tunel" "$saida"; contem "senha_linux|dkt_senha" "$saida"
nao_contem "dkt_ok_" "$saida" "contas certas fora"
igual 5 "$(wc -l <<< "$saida")" "5 itens"

# ════════════════════════════════════════════════════════════════════════════
# Correções
# ════════════════════════════════════════════════════════════════════════════
caso "só no Samba: apaga a conta órfã"
saida=$(corrigir so_samba dkt_orfao)
contem "RC=0" "$saida"; contem "Conta Samba de dkt_orfao apagada" "$saida"
verdadeiro "conta apagada" bash -c "! pdbedit -s '$AREIA/smb.conf' -u dkt_orfao"
contem "consistencia acao=so_samba nome=dkt_orfao resultado=ok" "$(LOG)"
caso "só no Samba: com usuário no Linux de novo, não apaga"
useradd -M -s /usr/sbin/nologin dkt_volta; SMBPW dkt_volta Volta123
contem "a situação mudou" "$(corrigir so_samba dkt_volta)"; verdadeiro "conta intacta" PDB -u dkt_volta

caso "só no Linux (servidor): cria a conta Samba; a senha do Linux não muda"
sh_antes=$(shadow dkt_semsmb)
saida=$(corrigir so_linux dkt_semsmb)
contem "RC=0" "$saida"; contem "Conta Samba de dkt_semsmb criada" "$saida"
verdadeiro "conta criada" PDB -u dkt_semsmb; igual "$sh_antes" "$(shadow dkt_semsmb)" "Linux igual"
nao_contem "NovaSamba1" "$(LOG)" "senha nunca no log"
caso "só no Linux (arquivos): a senha do Linux continua bloqueada"
contem "RC=0" "$(corrigir so_linux dkt_arqsem)"; igual "!" "$(shadow dkt_arqsem)"
caso "só no Linux: se a senha do Linux mudar junto (ex: sync), volta"
useradd -M -s /usr/sbin/nologin -G "$GRUPO_TESTE" dkt_sync
saida=$(corrigir so_linux dkt_sync "smbpasswd() { command smbpasswd \"\$@\" && printf 'dkt_sync:Vazou999\n' | command chpasswd; };")
contem "RC=0" "$saida"; contem "voltou a ser a anterior" "$saida"; igual "!" "$(shadow dkt_sync)"
caso "só no Linux: senha curta, já tem conta, sistema"
useradd -M -s /bin/bash dkt_curta
contem "pelo menos 4" "$(corrigir so_linux dkt_curta "" abc)"
contem "a situação mudou" "$(corrigir so_linux dkt_semsmb)" "já tem conta"
contem "a situação mudou" "$(corrigir so_linux daemon)"
caso "só no Linux: smbpasswd falha"
useradd -M -s /bin/bash dkt_smbfalha
saida=$(corrigir so_linux dkt_smbfalha "smbpasswd() { cat >/dev/null; return 1; };")
contem "RC=1" "$saida"; contem "não foi possível criar a conta no Samba" "$saida"
verdadeiro "sem conta" bash -c "! pdbedit -s '$AREIA/smb.conf' -u dkt_smbfalha"

caso "túnel: põe no grupo de proteção (vira usuário de arquivos)"
saida=$(corrigir tunel dkt_tunel)
contem "RC=0" "$saida"; contem "agora está no grupo de proteção $GRUPO_TESTE" "$saida"
contem "dkt_tunel" "$(getent group "$GRUPO_TESTE")"; igual "arquivos" "$(p "debkit_usuario_tipo dkt_tunel")"
caso "túnel: servidor (bash) e quem já está no grupo não são mexidos"
contem "a situação mudou" "$(corrigir tunel dkt_ok_srv)"; nao_contem "dkt_ok_srv" "$(getent group "$GRUPO_TESTE")"
contem "a situação mudou" "$(corrigir tunel dkt_tunel)"
caso "túnel: gpasswd falha"
useradd -M -s /usr/sbin/nologin dkt_tunel2
contem "não entrou no grupo" "$(corrigir tunel dkt_tunel2 "gpasswd() { return 1; };")"

caso "senha do Linux: bloqueia (a do Samba não muda)"
nt_antes=$(nt_hash dkt_senha)
saida=$(corrigir senha_linux dkt_senha)
contem "RC=0" "$saida"; contem "Senha do Linux de dkt_senha bloqueada" "$saida"
igual "!" "$(shadow dkt_senha)"; igual "$nt_antes" "$(nt_hash dkt_senha)" "Samba igual"
caso "senha do Linux: só usuário de arquivos (servidor nunca)"
sh_antes=$(shadow dkt_ok_srv)
contem "a situação mudou" "$(corrigir senha_linux dkt_ok_srv)"; igual "$sh_antes" "$(shadow dkt_ok_srv)" "senha do servidor intacta"
caso "senha do Linux: usermod falha"
printf 'dkt_senha:Vazou123\n' | chpasswd
contem "a senha não ficou bloqueada" "$(corrigir senha_linux dkt_senha "usermod() { return 1; };")"
contem "consistencia acao=senha_linux nome=dkt_senha resultado=falha" "$(LOG)"

# ════════════════════════════════════════════════════════════════════════════
# Tela (só os itens dkt_*)
# ════════════════════════════════════════════════════════════════════════════
SO_DKT="eval \"\$(declare -f debkit_samba_inconsistencias | sed '1s/debkit_samba_inconsistencias/_inc_todas/')\";
        debkit_samba_inconsistencias() { _inc_todas | grep '|dkt_'; };"
tela() { printf '%s\n' "$@" | p "$SO_DKT debkit_samba_tela_consistencia; echo RC=\$?"; }
limpar_usuarios manter_grupo_teste; criar dkt_ok_arq arquivos
useradd -M -s /usr/sbin/nologin dkt_t1; SMBPW dkt_t1 Tela1234          # túnel
useradd -M -s /bin/bash dkt_t2                                           # só no Linux
caso "tela: lista tudo e corrige um a um (s / n)"
saida=$(tela n s "TelaSenha1" "TelaSenha1" "")
contem "2 item(ns) fora do padrão" "$saida"
contem "dkt_t1: shell sem login, mas fora do grupo de proteção" "$saida"; contem "dkt_t2: usuário no Linux sem conta no Samba" "$saida"
contem "Mantido como está" "$saida"; contem "Conta Samba de dkt_t2 criada" "$saida"; contem "1 de 2 item(ns) corrigido(s)" "$saida"
nao_contem "dkt_t1" "$(getent group "$GRUPO_TESTE")" "o 'n' não mexeu"; verdadeiro "conta criada" PDB -u dkt_t2
caso "tela: depois de corrigir, tudo certo"
saida=$(tela s "")
contem "1 de 1 item(ns) corrigido(s)" "$saida"
contem "Tudo certo" "$(tela "")"
caso "tela: senha cancelada pula o item"
useradd -M -s /bin/bash dkt_t3
saida=$(tela s "abc")
contem "Mantido como está" "$saida"; verdadeiro "sem conta" bash -c "! pdbedit -s '$AREIA/smb.conf' -u dkt_t3"
caso "menu Samba > Usuários > 6"
contem "6) Verificar e corrigir contas (Linux x Samba)" "$(pty 0.6 "bash $DEBKIT" 1 1 0 0 0)"
caso "inglês"
contem "Samba account of dkt_t3 created." "$(p "DEBKIT_IDIOMA=en; DEBKIT_U_SENHA=Senha1234; debkit_consist_so_linux dkt_t3")"

limpar_usuarios
caso "limpeza"
verdadeiro "nenhum usuário dkt_" bash -c "! getent passwd | grep -q '^dkt_'"
verdadeiro "nenhuma conta Samba dkt_ na areia" bash -c "! pdbedit -s '$AREIA/smb.conf' -L 2>/dev/null | grep -q '^dkt_'"
real_intacto
resumo
