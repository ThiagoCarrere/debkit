#!/usr/bin/env bash
# Testes de excluir usuário (Fase 1, decisão de 19/10/2026, seção 3.4):
# travas, ordem (sessões → Linux → Samba → pasta pessoal → grupo pessoal),
# pasta pessoal apagada só quando pode, avisos e tela (confirmação s/n).
# Usuários/grupos dkt_* reais (removidos no fim); base do Samba e smb.conf
# do sandbox (as regras de teste vão no smb.conf DO SANDBOX: um smb.conf solto
# não isola a base de senhas).
source "$(dirname "$0")/lib.sh"
sandbox

if getent passwd | cut -d: -f1 | grep -q '^dkt_'; then echo "  já existem usuários dkt_* - abortando"; exit 1; fi
if [ -e /home/dkt_hx ]; then echo "  /home/dkt_hx já existe - abortando"; exit 1; fi
limpar_usuarios() {
    local x
    pkill -u "$(getent passwd | awk -F: '/^dkt_/ {print $1}' | paste -sd,)" 2>/dev/null
    for x in $(getent passwd | cut -d: -f1 | grep '^dkt_'); do userdel "$x" >/dev/null 2>&1; done
    for x in $(pdbedit -s "$SANDBOX/smb.conf" -L 2>/dev/null | cut -d: -f1 | grep '^dkt_'); do pdbedit -s "$SANDBOX/smb.conf" -x -u "$x" >/dev/null 2>&1; done
    for x in $(getent group | cut -d: -f1 | grep '^dkt_'); do groupdel "$x" >/dev/null 2>&1; done
    rm -rf /home/dkt_hx
}
trap 'limpar_usuarios; rm -rf -- "${SANDBOX:?}"' EXIT

copiar_smb_conf "$SANDBOX/smb.conf"
preparar_sandbox
cp "$SANDBOX/smb.conf" "$SANDBOX/smb.conf.limpo"
BASE="$SANDBOX/homes"; mkdir -p "$BASE" "$SANDBOX/dados" "$SANDBOX/outra"
cat >> "$SANDBOX/smb.conf" <<EOF

[dkt_dados]
   path = $SANDBOX/dados
EOF
CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs; DEBKIT_HOMES_BASE='$BASE';
     debkit_samba_recarregar() { echo reload >> '$SANDBOX/reloads'; };"
p() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
PDB() { pdbedit -s "$SANDBOX/smb.conf" "$@" 2>/dev/null; }
LOG() { cat "$SANDBOX/debkit.log" 2>/dev/null; }
criar() {  # criar <login> <tipo> [grupos]
    p "DEBKIT_U_NOME='$1'; DEBKIT_U_TIPO='$2'; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=(${3:-}); DEBKIT_U_HOME=0;
       DEBKIT_U_SENHA='Inicial1'; DEBKIT_U_SENHA_LINUX='Inicial1'; debkit_usuario_criar" >/dev/null
}
com_home() {  # com_home <login> <pasta>: pasta pessoal do usuário
    mkdir -p "$2"; chown "$1:$1" "$2"; chmod 700 "$2"; usermod -d "$2" "$1"
}
excluir() { p "${2:-} debkit_usuario_excluir '$1'; echo RC=\$?"; }
sumiu() { ! getent passwd "$1" >/dev/null && ! PDB -u "$1" >/dev/null && ! getent group "$1" >/dev/null; }
intacto() { getent passwd "$1" >/dev/null && PDB -u "$1" >/dev/null && getent group "$1" >/dev/null; }

groupadd dkt_gx; groupadd dkt_gy

# ════════════════════════════════════════════════════════════════════════════
# Excluir
# ════════════════════════════════════════════════════════════════════════════
caso "usuário de arquivos sem pasta: some do Linux, do Samba e dos grupos"
criar dkt_e1 arquivos "dkt_gx dkt_gy"; criar dkt_vizinho arquivos "dkt_gx"
saida=$(excluir dkt_e1)
contem "RC=0" "$saida"; contem "Usuário dkt_e1 excluído" "$saida"
verdadeiro "Linux, Samba e grupo pessoal sumiram" sumiu dkt_e1
nao_contem "dkt_e1" "$(getent group dkt_gx dkt_gy "$GRUPO_TESTE")" "saiu dos grupos"
verdadeiro "o vizinho continua" intacto dkt_vizinho
contem "dkt_vizinho" "$(getent group dkt_gx)" "grupos dos outros intactos"
contem "usuario_excluir nome=dkt_e1 uid=" "$(LOG)"; contem "pasta=nenhuma avisos=0 resultado=ok" "$(LOG)"
caso "usuário com acesso ao servidor"
criar dkt_e2 servidor
contem "RC=0" "$(excluir dkt_e2)"; verdadeiro "sumiu" sumiu dkt_e2

caso "pasta pessoal na base: apagada; arquivos dele fora dela ficam"
criar dkt_e3 arquivos; com_home dkt_e3 "$BASE/dkt_e3"
touch "$BASE/dkt_e3/doc.txt" "$SANDBOX/dados/dele.txt"; chown dkt_e3 "$BASE/dkt_e3/doc.txt" "$SANDBOX/dados/dele.txt"
saida=$(excluir dkt_e3)
contem "RC=0" "$saida"; contem "Pasta pessoal $BASE/dkt_e3 apagada" "$saida"
verdadeiro "pasta apagada" test ! -e "$BASE/dkt_e3"
verdadeiro "arquivo no compartilhamento fica" test -f "$SANDBOX/dados/dele.txt"
verdadeiro "base continua" test -d "$BASE"
caso "pasta pessoal em /home: apagada"
criar dkt_hx arquivos; com_home dkt_hx /home/dkt_hx
contem "RC=0" "$(excluir dkt_hx)"; verdadeiro "apagada" test ! -e /home/dkt_hx
caso "pasta pessoal fora da base e de /home: mantida, com aviso"
criar dkt_e4 arquivos; com_home dkt_e4 "$SANDBOX/outra/dkt_e4"
saida=$(excluir dkt_e4)
contem "RC=0" "$saida"; contem "mantida (fora da base das pastas pessoais e de /home)" "$saida"
verdadeiro "mantida" test -d "$SANDBOX/outra/dkt_e4"; verdadeiro "usuário sumiu" sumiu dkt_e4
contem "nome=dkt_e4" "$(LOG)"; contem "pasta=manter" "$(LOG)"
caso "pasta pessoal que é link: mantida (e o destino também)"
criar dkt_e5 arquivos; mkdir -p "$SANDBOX/outra/alvo"; touch "$SANDBOX/outra/alvo/x"; ln -s "$SANDBOX/outra/alvo" "$BASE/dkt_e5"; usermod -d "$BASE/dkt_e5" dkt_e5
contem "não é uma pasta comum" "$(excluir dkt_e5)"
verdadeiro "link e destino intactos" test -L "$BASE/dkt_e5" -a -f "$SANDBOX/outra/alvo/x"
caso "pasta pessoal de outro dono ou de outro usuário também: mantida"
criar dkt_e6 arquivos; mkdir -p "$BASE/dkt_e6"; usermod -d "$BASE/dkt_e6" dkt_e6          # dono root
contem "o dono não é o usuário" "$(excluir dkt_e6)"; verdadeiro "mantida" test -d "$BASE/dkt_e6"
criar dkt_e7 arquivos; criar dkt_e8 arquivos; com_home dkt_e7 "$BASE/dkt_e7"; usermod -d "$BASE/dkt_e7" dkt_e8
contem "outro usuário usa a mesma pasta" "$(excluir dkt_e7)"; verdadeiro "mantida" test -d "$BASE/dkt_e7"
saida=$(excluir dkt_e8)
contem "RC=0" "$saida"; contem "o dono não é o usuário" "$saida" "dono já excluído (número solto): mantida"
verdadeiro "mantida" test -d "$BASE/dkt_e7"

caso "grupo pessoal que é o principal de outro usuário: mantido, com aviso"
criar dkt_e9 arquivos; useradd -M -s /usr/sbin/nologin -g dkt_e9 dkt_dep
saida=$(excluir dkt_e9)
contem "RC=0" "$saida"; contem "O grupo pessoal dkt_e9 foi mantido" "$saida"
verdadeiro "grupo mantido" getent group dkt_e9; verdadeiro "dependente intacto" getent passwd dkt_dep
userdel dkt_dep; groupdel dkt_e9

# ════════════════════════════════════════════════════════════════════════════
# Travas (nada é apagado)
# ════════════════════════════════════════════════════════════════════════════
criar dkt_t1 arquivos
caso "recusa: administrador, quem roda o debkit, contas que não são comuns"
criar dkt_adm servidor; gpasswd -a dkt_adm sudo >/dev/null
contem "é administrador" "$(excluir dkt_adm)"; verdadeiro "admin intacto" intacto dkt_adm
gpasswd -d dkt_adm sudo >/dev/null
contem "é quem está rodando o debkit" "$(excluir dkt_t1 "SUDO_USER=dkt_t1;")"; verdadeiro "intacto" intacto dkt_t1
for x in root daemon nobody dkt_nao_existe; do contem "não é um usuário comum" "$(excluir "$x")" "$x"; done
verdadeiro "root e daemon intactos" bash -c "getent passwd root && getent passwd daemon"
caso "recusa: grupo pessoal usado no smb.conf"
printf '   valid users = @dkt_t1\n' >> "$SANDBOX/smb.conf"
saida=$(excluir dkt_t1)
contem "RC=1" "$saida"; contem "O grupo pessoal de dkt_t1 é usado no Samba ([dkt_dados])" "$saida"
verdadeiro "intacto" intacto dkt_t1
sed -i '/valid users = @dkt_t1/d' "$SANDBOX/smb.conf"
caso "recusa: processo do usuário fora do Samba (ex: SSH)"
su -s /bin/sh dkt_t1 -c 'exec sleep 60' >/dev/null 2>&1 & sleep 0.5
saida=$(excluir dkt_t1)
contem "RC=1" "$saida"; contem "tem processos em execução fora do Samba" "$saida"; contem "(sleep)" "$saida"
verdadeiro "intacto" intacto dkt_t1
pkill -u dkt_t1; sleep 0.5
caso "userdel falha: nada é apagado (Samba e pasta ficam)"
com_home dkt_t1 "$BASE/dkt_t1"
saida=$(excluir dkt_t1 "userdel() { return 1; };")
contem "RC=1" "$saida"; contem "o userdel falhou (nada foi apagado)" "$saida"
verdadeiro "intacto" intacto dkt_t1; verdadeiro "pasta intacta" test -d "$BASE/dkt_t1"
contem "usuario_excluir nome=dkt_t1 resultado=falha motivo=userdel" "$(LOG)"

# ════════════════════════════════════════════════════════════════════════════
# Sessões do Samba
# ════════════════════════════════════════════════════════════════════════════
sessao() { sleep 60 >/dev/null 2>&1 & echo $!; }
FAKE() {  # FAKE <pid> <usuário> [nao]: smbstatus mostra a sessão; smbcontrol encerra (ou não)
    echo "smbstatus() { printf 'PID     Username     Group\\n-----\\n%s  %s  %s  127.0.0.1\\n' '$1' '$2' '$2'; };
          smbcontrol() { [ '${3:-sim}' == sim ] && kill \"\$3\"; return 0; };"
}
caso "sessão aberta: encerrada e o usuário excluído"
P=$(sessao)
saida=$(excluir dkt_t1 "$(FAKE "$P" dkt_t1)")
contem "RC=0" "$saida"; contem "1 sessão(ões) do Samba encerrada(s)" "$saida"
verdadeiro "sessão encerrada" bash -c "! kill -0 $P"; verdadeiro "sumiu" sumiu dkt_t1
verdadeiro "pasta apagada" test ! -e "$BASE/dkt_t1"
caso "sessão que não fecha: nada é apagado"
criar dkt_t2 arquivos; P=$(sessao)
saida=$(excluir dkt_t2 "$(FAKE "$P" dkt_t2 nao)")
contem "RC=1" "$saida"; contem "não foi possível encerrar a sessão do Samba (nada foi apagado)" "$saida"
verdadeiro "intacto" intacto dkt_t2
kill "$P"
caso "conta Samba não sai: avisa (o Linux já foi)"
saida=$(excluir dkt_t2 "pdbedit() { [ \"\$3\" == -x ] && return 1; command pdbedit \"\$@\"; };")
contem "RC=0" "$saida"; contem "a conta Samba de dkt_t2 ficou" "$saida"
verdadeiro "Linux sumiu" bash -c "! getent passwd dkt_t2"; verdadeiro "Samba ficou" PDB -u dkt_t2
contem "avisos=1" "$(LOG)"
PDB -x -u dkt_t2 >/dev/null

# ════════════════════════════════════════════════════════════════════════════
# Consultas
# ════════════════════════════════════════════════════════════════════════════
caso "login citado no smb.conf (nome solto e force user; @grupo não conta)"
criar dkt_t3 arquivos
cat >> "$SANDBOX/smb.conf" <<EOF

[dkt_a]
   path = $SANDBOX/dados
   valid users = dkt_t3, dkt_t30
[dkt_b]
   path = $SANDBOX/dados
   force user = dkt_t3
[dkt_c]
   path = $SANDBOX/dados
   write list = @dkt_t3x, dkt_t3x
EOF
igual "$(printf '%s\n' dkt_a dkt_b)" "$(p "debkit_samba_usuario_usos dkt_t3")"
caso "arquivos do usuário: conta fora da pasta pessoal"
com_home dkt_t3 "$BASE/dkt_t3"; U3=$(id -u dkt_t3)
touch "$BASE/dkt_t3/a" "$BASE/dkt_t3/b" "$SANDBOX/dados/c"; chown dkt_t3 "$BASE/dkt_t3/a" "$BASE/dkt_t3/b" "$SANDBOX/dados/c"
igual 4 "$(p "debkit_contar_arquivos -user $U3")" "pasta + a + b + c"
igual 1 "$(p "debkit_contar_arquivos -user $U3 '$BASE/dkt_t3'")" "sem a pasta pessoal"

# ════════════════════════════════════════════════════════════════════════════
# Tela
# ════════════════════════════════════════════════════════════════════════════
tela() { printf '%s\n' "$@" | p "debkit_samba_tela_excluir_usuario; echo RC=\$?"; }
idx() { p "debkit_samba_usuarios_dados" | awk -F'|' '$3 != "" && $3 != "admin" {print $1}' | grep -nx "$1" | cut -d: -f1; }
caso "tela: mostra o que será perdido e 'n' cancela"
gpasswd -a dkt_t3 dkt_gx >/dev/null
saida=$(tela "$(idx dkt_t3)" n "")
contem "Será excluído dkt_t3:" "$saida"; contem "Tipo: arquivos" "$saida"; contem "Grupos: dkt_gx" "$saida"
contem "Pasta pessoal: $BASE/dkt_t3 - será APAGADA" "$saida"
contem "nos compartilhamentos: [dkt_a] [dkt_b]" "$saida"
contem "1 arquivo(s)/pasta(s) dele nos compartilhamentos NÃO serão apagados" "$saida"
contem "Cancelado" "$saida"; verdadeiro "intacto" intacto dkt_t3; verdadeiro "pasta intacta" test -d "$BASE/dkt_t3"
caso "tela: admin e quem roda não aparecem; 's' exclui"
gpasswd -a dkt_adm sudo >/dev/null
saida=$(tela "")
nao_contem "dkt_adm " "$saida" "admin fora da lista"
gpasswd -d dkt_adm sudo >/dev/null
nao_contem "dkt_vizinho " "$(printf '\n' | p "SUDO_USER=dkt_vizinho; debkit_samba_tela_excluir_usuario")" "quem roda fora da lista"
saida=$(tela "$(idx dkt_t3)" s "")
contem "Usuário dkt_t3 excluído" "$saida"; verdadeiro "sumiu" sumiu dkt_t3; verdadeiro "pasta apagada" test ! -e "$BASE/dkt_t3"
caso "tela: UID reaproveitado herda os arquivos que ficaram (o aviso mostra)"
criar dkt_r9 arquivos; touch "$SANDBOX/dados/heranca.txt"; chown dkt_r9 "$SANDBOX/dados/heranca.txt"; U9=$(id -u dkt_r9)
contem "RC=0" "$(excluir dkt_r9)"
igual "$U9" "$(stat -c %u "$SANDBOX/dados/heranca.txt")" "arquivo fica com o número"
useradd -M -U -s /usr/sbin/nologin -u "$U9" -G "$GRUPO_TESTE" dkt_herdeiro
igual "dkt_herdeiro" "$(stat -c %U "$SANDBOX/dados/heranca.txt")" "o usuário novo com o mesmo UID vira dono"
saida=$(tela "$(idx dkt_herdeiro)" n "")
contem "dele nos compartilhamentos NÃO serão apagados" "$saida" "o aviso mostra"; contem "Contas: Linux (sem conta no Samba)" "$saida"
criar dkt_t4 arquivos
caso "tela: sem pasta e sem arquivos"
rm -rf -- "${BASE:?}"/* "$SANDBOX/dados"/*
saida=$(tela "$(idx dkt_t4)" s "")
contem "Pasta pessoal: não tem" "$saida"; contem "Nenhum arquivo dele" "$saida"; contem "excluído" "$saida"
caso "tela: recusa antes de perguntar (processo aberto)"
criar dkt_t5 arquivos; su -s /bin/sh dkt_t5 -c 'exec sleep 60' >/dev/null 2>&1 & sleep 0.5
saida=$(tela "$(idx dkt_t5)" s "")
contem "tem processos em execução" "$saida"; nao_contem "Será excluído" "$saida"; verdadeiro "intacto" intacto dkt_t5
pkill -u dkt_t5; sleep 0.5
caso "menu Samba > Usuários > 5) Excluir usuário"
cp "$SANDBOX/smb.conf.limpo" "$SANDBOX/smb.conf"
saida=$(pty 0.6 "bash $DEBKIT" 1 1 5 "" 0 0 0)
contem "5) Excluir usuário" "$saida"; contem "Excluir usuário" "$saida"; contem "Cancelado" "$saida"
caso "inglês"
contem "User dkt_t5 deleted." "$(p "DEBKIT_IDIOMA=en; debkit_usuario_excluir dkt_t5")"

limpar_usuarios
caso "limpeza"
verdadeiro "nenhum usuário dkt_" bash -c "! getent passwd | grep -q '^dkt_'"
verdadeiro "nenhuma conta Samba dkt_ no sandbox" bash -c "! pdbedit -s '$SANDBOX/smb.conf' -L 2>/dev/null | grep -q '^dkt_'"
nao_contem "dkt_" "$(getent group sudo)"
verdadeiro "/home/dkt_hx não existe" test ! -e /home/dkt_hx
real_intacto
resumo
