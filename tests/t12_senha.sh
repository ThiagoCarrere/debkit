#!/usr/bin/env bash
# Testes de trocar senha (Fase 1) e do item da preparação que desliga o
# "unix password sync" (decisão de 16/10/2026). Usuários/grupos dkt_*
# reais (removidos no fim); base do Samba e smb.conf da areia. A prova com
# login de verdade está em t07b_usuario_real.sh.
source "$(dirname "$0")/lib.sh"
caixa_de_areia

if getent passwd | cut -d: -f1 | grep -q '^dkt_'; then echo "  já existem usuários dkt_* - abortando"; exit 1; fi
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
PDB() { pdbedit -s "$AREIA/smb.conf" "$@" 2>/dev/null; }
efetivo() { testparm -s "$AREIA/smb.conf" 2>/dev/null; }

# ════════════════════════════════════════════════════════════════════════════
# unix password sync
# ════════════════════════════════════════════════════════════════════════════
SMB_SYNC='[global]\n   workgroup = TESTE\n   server role = standalone server\n# comentário sobre o sync\n   unix password sync = yes\n   pam password change = yes\n\n[dados]\n   path = /tmp\n'
smb_teste() { printf '%b' "$1" > "$AREIA/smb.conf"; isolar_smb_conf "$AREIA/smb.conf"; rm -rf "$AREIA/conf-bkp"; : > "$AREIA/reloads"; }
plano() { p "debkit_verificar_ambiente >/dev/null; printf '%s\n' \"\${DEBKIT_VERIF[@]}\" | grep '^samba'; debkit_montar_plano; echo \"PLANO=\${DEBKIT_PLANO[*]}\""; }

caso "sync ligado: avisa e entra no plano"
smb_teste "$SMB_SYNC"
saida=$(plano)
contem "\"unix password sync\" ligado" "$saida"; contem "samba_sem_sync" "$(grep '^PLANO=' <<< "$saida")"
contem "Desligar no $AREIA/smb.conf a sincronização" "$(p "debkit_verificar_ambiente >/dev/null; debkit_montar_plano; debkit_mostrar_plano")"
caso "sync: desligado pela edição segura (linha trocada no lugar, só isso muda)"
antes=$(efetivo)
saida=$(p "debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(samba_sem_sync); debkit_executar_plano; echo RC=\$?")
contem "RC=0" "$saida"
igual "No" "$(testparm -s --parameter-name='unix password sync' "$AREIA/smb.conf" 2>/dev/null)"
igual "$(grep -vxF $'\tunix password sync = Yes' <<< "$antes")" "$(efetivo)" "configuração em vigor: só a linha do sync saiu"
contem "   unix password sync = no" "$(sed -n '/comentário sobre o sync/{n;p}' "$AREIA/smb.conf")" "no mesmo lugar, depois do comentário"
igual 1 "$(grep -ci 'unix password sync' "$AREIA/smb.conf")" "uma linha só"
verdadeiro "backup em conf-bkp" test -n "$(find "$AREIA/conf-bkp" -name 'smb.conf.*')"
igual 1 "$(grep -c reload "$AREIA/reloads")" "Samba recarregado"
caso "sync: idempotente"
nao_contem "samba_sem_sync" "$(plano)"
caso "sync: linha repetida e maiúsculas"
smb_teste '[global]\n   passwd program = /usr/bin/passwd %u\n   Unix Password Sync = Yes\n\tunix password sync=yes\n[dados]\n   path = /tmp\n'
contem "RC=0" "$(p "debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(samba_sem_sync); debkit_executar_plano; echo RC=\$?")"
igual 1 "$(grep -ci 'unix password sync' "$AREIA/smb.conf")" "repetida saiu"
igual "No" "$(testparm -s --parameter-name='unix password sync' "$AREIA/smb.conf" 2>/dev/null)"
caso "sync: já desligado (padrão) - nada no plano"
smb_teste '[global]\n   workgroup = TESTE\n[dados]\n   path = /tmp\n'
nao_contem "samba_sem_sync" "$(plano)"; nao_contem "sync\" ligado" "$(plano)"
caso "sync: passo seguinte falha - o smb.conf volta"
smb_teste "$SMB_SYNC"; cp "$AREIA/smb.conf" "$AREIA/smb.antes"
saida=$(p "debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(samba_sem_sync grupo); groupadd() { return 1; }; debkit_executar_plano; echo RC=\$?")
contem "RC=1" "$saida"; contem "restaurado do backup" "$saida"
verdadeiro "smb.conf de volta" cmp -s "$AREIA/smb.antes" "$AREIA/smb.conf"
caso "sync: filtro com defeito - a conferência recusa"
smb_teste "$SMB_SYNC"; md5=$(md5sum < "$AREIA/smb.conf")
saida=$(p "debkit_samba_filtro_sem_sync() { sed 's/workgroup = TESTE/workgroup = OUTRO/; s/unix password sync = yes/unix password sync = no/'; }; debkit_acao_samba_sem_sync; echo RC=\$?")
contem "RC=1" "$saida"; contem "mais do que o pretendido" "$saida"; igual "$md5" "$(md5sum < "$AREIA/smb.conf")"

# ════════════════════════════════════════════════════════════════════════════
# Trocar senha
# ════════════════════════════════════════════════════════════════════════════
copiar_smb_conf "$AREIA/smb.conf"
preparar_areia
nt_hash() { PDB -w -u "$1" | cut -d: -f4; }
shadow() { getent shadow "$1" | cut -d: -f2; }
senha_linux_ok() { local h; h=$(shadow "$1"); [ "$(perl -e 'print crypt($ARGV[0], $ARGV[1])' "$2" "$h")" == "$h" ]; }
referencia() {
    useradd -M -s /usr/sbin/nologin dkt_ref 2>/dev/null
    printf '%s\n%s\n' "$1" "$1" | smbpasswd -c "$AREIA/smb.conf" -s -a dkt_ref >/dev/null
    nt_hash dkt_ref; PDB -x -u dkt_ref >/dev/null; userdel dkt_ref 2>/dev/null
}
criar() {
    p "DEBKIT_U_NOME='$1'; DEBKIT_U_TIPO='$2'; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=(); DEBKIT_U_HOME=0;
       DEBKIT_U_SENHA='Inicial1'; DEBKIT_U_SENHA_LINUX='Inicial1'; debkit_usuario_criar" >/dev/null
}
trocar() { p "${3:-} DEBKIT_U_SENHA='${4:-NovaSenha9}'; debkit_usuario_trocar_senha '$1' '$2'; echo RC=\$?"; }

criar dkt_sa arquivos; criar dkt_ss servidor
useradd -M -s /bin/bash dkt_sad; gpasswd -a dkt_sad sudo >/dev/null
printf 'Inicial1\nInicial1\n' | smbpasswd -c "$AREIA/smb.conf" -s -a dkt_sad >/dev/null
printf 'dkt_sad:Inicial1\n' | chpasswd
useradd -M -s /bin/bash dkt_slx; printf 'dkt_slx:Inicial1\n' | chpasswd   # servidor só no Linux
REF_NOVA=$(referencia NovaSenha9); REF_INI=$(referencia Inicial1)

caso "usuário de arquivos: troca a do Samba, a do Linux continua bloqueada"
saida=$(trocar dkt_sa samba)
contem "RC=0" "$saida"; contem "Senha de dkt_sa trocada (Samba)" "$saida"
igual "$REF_NOVA" "$(nt_hash dkt_sa)" "senha nova no Samba"
igual "!" "$(shadow dkt_sa)" "Linux bloqueada"
contem "senha_trocar nome=dkt_sa alvo=samba resultado=ok" "$(cat "$AREIA/debkit.log")"
nao_contem "NovaSenha9" "$(cat "$AREIA/debkit.log")" "senha nunca no log"
caso "usuário de arquivos: senha do Linux é recusada"
for a in linux ambas; do
    saida=$(trocar dkt_sa "$a"); contem "RC=1" "$saida"; contem "não tem acesso ao servidor" "$saida" "$a"
done
igual "!" "$(shadow dkt_sa)" "Linux continua bloqueada"

caso "servidor: só o Samba (o Linux não muda)"
sh_antes=$(shadow dkt_ss)
contem "RC=0" "$(trocar dkt_ss samba)"
igual "$REF_NOVA" "$(nt_hash dkt_ss)"; igual "$sh_antes" "$(shadow dkt_ss)" "Linux igual"
caso "servidor: só o Linux (o Samba não muda)"
contem "RC=0" "$(trocar dkt_ss linux "" "SoLinux77")"
verdadeiro "Linux nova" senha_linux_ok dkt_ss SoLinux77; igual "$REF_NOVA" "$(nt_hash dkt_ss)" "Samba igual"
caso "servidor: as duas"
contem "RC=0" "$(trocar dkt_ss ambas "" "Inicial1")"
verdadeiro "Linux" senha_linux_ok dkt_ss Inicial1; igual "$REF_INI" "$(nt_hash dkt_ss)" "Samba"
caso "servidor sem conta Samba: só o Linux"
contem "não tem conta no Samba" "$(trocar dkt_slx samba)"
contem "RC=0" "$(trocar dkt_slx linux)"; verdadeiro "Linux nova" senha_linux_ok dkt_slx NovaSenha9

caso "admin: Samba sim, Linux nunca"
sh_antes=$(shadow dkt_sad)
contem "RC=0" "$(trocar dkt_sad samba)"; igual "$REF_NOVA" "$(nt_hash dkt_sad)"
saida=$(trocar dkt_sad linux); contem "RC=1" "$saida"; contem "é administrador: troque a senha do Linux à mão" "$saida"
igual "$sh_antes" "$(shadow dkt_sad)" "Linux do admin intacta"
caso "recusas: usuário de sistema, inexistente, opção inválida, senha curta"
contem "não é um usuário comum" "$(trocar daemon samba)"; contem "não é um usuário comum" "$(trocar root samba)"
contem "não é um usuário comum" "$(trocar dkt_nao_existe samba)"
contem "Opção de senha inválida" "$(trocar dkt_ss tudo)"
contem "pelo menos 4" "$(trocar dkt_ss samba "" abc)"

caso "as duas: Samba falha - a do Linux volta a ser a anterior"
sh_antes=$(shadow dkt_ss); nt_antes=$(nt_hash dkt_ss)
saida=$(trocar dkt_ss ambas "smbpasswd() { return 1; };")
contem "RC=1" "$saida"; contem "o smbpasswd falhou" "$saida"; contem "voltou a ser a anterior" "$saida"
igual "$sh_antes" "$(shadow dkt_ss)" "shadow idêntico ao de antes"; igual "$nt_antes" "$(nt_hash dkt_ss)" "Samba igual"
caso "as duas: Linux falha - o Samba nem é tentado"
saida=$(trocar dkt_ss ambas "chpasswd() { cat >/dev/null; return 1; }; smbpasswd() { echo chamado >> '$AREIA/smb-chamado'; return 0; };")
contem "RC=1" "$saida"; contem "o chpasswd falhou" "$saida"
verdadeiro "smbpasswd não chamado" test ! -e "$AREIA/smb-chamado"
igual "$sh_antes" "$(shadow dkt_ss)"
caso "só o Samba e algo mexeu na senha do Linux (ex: sync): restaura e acusa"
saida=$(trocar dkt_sa samba "smbpasswd() { command smbpasswd \"\$@\" && printf 'dkt_sa:Vazou123\n' | command chpasswd; };")
contem "RC=1" "$saida"; contem "deixou de estar bloqueada" "$saida"
igual "!" "$(shadow dkt_sa)" "bloqueada de novo (\"!\" restaurado pelo chpasswd -e)"
caso "senha nunca na linha de comando"
: > "$AREIA/args"
ESPIA="chpasswd() { echo \"chpasswd \$*\" >> '$AREIA/args'; command chpasswd \"\$@\"; }; smbpasswd() { echo \"smbpasswd \$*\" >> '$AREIA/args'; command smbpasswd \"\$@\"; };"
contem "RC=0" "$(trocar dkt_ss ambas "$ESPIA" "Espia#Nova1")"
contem "smbpasswd -c $AREIA/smb.conf -s -- dkt_ss" "$(cat "$AREIA/args")"; nao_contem "Espia#" "$(cat "$AREIA/args")"

# ── Tela ─────────────────────────────────────────────────────────────────────
tela() { printf '%s\n' "$@" | p "debkit_samba_tela_trocar_senha; echo RC=\$?"; }
idx() { p "debkit_samba_usuarios_dados" | awk -F'|' '$3 != "" && ($4 != "nao" || $3 == "servidor") {print $1}' | grep -nx "$1" | cut -d: -f1; }
caso "tela: usuário de arquivos (só Samba, sem perguntar qual)"
saida=$(tela "$(idx dkt_sa)" "TelaSenha1" "TelaSenha1" "")
contem "só a senha do Samba é trocada" "$saida"; nao_contem "Qual senha?" "$saida"; contem "Senha de dkt_sa trocada (Samba)" "$saida"
caso "tela: servidor pergunta qual (Enter = as duas)"
saida=$(tela "$(idx dkt_ss)" "" "TelaSenha2" "TelaSenha2" "")
contem "Qual senha?" "$saida"; contem "Senha de dkt_ss trocada (Samba e Linux)" "$saida"
verdadeiro "Linux" senha_linux_ok dkt_ss TelaSenha2
caso "tela: servidor só no Linux não pergunta qual"
saida=$(tela "$(idx dkt_slx)" "TelaSenha3" "TelaSenha3" "")
nao_contem "Qual senha?" "$saida"; contem "trocada (Linux)" "$saida"
caso "tela: lista não tem quem não tem senha a trocar (só Linux e de arquivos) nem só-Samba"
useradd -M -s /usr/sbin/nologin -G "$GRUPO_TESTE" dkt_sem
saida=$(tela "")
nao_contem "dkt_sem" "$saida"; contem "dkt_sa" "$saida"; contem "Cancelado" "$saida"
caso "tela: senhas diferentes e fim da entrada cancelam sem trocar"
nt_antes=$(nt_hash dkt_sa)
saida=$(tela "$(idx dkt_sa)" "Uma12345" "Outra1234")
contem "As senhas não conferem" "$saida"; contem "Cancelado" "$saida"; igual "$nt_antes" "$(nt_hash dkt_sa)"
caso "menu do Samba: 3) Trocar senha"
contem "Trocar senha" "$(pty 0.6 "bash $DEBKIT" 1 3 "" 0 0)"

limpar_usuarios
caso "limpeza"
verdadeiro "nenhum usuário dkt_" bash -c "! getent passwd | grep -q '^dkt_'"
nao_contem "dkt_sad" "$(getent group sudo)"
real_intacto
resumo
