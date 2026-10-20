#!/usr/bin/env bash
# Testes da tarefa 1.1b - pasta pessoal: base no disco de dados
# (HOMES_BASE), pasta na criação do usuário e para usuário existente,
# compartilhamento [homes]. Os "discos" são de verdade: arquivos ext4
# montados em loop (e um tmpfs e um ext4 somente leitura) em
# /mnt/dkt-teste.*, desmontados no fim. Usuários dkt_* reais (removidos no
# fim); base do Samba e smb.conf do sandbox. A prova com login de verdade no
# [homes] fica em t09b_home_real.sh (só com DEBKIT_TESTE_REAL=1).
source "$(dirname "$0")/lib.sh"
sandbox

if getent passwd | cut -d: -f1 | grep -q '^dkt_'; then echo "  já existem usuários dkt_* - abortando"; exit 1; fi
for c in mkfs.ext4 losetup findmnt; do command -v "$c" >/dev/null || { echo "  falta $c - abortando"; exit 1; }; done

DISCO=$(mktemp -d /mnt/dkt-teste.XXXXXX); DISCO_RO=$(mktemp -d /mnt/dkt-teste-ro.XXXXXX); DISCO_TMP=$(mktemp -d /mnt/dkt-teste-tmp.XXXXXX)
LINK="/mnt/dkt-teste-link.$$"
limpar_tudo() {
    local x
    for x in $(getent passwd | cut -d: -f1 | grep '^dkt_'); do
        pdbedit -s "$SANDBOX/smb.conf" -x -u "$x" >/dev/null 2>&1; userdel "$x" >/dev/null 2>&1
    done
    for x in $(getent group | cut -d: -f1 | grep '^dkt_'); do groupdel "$x" >/dev/null 2>&1; done
    for x in "$DISCO" "$DISCO_RO" "$DISCO_TMP"; do
        mountpoint -q "$x" && umount "$x"
        rmdir "$x" 2>/dev/null
    done
    rm -f "$LINK"
    rm -rf -- "${SANDBOX:?}"
}
trap limpar_tudo EXIT

truncate -s 32M "$SANDBOX/disco.img"; mkfs.ext4 -q -F "$SANDBOX/disco.img"
truncate -s 16M "$SANDBOX/disco_ro.img"; mkfs.ext4 -q -F "$SANDBOX/disco_ro.img"
mount -o loop "$SANDBOX/disco.img" "$DISCO" && mount -o loop,ro "$SANDBOX/disco_ro.img" "$DISCO_RO" && mount -t tmpfs -o size=4m tmpfs "$DISCO_TMP" \
    || { echo "  não foi possível montar os discos de teste - abortando"; exit 1; }
ln -s "$DISCO" "$LINK"
touch "$DISCO/um_arquivo"

preparar_sandbox
cp -p "$SANDBOX/debkit.conf" "$SANDBOX/debkit.conf.inicial"
CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;
     debkit_samba_recarregar() { echo reload >> '$SANDBOX/reloads'; };"
h() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
PDB() { pdbedit -s "$SANDBOX/smb.conf" "$@" 2>/dev/null; }
conf_inicial() { cp -p "$SANDBOX/debkit.conf.inicial" "$SANDBOX/debkit.conf"; }
nada_sobrou() { ! getent passwd "$1" >/dev/null && ! getent group "$1" >/dev/null && ! PDB -u "$1" >/dev/null; }
criar() {  # criar <nome> <tipo> <home 0|1> [código antes]
    h "${4:-} DEBKIT_U_NOME='$1'; DEBKIT_U_TIPO='$2'; DEBKIT_U_GECOS=''; DEBKIT_U_GRUPOS=(); DEBKIT_U_HOME='$3';
       DEBKIT_U_SENHA='senha12'; DEBKIT_U_SENHA_LINUX='senha12'; debkit_usuario_criar; echo RC=\$?"
}

# ════════════════════════════════════════════════════════════════════════════
# Regras da base
# ════════════════════════════════════════════════════════════════════════════
bp() { h "debkit_samba_base_problema '$1'; echo \" RC=\$?\""; }
caso "base: válidas (disco de dados, pasta nova ou o próprio ponto de montagem)"
contem "RC=0" "$(bp "$DISCO/homes")" "pasta ainda inexistente"
contem "RC=0" "$(bp "$DISCO")" "ponto de montagem"
caso "base: formato"
contem "Informe o caminho da base" "$(bp '')"
for b in relativo/homes "/mnt/com espaco" "$DISCO/hómes" "$DISCO/../homes"; do contem "Caminho inválido" "$(bp "$b")" "[$b]"; done
caso "base: pastas do sistema"
for b in /etc/homes /var/homes /usr /tmp/homes /root/homes /boot/x /run/homes; do contem "fica numa pasta do sistema" "$(bp "$b")" "$b"; done
contem "fica no disco do sistema" "$(bp /)" "/"
caso "base: links, / no fim e // são recusados (o caminho real é mostrado)"
contem "Use o caminho real" "$(bp "$LINK/homes")" "link"
contem "$DISCO/homes" "$(bp "$LINK/homes")" "mostra o caminho real"
contem "Use o caminho real" "$(bp "$DISCO/homes/")" "/ no fim"
contem "Use o caminho real" "$(bp "$DISCO//homes")" "//"
caso "base: no disco do sistema (/) é recusada"
contem "fica no disco do sistema (/)" "$(bp /dkt-teste-raiz/homes)" "pasta inexistente na raiz"
contem "fica no disco do sistema (/)" "$(bp /mnt/dkt-nao-montado/homes)" "/mnt sem disco montado"
caso "base: tmpfs, somente leitura e arquivo"
contem "que não é um disco de dados" "$(bp "$DISCO_TMP/homes")" "tmpfs"
contem "montado somente leitura" "$(bp "$DISCO_RO/homes")" "ro"
contem "existe e não é uma pasta" "$(bp "$DISCO/um_arquivo/homes")" "arquivo no caminho"

caso "discos de dados detectados"
saida=$(h "debkit_samba_discos_dados")
contem "$DISCO" "$saida"
nao_contem "$DISCO_RO" "$saida" "somente leitura fora"; nao_contem "$DISCO_TMP" "$saida" "tmpfs fora"
verdadeiro "/ fora" bash -c '! grep -qx / <<< "$1"' _ "$saida"

# ════════════════════════════════════════════════════════════════════════════
# Definir a base (gravar HOMES_BASE)
# ════════════════════════════════════════════════════════════════════════════
caso "definir a base: cria a pasta e grava HOMES_BASE (resto do debkit.conf igual)"
conf_inicial
antes=$(h "debkit_conf_valores '$SANDBOX/debkit.conf'")
saida=$(h "debkit_samba_definir_base '$DISCO/homes'; echo RC=\$? BASE=\$DEBKIT_HOMES_BASE")
contem "RC=0 BASE=$DISCO/homes" "$saida"
igual "755 0" "$(stat -c '%a %u' "$DISCO/homes")" "pasta 755 do root"
contem "HOMES_BASE=$DISCO/homes" "$(cat "$SANDBOX/debkit.conf")"
igual "$(sed "s|^HOMES_BASE=.*|HOMES_BASE=$DISCO/homes|" <<< "$antes")" "$(h "debkit_conf_valores '$SANDBOX/debkit.conf'")" "só HOMES_BASE mudou"
igual "644 0" "$(stat -c '%a %u' "$SANDBOX/debkit.conf")" "debkit.conf continua 644 do root"
verdadeiro "backup do debkit.conf" test -n "$(find "$SANDBOX/backups" -name 'debkit.conf.*')"
contem "conf_definir chave=HOMES_BASE" "$(cat "$SANDBOX/debkit.log")" "auditoria"
caso "definir a base de novo: a linha é substituída (não duplica)"
h "debkit_samba_definir_base '$DISCO/homes'" >/dev/null
igual 1 "$(grep -c '^HOMES_BASE=' "$SANDBOX/debkit.conf")"
caso "definir a base inválida: nada é criado nem gravado"
conf_inicial; md5=$(md5sum < "$SANDBOX/debkit.conf")
contem "fica numa pasta do sistema" "$(h "debkit_samba_definir_base /var/dkt_homes")"
verdadeiro "pasta não criada" test ! -e /var/dkt_homes
igual "$md5" "$(md5sum < "$SANDBOX/debkit.conf")" "debkit.conf intacto"
caso "definir a base: falha ao gravar a configuração tira a pasta que criou"
conf_inicial
saida=$(h "mv() { return 1; }; debkit_samba_definir_base '$DISCO/homes2'; echo RC=\$?")
contem "RC=1" "$saida"; verdadeiro "pasta removida" test ! -e "$DISCO/homes2"
caso "HOMES_BASE inválido no debkit.conf é recusado na leitura"
printf 'HOMES_BASE=relativo\n' >> "$SANDBOX/debkit.conf"
contem "valor inválido para HOMES_BASE" "$(bash "$DEBKIT" --verificar 2>&1)"
conf_inicial

# Base definida para os próximos testes
h "debkit_samba_definir_base '$DISCO/homes'" >/dev/null
BASE="$DISCO/homes"
cp -p "$SANDBOX/debkit.conf" "$SANDBOX/debkit.conf.com_base"

# ════════════════════════════════════════════════════════════════════════════
# Criar usuário com pasta pessoal
# ════════════════════════════════════════════════════════════════════════════
caso "usuário de arquivos com pasta pessoal"
saida=$(criar dkt_h1 arquivos 1)
contem "RC=0" "$saida"
IFS=: read -r _ _ uid gid _ home _ < <(getent passwd dkt_h1)
igual "$BASE/dkt_h1" "$home" "home no Linux"
igual "$uid $gid 700" "$(stat -c '%u %g %a' "$BASE/dkt_h1")" "dono o usuário, 700"
igual "" "$(ls -A "$BASE/dkt_h1")" "sem /etc/skel (só acessa pelo Samba)"
contem "home=$BASE/dkt_h1 resultado=ok" "$(cat "$SANDBOX/debkit.log")" "auditoria"
caso "usuário com acesso ao servidor com pasta pessoal: recebe o /etc/skel"
contem "RC=0" "$(criar dkt_h2 servidor 1)"
verdadeiro ".bashrc copiado" test -f "$BASE/dkt_h2/.bashrc"
igual "dkt_h2" "$(stat -c %U "$BASE/dkt_h2/.bashrc")" "arquivos do skel do usuário"
caso "sem pasta pessoal continua /nonexistent"
contem "RC=0" "$(criar dkt_h0 arquivos 0)"
igual "/nonexistent" "$(getent passwd dkt_h0 | cut -d: -f6)"; verdadeiro "nada na base" test ! -e "$BASE/dkt_h0"
caso "pasta já existe na base: recusa antes de criar qualquer coisa"
mkdir "$BASE/dkt_h3"; echo dado > "$BASE/dkt_h3/arquivo"
saida=$(criar dkt_h3 arquivos 1)
contem "RC=1" "$saida"; contem "já existe" "$saida"
verdadeiro "usuário não criado" nada_sobrou dkt_h3
igual "dado" "$(cat "$BASE/dkt_h3/arquivo")" "pasta existente intacta"
rm -rf "${BASE:?}/dkt_h3"
caso "falha no Samba: desfaz também a pasta pessoal"
saida=$(criar dkt_h4 arquivos 1 "smbpasswd() { return 1; };")
contem "RC=1" "$saida"; contem "foi desfeito" "$saida"
verdadeiro "nada sobrou" nada_sobrou dkt_h4; verdadeiro "pasta removida" test ! -e "$BASE/dkt_h4"
caso "disco de dados desmontado: recusa (nunca cria a pasta no disco do sistema)"
umount "$DISCO"
saida=$(criar dkt_h5 arquivos 1)
contem "RC=1" "$saida"; contem "não pode ser usada agora" "$saida"; contem "disco do sistema" "$saida"
verdadeiro "usuário não criado" nada_sobrou dkt_h5
verdadeiro "nada criado no disco do sistema" test ! -e "$BASE"
mount -o loop "$SANDBOX/disco.img" "$DISCO"

caso "remover pasta criada: só exatamente HOMES_BASE/<nome>"
mkdir -p "$SANDBOX/fora" "$BASE/x/y"
rpc() { h "DEBKIT_H_CRIADA=1; debkit_samba_remover_pasta_criada '$1'; echo RC=\$?"; }
contem "RC=1" "$(rpc "$SANDBOX/fora")" "fora da base"; verdadeiro "intacta" test -d "$SANDBOX/fora"
contem "RC=1" "$(rpc "$BASE")" "a própria base"; verdadeiro "base intacta" test -d "$BASE"
contem "RC=1" "$(rpc "$BASE/x/y")" "subpasta de outra"; verdadeiro "intacta" test -d "$BASE/x/y"
contem "RC=1" "$(rpc "$BASE/.")" "ponto"
contem "RC=0" "$(h "DEBKIT_H_CRIADA=0; debkit_samba_remover_pasta_criada '$BASE/x'; echo RC=\$?")" "não criada nesta operação: nada"
verdadeiro "intacta" test -d "$BASE/x"
rm -rf "${BASE:?}/x"

# ════════════════════════════════════════════════════════════════════════════
# Pasta pessoal para usuário existente
# ════════════════════════════════════════════════════════════════════════════
caso "usuário existente sem pasta: lista e cria"
criar dkt_e1 arquivos 0 >/dev/null
contem "dkt_e1" "$(h debkit_samba_usuarios_sem_home)"
nao_contem "dkt_h1" "$(h debkit_samba_usuarios_sem_home)" "quem tem pasta não aparece"
saida=$(h "debkit_samba_home_existente dkt_e1; echo RC=\$?")
contem "RC=0" "$saida"; contem "Pasta pessoal $BASE/dkt_e1 criada" "$saida"
igual "$BASE/dkt_e1" "$(getent passwd dkt_e1 | cut -d: -f6)"
igual "dkt_e1 dkt_e1 700" "$(stat -c '%U %G %a' "$BASE/dkt_e1")"
igual "" "$(ls -A "$BASE/dkt_e1")" "nologin: sem skel"
contem "home_criar nome=dkt_e1 pasta=$BASE/dkt_e1 resultado=ok" "$(cat "$SANDBOX/debkit.log")"
caso "usuário existente: já tem pasta / não é comum / pasta já existe"
contem "já tem pasta pessoal" "$(h "debkit_samba_home_existente dkt_e1")"
contem "não é um usuário comum" "$(h "debkit_samba_home_existente daemon")"
contem "não é um usuário comum" "$(h "debkit_samba_home_existente dkt_nao_existe")"
criar dkt_e2 arquivos 0 >/dev/null; mkdir "$BASE/dkt_e2"; echo dado > "$BASE/dkt_e2/a"
contem "já existe" "$(h "debkit_samba_home_existente dkt_e2")"
igual "/nonexistent" "$(getent passwd dkt_e2 | cut -d: -f6)" "home não mudou"; igual "dado" "$(cat "$BASE/dkt_e2/a")" "pasta intacta"
rm -rf "${BASE:?}/dkt_e2"
caso "usuário existente: usermod falha - desfaz a pasta"
saida=$(h "usermod() { return 1; }; debkit_samba_home_existente dkt_e2; echo RC=\$?")
contem "RC=1" "$saida"; contem "o usermod falhou" "$saida"
verdadeiro "pasta removida" test ! -e "$BASE/dkt_e2"; igual "/nonexistent" "$(getent passwd dkt_e2 | cut -d: -f6)"
caso "usuário existente com acesso ao servidor: recebe o skel"
criar dkt_e3 servidor 0 >/dev/null
contem "RC=0" "$(h "debkit_samba_home_existente dkt_e3; echo RC=\$?")"; verdadeiro ".bashrc" test -f "$BASE/dkt_e3/.bashrc"

# ════════════════════════════════════════════════════════════════════════════
# Compartilhamento [homes]
# ════════════════════════════════════════════════════════════════════════════
# servidor já preparado: com o log de autenticação (tarefa 3.0) do sandbox
SMB_MIN="[global]\n   workgroup = TESTE\n   server role = standalone server\n   log level = 0 auth_json_audit:3@$SANDBOX/debkit-auth.json\n\n[dados]\n   path = /tmp\n"
smb_teste() { printf '%b' "$1" > "$SANDBOX/smb.conf"; isolar_smb_conf "$SANDBOX/smb.conf"; rm -rf "$SANDBOX/conf-bkp"; : > "$SANDBOX/reloads"; }
efetivo() { testparm -s "$SANDBOX/smb.conf" 2>/dev/null; }
estado() { h "debkit_samba_homes_estado"; }
ajustar() { h "debkit_samba_ajustar_homes; echo RC=\$?"; }

caso "[homes] do Debian (somente leitura): ajustado para escrita, o resto igual"
copiar_smb_conf "$SANDBOX/smb.conf"; rm -rf "$SANDBOX/conf-bkp"
if grep -qx '\[homes\]' <<< "$(efetivo)"; then
    igual "leitura" "$(estado)"
    antes=$(efetivo)
    saida=$(ajustar)
    contem "RC=0" "$saida"; contem "Compartilhamento [homes] pronto" "$saida"
    igual "ok" "$(estado)"
    igual "No" "$(testparm -s --section-name=homes --parameter-name='read only' "$SANDBOX/smb.conf" 2>/dev/null)" "read only = No"
    igual "$(diff <(echo "$antes") <(efetivo) | grep -c '^[<>]')" "1" "só uma linha mudou na configuração em vigor"
    contem "> 	read only = No" "$(diff <(echo "$antes") <(efetivo))"
    verdadeiro "backup em conf-bkp" test -n "$(find "$SANDBOX/conf-bkp" -name 'smb.conf.*')"
    caso "[homes] ajustado: idempotente"
    md5=$(md5sum < "$SANDBOX/smb.conf"); contem "RC=0" "$(ajustar)"; igual "$md5" "$(md5sum < "$SANDBOX/smb.conf")" "nada muda"
else
    echo "  (smb.conf real sem [homes]: caso do Debian pulado)"
fi

caso "[homes] ausente: criado"
smb_teste "$SMB_MIN"
igual "ausente" "$(estado)"
antes=$(efetivo)
contem "RC=0" "$(ajustar)"
igual "ok" "$(estado)"
for p in "browseable = No" "read only = No" "valid users = %S" "create mask = 0600" "directory mask = 0700"; do
    contem "	$p" "$(efetivo | awk '/^\[/ {em = ($0 == "[homes]"); next} em')" "$p"
done
igual "$(echo "$antes" | awk NF)" "$(efetivo | awk '/^\[/ {em = ($0 == "[homes]")} !em && NF')" "resto do smb.conf igual"
caso "[homes] com writeable = yes e sem valid users: ajusta (read only = no + valid users = %S)"
smb_teste "$SMB_MIN\n[homes]\n   writeable = yes\n   browseable = no\n"
igual "leitura" "$(estado)"
contem "RC=0" "$(ajustar)"; igual "ok" "$(estado)"
nao_contem "writeable" "$(cat "$SANDBOX/smb.conf")" "linha antiga de escrita saiu"
caso "[homes] feito à mão (path próprio / valid users sem %S): o debkit não mexe"
for extra in "   path = /srv/outro" "   valid users = @financeiro"; do
    smb_teste "$SMB_MIN\n[homes]\n$extra\n"
    md5=$(md5sum < "$SANDBOX/smb.conf")
    igual "outro" "$(estado)" "$extra"
    saida=$(ajustar); contem "RC=1" "$saida"; contem "configurado à mão" "$saida"
    igual "$md5" "$(md5sum < "$SANDBOX/smb.conf")" "smb.conf intacto"
done
caso "[homes]: filtro com defeito (mexe em outro parâmetro) - a conferência recusa"
smb_teste "$SMB_MIN\n[homes]\n   browseable = no\n"
md5=$(md5sum < "$SANDBOX/smb.conf")
saida=$(h "debkit_samba_filtro_homes_ajustar() { sed 's/browseable = no/browseable = yes/'; echo '   read only = no'; }; debkit_samba_ajustar_homes; echo RC=\$?")
contem "RC=1" "$saida"; contem "mais do que o pretendido" "$saida"
igual "$md5" "$(md5sum < "$SANDBOX/smb.conf")" "smb.conf intacto"

# ════════════════════════════════════════════════════════════════════════════
# Telas
# ════════════════════════════════════════════════════════════════════════════
tela() { local f="$1"; shift; printf '%s\n' "$@" | h "$f; echo RC=\$?"; }
# Grupo próprio: a pergunta "Grupos" aparece sempre (com ou sem grupos
# reais no servidor) e as telas respondem Enter (nenhum)
groupadd dkt_h_grupo
caso "tela criar usuário: primeira vez define a base, cria com pasta e oferece o [homes]"
conf_inicial; smb_teste "$SMB_MIN"; rm -rf "${DISCO:?}/homes_t"
# nome completo, login, tipo, grupos (Enter), pasta? s, base, confirma base, senha x2, confirma, [homes]? s, Enter
saida=$(tela debkit_samba_tela_criar_usuario "" dkt_t1 "" "" s "$DISCO/homes_t" s "senha12" "senha12" s s "")
contem "Discos de dados montados:" "$saida"; contem "$DISCO" "$saida"
contem "Base das pastas pessoais: $DISCO/homes_t (gravada" "$saida"
contem "Pasta pessoal: $DISCO/homes_t/dkt_t1" "$saida" "resumo"
contem "Usuário dkt_t1 criado" "$saida"; contem "Compartilhamento [homes] pronto" "$saida"; contem "RC=0" "$saida"
igual "$DISCO/homes_t/dkt_t1" "$(getent passwd dkt_t1 | cut -d: -f6)"
contem "HOMES_BASE=$DISCO/homes_t" "$(cat "$SANDBOX/debkit.conf")"
caso "tela criar usuário: Enter na base usa a sugestão (<disco>/homes)"
conf_inicial
saida=$(tela debkit_samba_tela_criar_usuario "" dkt_t2 "" "" s "" n "senha12" "senha12" n "")
contem "Seguindo sem pasta pessoal" "$saida" "recusou a base"; contem "Cancelado" "$saida"
nao_contem "HOMES_BASE=/" "$(cat "$SANDBOX/debkit.conf")" "nada gravado"
caso "tela criar usuário (terminal): a base sugerida é <primeiro disco>/homes"
sug="$(h debkit_samba_discos_dados | head -1)/homes"
saida=$(pty 0.7 "bash $DEBKIT" 1 1 2 "" dkt_t2 "" "" s "" n "senha12" "senha12" n "" 0 0 0)
contem "Base [$sug]:" "$saida" "sugestão no prompt"; contem "Usar $sug como base das pastas pessoais" "$saida"
nao_contem "HOMES_BASE=/" "$(cat "$SANDBOX/debkit.conf")" "recusou: nada gravado"
caso "tela criar usuário: sem disco de dados - segue sem pasta"
conf_inicial
saida=$(tela "debkit_samba_discos_dados() { :; }; debkit_samba_tela_criar_usuario" "" dkt_t3 "" "" s "senha12" "senha12" s "")
contem "Nenhum disco de dados montado" "$saida"; contem "Seguindo sem pasta pessoal" "$saida"
contem "Pasta pessoal: não" "$saida"; contem "RC=0" "$saida"
igual "/nonexistent" "$(getent passwd dkt_t3 | cut -d: -f6)"
caso "tela usuário existente: escolhe, confirma e cria"
cp -p "$SANDBOX/debkit.conf.com_base" "$SANDBOX/debkit.conf"
lista=$(h debkit_samba_usuarios_sem_home); n=$(grep -nx dkt_t3 <<< "$lista" | cut -d: -f1)
saida=$(tela debkit_samba_tela_home_existente "$n" s "")
contem "Usuários sem pasta pessoal:" "$saida"; contem "Pasta pessoal $BASE/dkt_t3 criada para dkt_t3" "$saida"; contem "RC=0" "$saida"
caso "tela usuário existente: número inválido e cancelar"
saida=$(tela debkit_samba_tela_home_existente 999 "")
contem "Opção inválida: '999'" "$saida"; contem "Cancelado" "$saida"
caso "tela pastas pessoais: mostra a base e o [homes]"
saida=$(tela debkit_samba_tela_pastas_pessoais "")
contem "Base das pastas pessoais: $BASE" "$saida"; contem "Compartilhamento [homes]: ativo e com escrita" "$saida"
caso "menu: Usuários > 4) Criar pasta pessoal; Compartilhamentos > 7) Pastas pessoais"
contem "4) Criar pasta pessoal para um usuário existente" "$(pty 0.6 "bash $DEBKIT" 1 1 0 0 0)"
saida=$(pty 0.6 "bash $DEBKIT" 1 3 7 "" 0 0 0)
contem "7) Pastas pessoais: base e compartilhamento [homes]" "$saida"
contem "Base das pastas pessoais: $BASE" "$saida"

# ── Limpeza ──────────────────────────────────────────────────────────────────
real_intacto
limpar_tudo; trap - EXIT
caso "limpeza"
verdadeiro "discos de teste desmontados" bash -c "! findmnt -rn -o TARGET | grep -q dkt-teste"
verdadeiro "pontos de montagem removidos" bash -c "! ls -d /mnt/dkt-teste* 2>/dev/null | grep -q ."
verdadeiro "nenhum usuário dkt_" bash -c "! getent passwd | grep -q '^dkt_'"
resumo
