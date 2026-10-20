#!/usr/bin/env bash
# Testes da tarefa 1.1 - criar usuário (sem pasta pessoal: tarefa 1.1b).
# Os usuários e grupos Linux de teste (dkt_*) são REAIS (não há como isolar
# o /etc/passwd) e removidos no fim; a base de senhas do Samba é a do sandbox
# (copiar_smb_conf), nunca a real. A prova com login de verdade no Samba e
# no SSH fica em t07b_usuario_real.sh (só com DEBKIT_TESTE_REAL=1).
source "$(dirname "$0")/lib.sh"
sandbox

if getent passwd | cut -d: -f1 | grep -q '^dkt_' || getent group | cut -d: -f1 | grep -qE '^dkt_(g|arq|srv|x)'; then
    echo "  já existem usuários/grupos dkt_* - abortando"; exit 1
fi

# Remove tudo o que os testes criaram (contas Samba do sandbox, usuários e
# grupos dkt_*) e depois o sandbox
limpar_usuarios() {
    local x
    for x in $(getent passwd | cut -d: -f1 | grep '^dkt_'); do
        pdbedit -s "$SANDBOX/smb.conf" -x -u "$x" >/dev/null 2>&1
        userdel "$x" >/dev/null 2>&1
    done
    for x in $(getent group | cut -d: -f1 | grep '^dkt_'); do groupdel "$x" >/dev/null 2>&1; done
}
trap 'limpar_usuarios; rm -rf -- "${SANDBOX:?}"' EXIT

preparar_sandbox
CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;"
u() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
PDB() { pdbedit -s "$SANDBOX/smb.conf" "$@" 2>/dev/null; }
status_linux() { passwd -S "$1" 2>/dev/null | awk '{print $2}'; }
# NT hash da conta (Samba) - comparado com o de uma conta de referência
nt_hash() { PDB -w -u "$1" | cut -d: -f4; }
# A senha do Linux (shadow) confere? (crypt da libc, via perl)
senha_linux_ok() {
    local h; h=$(getent shadow "$1" | cut -d: -f2)
    [ "$(perl -e 'print crypt($ARGV[0], $ARGV[1])' "$2" "$h")" == "$h" ]
}
# criar <nome> <tipo> <gecos> "<grupos separados por espaço>" <senha> [senha_linux] [código antes]
criar() {
    u "${7:-} DEBKIT_U_NOME='$1'; DEBKIT_U_TIPO='$2'; DEBKIT_U_GECOS='$3'; DEBKIT_U_GRUPOS=($4);
       DEBKIT_U_SENHA='$5'; DEBKIT_U_SENHA_LINUX='${6:-}'; debkit_usuario_criar; echo RC=\$?"
}
# Conta Samba de referência (mesma senha = mesmo NT hash)
referencia() {
    useradd -M -s /usr/sbin/nologin dkt_ref 2>/dev/null
    printf '%s\n%s\n' "$1" "$1" | smbpasswd -c "$SANDBOX/smb.conf" -s -a dkt_ref >/dev/null
    nt_hash dkt_ref
    pdbedit -s "$SANDBOX/smb.conf" -x -u dkt_ref >/dev/null 2>&1; userdel dkt_ref 2>/dev/null
}

groupadd dkt_g1; groupadd dkt_g2; groupadd --system dkt_gsys

# ════════════════════════════════════════════════════════════════════════════
# Regras do nome de login
# ════════════════════════════════════════════════════════════════════════════
np() { u "debkit_usuario_nome_problema '$1'; echo \" RC=\$?\""; }
caso "nome: válidos"
for n in maria maria_souza joao2 ab a1_b2 dkt_x_y_z abcdefghij_abcdefghij_abcdefghij; do
    contem "RC=0" "$(np "$n")" "$n"
done
caso "nome: formato inválido (maiúscula, acento, ponto, hífen, espaço, _ mal colocado, número no início)"
for n in Maria maria.souza maria-souza "maria souza" joão _maria maria_ maria__souza 2maria 'maria;id' 'a$b' 'maria/x'; do
    saida=$(np "$n"); contem "RC=1" "$saida" "[$n]"; contem "ex: maria_souza" "$saida" "[$n] mostra o exemplo"
done
caso "nome: tamanho"
contem "tem 1 caractere(s): use de 2 a 32" "$(np a)"
contem "tem 33 caractere(s)" "$(np abcdefghij_abcdefghij_abcdefghijk)"
contem "Informe o nome de login" "$(np '')"
caso "nome: reservados"
for n in root admin administrator administrador guest convidado nobody; do contem "é um nome reservado" "$(np "$n")" "$n"; done
caso "nome: já existe (usuário, grupo, conta Samba órfã)"
contem "Já existe um usuário 'daemon'" "$(np daemon)"
contem "Já existe um grupo 'dkt_g1'" "$(np dkt_g1)"
useradd -M -s /usr/sbin/nologin dkt_orfa; printf 'x1234\nx1234\n' | smbpasswd -c "$SANDBOX/smb.conf" -s -a dkt_orfa >/dev/null; userdel dkt_orfa
contem "Já existe uma conta Samba 'dkt_orfa' sem usuário no Linux" "$(np dkt_orfa)"
PDB -x -u dkt_orfa >/dev/null

# ════════════════════════════════════════════════════════════════════════════
# Nome completo e sugestão de login
# ════════════════════════════════════════════════════════════════════════════
gp() { bash -c "source '$DEBKIT'; $CFG debkit_usuario_gecos_problema \"\$1\"; echo \" RC=\$?\"" _ "$1" 2>&1; }
caso "nome completo: válidos (com acentos)"
for g in "" "Maria Souza - Financeiro" "José da Conceição" "Ana (estagiária) 2026"; do contem "RC=0" "$(gp "$g")" "[$g]"; done
caso "nome completo: inválidos"
for g in "a:b" "a,b" "a=b" 'a\b' $'a\tb' $'a\nb'; do contem "RC=1" "$(gp "$g")" "[${g//$'\n'/\\n}]"; done
contem "muito longo" "$(gp "$(printf 'x%.0s' {1..101})")"
sg() { bash -c "source '$DEBKIT'; $CFG debkit_usuario_sugerir \"\$1\"" _ "$1" 2>&1; }
caso "sugestão de login a partir do nome completo"
igual "maria_avila" "$(sg "Maria Conceição Ávila - Financeiro")" "primeiro e último nome, sem acento"
igual "joao" "$(sg "  João  ")" "um nome só"
igual "nunez_oconnor" "$(sg "Ñúñez O'Connor")" "apóstrofo e ñ"
igual "" "$(sg "123 Silva")" "começando por número: sem sugestão"
igual "" "$(sg "")" "vazio: sem sugestão"
igual "" "$(sg "Daemon")" "nome que já existe: sem sugestão"

# ════════════════════════════════════════════════════════════════════════════
# Grupos comuns
# ════════════════════════════════════════════════════════════════════════════
caso "grupos comuns: só GID na faixa, sem pessoais e sem o de proteção"
saida=$(u "debkit_samba_grupos_comuns")
contem "dkt_g1" "$saida"; contem "dkt_g2" "$saida"
nao_contem "dkt_gsys" "$saida" "grupo de sistema fora"
nao_contem "$GRUPO_TESTE" "$saida" "grupo de proteção fora"
nao_contem "root" "$saida"
for x in $(getent passwd | awk -F: '$3 >= 1000 && $3 <= 60000 {print $1}'); do
    g=$(getent group "$x" | cut -d: -f1)
    [ -n "$g" ] && nao_contem "$x"$'\n' "$saida"$'\n' "grupo pessoal $x fora"
done

# ════════════════════════════════════════════════════════════════════════════
# Criar: usuário de arquivos
# ════════════════════════════════════════════════════════════════════════════
caso "criar usuário de arquivos"
ref=$(referencia "Arq#Senha 1")
saida=$(criar dkt_arq arquivos "Maria Souza - Financeiro" "dkt_g1 dkt_g2" "Arq#Senha 1")
contem "RC=0" "$saida"; contem "Usuário dkt_arq criado" "$saida"
IFS=: read -r _ _ uid gid gecos home shell < <(getent passwd dkt_arq)
verdadeiro "UID $uid na faixa comum" test "$uid" -ge 1000 -a "$uid" -le 60000
igual "Maria Souza - Financeiro" "$gecos" "nome completo"
igual "/nonexistent /usr/sbin/nologin" "$home $shell" "sem home, shell nologin"
verdadeiro "nenhuma pasta criada" test ! -e /nonexistent
igual "dkt_arq" "$(getent group "$gid" | cut -d: -f1)" "grupo pessoal com o mesmo nome"
grupos=$(id -nG dkt_arq | tr ' ' '\n' | sort | tr '\n' ' ')
igual "$(printf '%s\n' dkt_arq dkt_g1 dkt_g2 "$GRUPO_TESTE" | sort | tr '\n' ' ')" "$grupos" "grupos: pessoal, escolhidos e o de proteção SSH"
igual "L" "$(status_linux dkt_arq)" "senha do Linux bloqueada"
igual "!" "$(getent shadow dkt_arq | cut -d: -f2)" "nenhuma senha Linux utilizável"
contem "[U" "$(PDB -u dkt_arq -v | grep 'Account Flags')" "conta Samba ativa"
igual "$ref" "$(nt_hash dkt_arq)" "senha do Samba é a informada"
verdadeiro "nada na base Samba REAL" bash -c '! pdbedit -L 2>/dev/null | grep -q "^dkt_"'
log=$(cat "$SANDBOX/debkit.log")
contem "usuario_criar nome=dkt_arq tipo=arquivos uid=$uid grupos=dkt_g1,dkt_g2 home=/nonexistent resultado=ok" "$log" "auditoria"
nao_contem "Arq#Senha" "$log" "senha nunca no log"

caso "criar usuário de arquivos sem grupos e sem nome completo"
contem "RC=0" "$(criar dkt_arq2 arquivos "" "" "senha12")"
igual "$(printf '%s\n' dkt_arq2 "$GRUPO_TESTE" | sort | tr '\n' ' ')" "$(id -nG dkt_arq2 | tr ' ' '\n' | sort | tr '\n' ' ')" "só pessoal e proteção"
igual "" "$(getent passwd dkt_arq2 | cut -d: -f5)" "nome completo vazio"

caso "criar: nome já usado agora é recusado (nada muda)"
antes=$(getent passwd dkt_arq)
saida=$(criar dkt_arq arquivos "" "" "senha12")
contem "RC=1" "$saida"; contem "Já existe um usuário 'dkt_arq'" "$saida"
igual "$antes" "$(getent passwd dkt_arq)" "o existente não foi tocado"

# ════════════════════════════════════════════════════════════════════════════
# Criar: usuário com acesso ao servidor
# ════════════════════════════════════════════════════════════════════════════
caso "criar usuário com acesso ao servidor (mesma senha)"
ref=$(referencia "Srv%Senha2")
contem "RC=0" "$(criar dkt_srv servidor "Admin Junior" "dkt_g1" "Srv%Senha2" "Srv%Senha2")"
igual "/bin/bash" "$(getent passwd dkt_srv | cut -d: -f7)" "shell bash"
nao_contem "$GRUPO_TESTE" "$(id -nG dkt_srv)" "fora do grupo de proteção SSH"
igual "P" "$(status_linux dkt_srv)" "senha do Linux definida"
verdadeiro "senha do Linux é a informada" senha_linux_ok dkt_srv "Srv%Senha2"
igual "$ref" "$(nt_hash dkt_srv)" "senha do Samba é a informada"
caso "criar usuário com acesso ao servidor (senhas diferentes)"
ref=$(referencia "SambaPw9")
contem "RC=0" "$(criar dkt_srv2 servidor "" "" "SambaPw9" "Linux:Pw 8")"
verdadeiro "senha do Linux (com ':' e espaço)" senha_linux_ok dkt_srv2 "Linux:Pw 8"
verdadeiro "senha do Linux NÃO é a do Samba" bash -c "! perl -e 'exit(crypt(\$ARGV[0],\$ARGV[1]) eq \$ARGV[1] ? 0 : 1)' SambaPw9 \"\$(getent shadow dkt_srv2 | cut -d: -f2)\""
igual "$ref" "$(nt_hash dkt_srv2)" "senha do Samba"

# ════════════════════════════════════════════════════════════════════════════
# Senha nunca na linha de comando
# ════════════════════════════════════════════════════════════════════════════
caso "senha nunca vai para a linha de comando (useradd/chpasswd/smbpasswd)"
ESPIA="useradd() { echo \"useradd \$*\" >> '$SANDBOX/args'; command useradd \"\$@\"; };
       chpasswd() { echo \"chpasswd \$*\" >> '$SANDBOX/args'; command chpasswd \"\$@\"; };
       smbpasswd() { echo \"smbpasswd \$*\" >> '$SANDBOX/args'; command smbpasswd \"\$@\"; };"
: > "$SANDBOX/args"
contem "RC=0" "$(criar dkt_x servidor "" "" "Espia#Samba" "Espia#Linux" "$ESPIA")"
contem "smbpasswd -c $SANDBOX/smb.conf -s -a -- dkt_x" "$(cat "$SANDBOX/args")" "smbpasswd com a configuração do debkit"
nao_contem "Espia#" "$(cat "$SANDBOX/args")" "nenhuma senha nos argumentos"

# ════════════════════════════════════════════════════════════════════════════
# Falhas: desfaz tudo
# ════════════════════════════════════════════════════════════════════════════
nada_sobrou() { ! getent passwd "$1" >/dev/null && ! getent group "$1" >/dev/null && ! PDB -u "$1" >/dev/null; }
caso "falha no Samba: desfaz o usuário Linux e o grupo pessoal"
saida=$(criar dkt_f1 arquivos "" "dkt_g1" "senha12" "" "smbpasswd() { return 1; };")
contem "RC=1" "$saida"; contem "não foi possível criar a conta no Samba" "$saida"; contem "foi desfeito" "$saida"
verdadeiro "nada sobrou (Linux, grupo, Samba)" nada_sobrou dkt_f1
nao_contem "dkt_f1" "$(getent group dkt_g1)" "não ficou como membro do grupo"
contem "nome=dkt_f1 resultado=desfeito" "$(cat "$SANDBOX/debkit.log")" "auditoria"
caso "falha na senha do Linux: desfaz"
saida=$(criar dkt_f2 servidor "" "" "senha12" "senha12" "chpasswd() { cat >/dev/null; return 1; };")
contem "RC=1" "$saida"; contem "não foi possível definir a senha do Linux" "$saida"
verdadeiro "nada sobrou" nada_sobrou dkt_f2
caso "falha na conferência final (Samba mexeu na senha do Linux): desfaz Samba e Linux"
saida=$(criar dkt_f3 arquivos "" "" "senha12" "" "passwd() { if [ \"\$1\" == -S ] && [ -e '$SANDBOX/samba_feito' ]; then echo \"\$3 P\"; else command passwd \"\$@\"; fi; };
        smbpasswd() { command smbpasswd \"\$@\" && touch '$SANDBOX/samba_feito'; };")
contem "RC=1" "$saida"; contem "senha do Linux não bloqueada" "$saida"
verdadeiro "nada sobrou (inclusive a conta Samba)" nada_sobrou dkt_f3
rm -f "$SANDBOX/samba_feito"
caso "falha no useradd: nada a desfazer"
saida=$(criar dkt_f4 arquivos "" "" "senha12" "" "useradd() { return 1; };")
contem "RC=1" "$saida"; contem "o useradd falhou" "$saida"; nao_contem "foi desfeito" "$saida"
verdadeiro "nada sobrou" nada_sobrou dkt_f4
caso "UID fora da faixa (login.defs diferente do useradd): desfaz"
saida=$(criar dkt_f5 arquivos "" "" "senha12" "" "debkit_uid_comum() { return 1; };")
contem "RC=1" "$saida"; contem "fora da faixa de contas comuns" "$saida"
verdadeiro "nada sobrou" nada_sobrou dkt_f5

# ════════════════════════════════════════════════════════════════════════════
# Tela (entradas como uma pessoa digitando)
# ════════════════════════════════════════════════════════════════════════════
tela() { printf '%s\n' "$@" | u "debkit_samba_tela_criar_usuario; echo RC=\$?"; }
idx() { u "debkit_samba_grupos_comuns" | grep -nx "$1" | cut -d: -f1; }
G1=$(idx dkt_g1); G2=$(idx dkt_g2)

caso "tela: usuário de arquivos com sugestão de login, grupos e confirmação"
saida=$(tela "Dkt Tela - Teste" "" "" "$G1,$G2" n "senha12" "senha12" s "")
contem "Login: dkt_tela" "$saida" "Enter no login usa a sugestão do nome completo"; contem "Nome completo: Dkt Tela - Teste" "$saida"
contem "Grupos: dkt_g1, dkt_g2" "$saida"; contem "Senha: definida (não é mostrada)" "$saida"
contem "Pasta pessoal: não" "$saida"; contem "Usuário dkt_tela criado" "$saida"; contem "RC=0" "$saida"
nao_contem "senha12" "$saida" "senha não aparece na tela"
igual "/usr/sbin/nologin" "$(getent passwd dkt_tela | cut -d: -f7)"

caso "tela: nome inválido, senha curta e senhas diferentes pedem de novo"
saida=$(tela "" "Dkt.Ruim" "dkt_tela2" "" "" n "abc" "senha12" "outra12" "senha12" "senha12" s "")
contem "Nome inválido: 'Dkt.Ruim'" "$saida"
contem "pelo menos 4 caractere(s)" "$saida"; contem "As senhas não conferem" "$saida"
contem "RC=0" "$saida"; verdadeiro "criado" getent passwd dkt_tela2

caso "tela: respondendo n na confirmação, nada é criado"
saida=$(tela "" dkt_tela3 "" "" n "senha12" "senha12" n "")
contem "Cancelado. Nada foi feito." "$saida"; contem "RC=1" "$saida"
verdadeiro "não criado" nada_sobrou dkt_tela3

caso "tela: acesso ao servidor exige confirmação explícita"
saida=$(tela "" dkt_tela4 2 n 2 s "" n "senha12" "senha12" n "Linux123" "Linux123" s "")
contem "poderá ENTRAR NO SERVIDOR" "$saida"
contem "Tipo: Usuário com acesso ao servidor" "$saida"; contem "Senha do Linux: própria" "$saida"
contem "RC=0" "$saida"
igual "/bin/bash" "$(getent passwd dkt_tela4 | cut -d: -f7)"
verdadeiro "senha do Linux própria" senha_linux_ok dkt_tela4 "Linux123"

caso "tela: número de grupo inválido pede de novo"
saida=$(tela "" dkt_tela5 "" "99" "x" "$G1" n "senha12" "senha12" s "")
contem "Escolha inválida: '99'" "$saida"; contem "Escolha inválida: 'x'" "$saida"
contem "Grupos: dkt_g1" "$saida"; contem "RC=0" "$saida"

caso "tela: fim da entrada (Ctrl+D) cancela sem criar nada"
saida=$(tela "" dkt_tela6 "")
contem "Cancelado" "$saida"; contem "RC=1" "$saida"; verdadeiro "não criado" nada_sobrou dkt_tela6
caso "tela: login vazio sem sugestão cancela"
contem "Cancelado" "$(tela "" "")"

caso "tela: ambiente não preparado - recusa antes de perguntar"
saida=$(printf '\n' | u "debkit_samba_ambiente_pronto() { return 1; }; debkit_samba_tela_criar_usuario; echo RC=\$?")
contem "ainda não está preparado" "$saida"; nao_contem "Nome completo" "$saida"; contem "RC=1" "$saida"

caso "menu Samba > Usuários > 2) Criar usuário, no terminal (perguntas, sugestão, senha sem eco)"
saida=$(pty 0.7 "bash $DEBKIT" 1 1 2 "Dkt Pty" "" "" "" n "SenhaPty1" "SenhaPty1" n "" 0 0 0)
contem "Nome completo (opcional; Enter para pular):" "$saida"
contem "Nome de login [dkt_pty]:" "$saida" "sugestão mostrada"
contem "Senha do Samba (pastas):" "$saida"; contem "Repita a senha:" "$saida"
nao_contem "SenhaPty1" "$saida" "senha não ecoa no terminal"
contem "Cancelado. Nada foi feito." "$saida"
verdadeiro "não criado" nada_sobrou dkt_pty

# ── Limpeza ──────────────────────────────────────────────────────────────────
limpar_usuarios
caso "limpeza"
verdadeiro "nenhum usuário dkt_ sobrou" bash -c "! getent passwd | grep -q '^dkt_'"
real_intacto

resumo
