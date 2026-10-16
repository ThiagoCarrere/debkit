#!/usr/bin/env bash
# Testes da tarefa 1.0 - reestruturação: ponto de entrada + núcleo +
# módulos, carregamento seguro dos arquivos, chaves obsoletas, faixas do
# login.defs, backups (nome, sufixo, rotação por data), edição segura do
# smb.conf e remoção do "include" antigo. Tudo em caixa de areia.
source "$(dirname "$0")/lib.sh"
caixa_de_areia

# Trecho que configura o debkit (em modo source) para a areia; o "recarregar
# o Samba" é simulado (anota em reloads; FALHA_RELOAD=1 simula falha)
CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null;
     debkit_samba_recarregar() { echo reload >> '$AREIA/reloads'; [ \"\${FALHA_RELOAD:-0}\" -eq 0 ]; };"
g() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }

# ════════════════════════════════════════════════════════════════════════════
# Estrutura e carregamento
# ════════════════════════════════════════════════════════════════════════════
caso "estrutura: ponto de entrada, núcleo e módulo samba"
verdadeiro "debkit executável" test -x "$REPO/debkit"
verdadeiro "lib/nucleo.sh" test -f "$REPO/lib/nucleo.sh"
verdadeiro "modulos/samba.sh" test -f "$REPO/modulos/samba.sh"
verdadeiro "debkit.sh antigo não existe mais" test ! -e "$REPO/debkit.sh"
igual "samba" "$(bash -c "source '$DEBKIT'; echo \"\${DEBKIT_MODULOS[*]}\"")" "módulo registrado"

caso "chamado por um link (como /usr/local/sbin/debkit)"
mkdir -p "$AREIA/bin"; ln -s "$DEBKIT" "$AREIA/bin/debkit"
igual "debkit 0.1.0-dev" "$("$AREIA/bin/debkit" --versao 2>&1)" "acha núcleo e módulos pela pasta real"

# Cópia do programa para mexer nas permissões sem tocar no repositório
copia() {
    rm -rf "${AREIA:?}/prog"; mkdir -p "$AREIA/prog"
    cp -a "$REPO/debkit" "$REPO/lib" "$REPO/modulos" "$AREIA/prog/"
}
roda_copia() { bash "$AREIA/prog/debkit" --versao 2>&1; echo "RC=$?"; }

caso "carregamento seguro: cópia íntegra funciona"
copia; contem "debkit 0.1.0-dev" "$(roda_copia)"
caso "carregamento seguro: núcleo com escrita para outros"
copia; chmod 646 "$AREIA/prog/lib/nucleo.sh"; saida=$(roda_copia)
contem "nucleo.sh não é seguro" "$saida"; contem "RC=1" "$saida"; nao_contem "debkit 0.1.0-dev" "$saida" "nada executado"
caso "carregamento seguro: módulo com escrita para o grupo"
copia; chmod 664 "$AREIA/prog/modulos/samba.sh"; saida=$(roda_copia)
contem "samba.sh não é seguro" "$saida"; contem "RC=1" "$saida"
caso "carregamento seguro: pasta de módulos com escrita para outros"
copia; chmod 777 "$AREIA/prog/modulos"; saida=$(roda_copia)
contem "modulos não é seguro" "$saida"; contem "RC=1" "$saida"
caso "carregamento seguro: pasta do programa com escrita para outros"
copia; chmod 757 "$AREIA/prog"; saida=$(roda_copia)
contem "prog não é seguro" "$saida"; contem "RC=1" "$saida"
caso "carregamento seguro: núcleo de outro dono (não root)"
copia; chown 65534 "$AREIA/prog/lib/nucleo.sh"; saida=$(roda_copia)
contem "precisa pertencer ao root" "$saida"; contem "dono UID 65534" "$saida"; contem "RC=1" "$saida"
caso "carregamento seguro: núcleo ausente"
copia; rm "$AREIA/prog/lib/nucleo.sh"; saida=$(roda_copia)
contem "nucleo.sh ausente" "$saida"; contem "RC=1" "$saida"
caso "carregamento seguro: módulo que é um link"
copia; mv "$AREIA/prog/modulos/samba.sh" "$AREIA/samba_real.sh"; ln -s "$AREIA/samba_real.sh" "$AREIA/prog/modulos/samba.sh"
saida=$(roda_copia); contem "ausente ou é um link" "$saida"; contem "RC=1" "$saida"
rm -f "$AREIA/samba_real.sh"
caso "carregamento seguro: módulo inseguro NUNCA é executado"
copia; rm -f /tmp/debkit_injecao_modulo
echo 'touch /tmp/debkit_injecao_modulo' > "$AREIA/prog/modulos/zz_mau.sh"; chmod 666 "$AREIA/prog/modulos/zz_mau.sh"
saida=$(roda_copia); contem "RC=1" "$saida"
verdadeiro "o código do módulo não rodou" test ! -e /tmp/debkit_injecao_modulo
caso "carregamento seguro: só root pode rodar arquivos de root (sem root também funciona a ajuda)"
copia; saida=$(setpriv --reuid=65534 --regid=65534 --clear-groups bash "$AREIA/prog/debkit" --ajuda 2>&1)
contem "Uso: debkit" "$saida"

# Um módulo novo entra só colocando o arquivo em modulos/ (sem mexer nos outros)
caso "módulo novo: registrado, com item na verificação e no menu"
copia
cat > "$AREIA/prog/modulos/zz_teste.sh" <<'EOF'
# shellcheck shell=bash
debkit_modulo_registrar zzteste
MSG_pt_BR+=([menu.zzteste]="Módulo de teste" [amb.grupo_zzteste]="Grupo de teste")
debkit_zzteste_verificar() { debkit_verif_add zzteste ok "item do módulo de teste"; }
debkit_zzteste_menu() { echo "TELA DO MÓDULO DE TESTE"; pausar; }
EOF
chmod 644 "$AREIA/prog/modulos/zz_teste.sh"
igual "samba zzteste" "$(bash -c "source '$AREIA/prog/debkit'; echo \"\${DEBKIT_MODULOS[*]}\"")" "ordem alfabética dos arquivos"
saida=$(bash "$AREIA/prog/debkit" --verificar 2>&1)
contem "Grupo de teste" "$saida"; contem "item do módulo de teste" "$saida"
preparar_areia
saida=$(pty 0.6 "bash $AREIA/prog/debkit" 2 "" 0)
contem "2) Módulo de teste" "$saida"; contem "TELA DO MÓDULO DE TESTE" "$saida"
rm -rf "${AREIA:?}/prog"

# ── Menu ─────────────────────────────────────────────────────────────────────
caso "menu principal lista os módulos e abre o do Samba"
saida=$(pty 0.6 "bash $DEBKIT" 1 0 0)
contem "1) Samba: usuários, grupos e compartilhamentos" "$saida"
contem "9) Ambiente: verificar e preparar" "$saida"
contem "(as funções serão adicionadas nas próximas etapas)" "$saida" "tela do Samba"
contem "0) Voltar" "$saida"
caso "menu: número sem módulo é opção inválida"
saida=$(pty 0.6 "bash $DEBKIT" 2 "" 8 "" 0)
contem "Opção inválida: '2'" "$saida"; contem "Opção inválida: '8'" "$saida"
caso "menu do Samba: opção inválida e Ctrl+D"
contem "Opção inválida: 'x'" "$(pty 0.6 "bash $DEBKIT" 1 x "" 0 0)"
printf '1\n' | timeout 10 bash "$DEBKIT" >/dev/null 2>&1; igual 0 "$?" "fim da entrada dentro do módulo encerra"

# ════════════════════════════════════════════════════════════════════════════
# Configuração
# ════════════════════════════════════════════════════════════════════════════
conf() { printf '%b' "$1" > "$AREIA/c.conf"; chmod 644 "$AREIA/c.conf"; }
carregar() { bash -c "source '$DEBKIT'; debkit_conf_carregar '$AREIA/c.conf'; rc=\$?; eval \"echo rc=\$rc \$1\"; printf 'E:%s\nA:%s\n' \"\$DEBKIT_CONF_ERROS\" \"\$DEBKIT_CONF_AVISOS\"" _ "$1"; }

caso "padrões do módulo samba"
igual "/etc/samba/smb.conf /etc/samba/conf-bkp" "$(bash -c "source '$DEBKIT'; debkit_conf_padroes; echo \"\$DEBKIT_SMB_CONF \$DEBKIT_SMB_BACKUP_DIR\"")"
caso "SMB_BACKUP_DIR configurável e validado"
conf 'SMB_BACKUP_DIR=/srv/bkp-samba'; contem "rc=0 /srv/bkp-samba" "$(carregar '$DEBKIT_SMB_BACKUP_DIR')"
conf 'SMB_BACKUP_DIR=relativo/bkp'; contem "linha 1: valor inválido para SMB_BACKUP_DIR" "$(carregar '')"
caso "chaves obsoletas (SHARES_CONF, PREFIXO_GRUPO): aviso próprio, não impedem"
conf 'SHARES_CONF=/etc/samba/debkit-shares.conf\nPREFIXO_GRUPO=debkit_\nSENHA_MIN=6'
saida=$(carregar '$DEBKIT_SENHA_MIN')
contem "rc=0 6" "$saida"
contem "linha 1: a chave 'SHARES_CONF' não é mais usada" "$saida"
contem "linha 2: a chave 'PREFIXO_GRUPO' não é mais usada" "$saida"
contem "pode apagar a linha" "$saida"; nao_contem "desconhecida" "$saida"
caso "chaves obsoletas: o valor não vira variável"
conf 'SHARES_CONF=/x/y'; contem "rc=0 []" "$(carregar '[$DEBKIT_SHARES_CONF]')"

# ════════════════════════════════════════════════════════════════════════════
# Faixas de contas (/etc/login.defs)
# ════════════════════════════════════════════════════════════════════════════
# ldefs '<conteúdo>' -> "rc UID_MIN UID_MAX GID_MIN GID_MAX" e o erro
ldefs() {
    printf '%b' "$1" > "$AREIA/login.defs"
    bash -c "source '$DEBKIT'; DEBKIT_ARQ_LOGIN_DEFS='$AREIA/login.defs'; debkit_ler_login_defs; echo \"rc=\$? \$DEBKIT_UID_MIN \$DEBKIT_UID_MAX \$DEBKIT_GID_MIN \$DEBKIT_GID_MAX\"; echo \"E=\$DEBKIT_CONTAS_ERRO\""
}
caso "login.defs real"
igual "rc=0" "$(bash -c "source '$DEBKIT'; debkit_ler_login_defs; echo rc=\$?")"
caso "login.defs: valores próprios, espaços/tabs, comentários"
contem "rc=0 2000 3000 1500 1600" "$(ldefs '# UID_MIN 1\nUID_MIN 2000\n  UID_MAX\t\t3000\n#GID_MIN 5\nGID_MIN\t 1500\nGID_MAX 1600 # resto\nMAIL_DIR /var/mail')"
caso "login.defs: a última ocorrência vale, aspas e CRLF"
contem "rc=0 1200 60000 1100 2000" "$(ldefs 'UID_MIN 500\nUID_MIN 1200\nGID_MIN "1100"\r\nGID_MAX 2000\r\n')"
caso "login.defs: chaves ausentes usam o padrão"
contem "rc=0 1000 60000 1000 60000" "$(ldefs 'PASS_MAX_DAYS 99999\n')"
caso "login.defs ausente: padrão do Debian com aviso"
saida=$(bash -c "source '$DEBKIT'; DEBKIT_ARQ_LOGIN_DEFS=/nao/existe; debkit_ler_login_defs; echo \"rc=\$? \$DEBKIT_UID_MIN \$DEBKIT_UID_MAX E=\$DEBKIT_CONTAS_ERRO\"")
contem "rc=1 1000 60000 E=arquivo ausente ou ilegível" "$saida"
caso "login.defs: valores inválidos (0, hexadecimal, zero à esquerda, texto) usam o padrão"
saida=$(ldefs 'UID_MIN 0\nUID_MAX 0x10000\nGID_MIN 01000\nGID_MAX abc')
contem "rc=1 1000 60000 1000 60000" "$saida"
for k in "UID_MIN inválido ('0')" "UID_MAX inválido ('0x10000')" "GID_MIN inválido ('01000')" "GID_MAX inválido ('abc')"; do contem "$k" "$saida"; done
caso "login.defs: faixa invertida volta ao padrão só daquele tipo"
saida=$(ldefs 'UID_MIN 5000\nUID_MAX 4000\nGID_MIN 2000\nGID_MAX 3000')
contem "rc=1 1000 60000 2000 3000" "$saida"; contem "UID_MIN maior que UID_MAX" "$saida"
caso "login.defs: verificação mostra a faixa (ou o aviso)"
contem "Contas comuns ($AREIA/login.defs): usuários UID 1000-60000, grupos GID 1000-60000" \
      "$(printf 'UID_MIN 1000\n' > "$AREIA/login.defs"; bash -c "source '$DEBKIT'; $CFG DEBKIT_ARQ_LOGIN_DEFS='$AREIA/login.defs'; debkit_verificar_ambiente >/dev/null; printf '%s\n' \"\${DEBKIT_VERIF[@]}\"")"
saida=$(bash -c "source '$DEBKIT'; $CFG DEBKIT_ARQ_LOGIN_DEFS=/nao/existe; debkit_verificar_ambiente; echo RC=\$?; printf '%s\n' \"\${DEBKIT_VERIF[@]}\"")
contem "usando o padrão do Debian" "$saida"; contem "RC=0" "$saida" "é aviso, não impede"

caso "contas comuns: limites da faixa (padrão 1000-60000)"
uc() { bash -c "source '$DEBKIT'; DEBKIT_ARQ_LOGIN_DEFS=/nao/existe; debkit_ler_login_defs; ${2:-} for v in $1; do debkit_${3:-uid}_comum \"\$v\" && echo -n S || echo -n N; done"; }
igual "NSSNNNNNN" "$(uc "999 1000 60000 60001 0 65534 abc 1e3 -1")"
igual "NSSN" "$(uc "999 1000 60000 60001" "" gid)" "GID"
igual "N" "$(uc "0" 'DEBKIT_UID_MIN=0;')" "UID 0 nunca é comum, nem com UID_MIN 0"
igual "S" "$(uc "01000")" "zero à esquerda é decimal (1000), não octal"

# ════════════════════════════════════════════════════════════════════════════
# Backups
# ════════════════════════════════════════════════════════════════════════════
B="$AREIA/bk"
DATA_FIXA='date() { echo "$DATA"; };'
bk() { DATA="$1" bash -c "source '$DEBKIT'; $CFG $DATA_FIXA DEBKIT_BACKUP_MANTER=${2:-30}; debkit_backup '$AREIA/arq.conf' '$B'" 2>&1; }
lista_bk() { find "$B" -maxdepth 1 -type f -printf '%f\n' | sort | tr '\n' ' ' | sed 's/ $//'; }

caso "backup: nome dd-mm-aaaa-hh-mm-ss e sufixo no mesmo segundo"
rm -rf "$B"; echo a > "$AREIA/arq.conf"
igual "$B/arq.conf.16-10-2026-17-42-05" "$(bk 16-10-2026-17-42-05)" "primeiro"
echo b > "$AREIA/arq.conf"; igual "$B/arq.conf.16-10-2026-17-42-05-2" "$(bk 16-10-2026-17-42-05)" "segundo: -2"
echo c > "$AREIA/arq.conf"; igual "$B/arq.conf.16-10-2026-17-42-05-3" "$(bk 16-10-2026-17-42-05)" "terceiro: -3"
igual "a b c" "$(cat "$B/arq.conf.16-10-2026-17-42-05" "$B/arq.conf.16-10-2026-17-42-05-2" "$B/arq.conf.16-10-2026-17-42-05-3" | tr '\n' ' ' | sed 's/ $//')" "nenhum sobrescrito"
igual 700 "$(stat -c %a "$B")" "pasta 700"

caso "backup: nome liberado pela rotação não é reaproveitado (a cópia nova nunca some)"
rm -rf "$B"
for i in 1 2 3 4 5 6; do
    echo "v$i" > "$AREIA/arq.conf"; novo=$(bk 16-10-2026-17-42-05 2)
    igual "v$i" "$(cat "$novo" 2>/dev/null)" "backup $i existe logo depois de criado"
done
igual "arq.conf.16-10-2026-17-42-05-5 arq.conf.16-10-2026-17-42-05-6" "$(lista_bk)" "ficam os 2 mais novos"

caso "backup: rotação pela data do nome, só com o padrão do debkit"
rm -rf "$B"; mkdir -p "$B"
for n in 15-06-2025-10-00-00 31-12-2025-23-59-59 01-01-2026-00-00-00 01-01-2026-00-00-00-9 01-01-2026-00-00-00-10; do echo velho > "$B/arq.conf.$n"; done
for n in arq.conf.bak arq.conf.2026 arq.conf.01-01-2026-00-00-00-1 arq.conf.01-01-2026-00-00-00-02 arq.conf.1-1-2026-00-00-00 outro.conf.01-01-2020-00-00-00 LEIA-ME; do echo alheio > "$B/$n"; done
mkdir "$B/arq.conf.01-01-2000-00-00-00"   # pasta com nome de backup: ignorada
echo novo > "$AREIA/arq.conf"; bk 02-01-2026-08-00-00 3 >/dev/null
saida=$(lista_bk)
for n in 01-01-2026-00-00-00-9 01-01-2026-00-00-00-10 02-01-2026-08-00-00; do contem "arq.conf.$n" "$saida" "mantido $n"; done
for n in 15-06-2025-10-00-00 31-12-2025-23-59-59; do nao_contem "arq.conf.$n " "$saida " "apagado $n"; done
nao_contem "arq.conf.01-01-2026-00-00-00 " "$saida " "apagado 01-01-2026 (sem sufixo, mais antigo que -9)"
for n in arq.conf.bak arq.conf.2026 arq.conf.01-01-2026-00-00-00-1 arq.conf.01-01-2026-00-00-00-02 arq.conf.1-1-2026-00-00-00 outro.conf.01-01-2020-00-00-00 LEIA-ME; do
    contem "$n" "$saida" "outro arquivo intacto: $n"
done
verdadeiro "pasta com nome de backup intacta" test -d "$B/arq.conf.01-01-2000-00-00-00"

caso "backup: relógio atrasado - a cópia nova é mantida mesmo parecendo mais antiga"
rm -rf "$B"; mkdir -p "$B"
for n in 01-01-2026-00-00-00 02-01-2026-00-00-00 03-01-2026-00-00-00; do echo velho > "$B/arq.conf.$n"; done
echo novo > "$AREIA/arq.conf"; novo=$(bk 01-01-2020-00-00-00 2)
igual "novo" "$(cat "$novo" 2>/dev/null)" "cópia nova existe"
igual "arq.conf.01-01-2020-00-00-00 arq.conf.03-01-2026-00-00-00" "$(lista_bk)" "total = BACKUP_MANTER, com a nova"

caso "backup: cópia que não confere é apagada e dá erro"
rm -rf "$B"; echo x > "$AREIA/arq.conf"
saida=$(bash -c "source '$DEBKIT'; $CFG cmp() { return 1; }; debkit_backup '$AREIA/arq.conf' '$B'; echo RC=\$?" 2>&1)
contem "não ficou igual ao original" "$saida"; contem "RC=1" "$saida"
igual "" "$(lista_bk)" "nenhuma cópia deixada"

caso "backup do smb.conf vai para SMB_BACKUP_DIR"
rm -rf "$AREIA/conf-bkp"
b=$(g "debkit_samba_backup")
contem "$AREIA/conf-bkp/smb.conf." "$b"
verdadeiro "nome smb.conf.dd-mm-aaaa-hh-mm-ss" bash -c '[[ "${1##*/}" =~ ^smb\.conf\.[0-9]{2}-[0-9]{2}-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]' _ "$b"
igual 700 "$(stat -c %a "$AREIA/conf-bkp")" "pasta criada com 700"
igual 600 "$(stat -c %a "$b")" "cópia 600"
verdadeiro "igual ao smb.conf" cmp -s "$b" "$AREIA/smb.conf"
igual "" "$(find "$AREIA/backups" -name 'smb.conf.*' 2>/dev/null)" "nada em BACKUP_DIR"

# ════════════════════════════════════════════════════════════════════════════
# Edição segura do smb.conf
# ════════════════════════════════════════════════════════════════════════════
SMB_MIN='[global]\n   workgroup = TESTE\n   server role = standalone server\n\n[dados]\n   path = /tmp\n'
smb_novo() {
    printf '%b' "$SMB_MIN" > "$AREIA/smb.conf"
    chmod 640 "$AREIA/smb.conf"; chgrp nogroup "$AREIA/smb.conf"
    rm -rf "$AREIA/conf-bkp"; : > "$AREIA/reloads"
}
# Funções de teste: transformar (filtros) e conferir
FUNCS='mais_comentario() { cat; echo "; comentario do teste"; }
       outro_grupo() { sed "s/workgroup = TESTE/workgroup = OUTRO/"; }
       quebra() { echo "[global"; }
       falha() { return 1; }
       igual_efetivo() { cmp -s "$1" "$2"; };'
ed() { g "$FUNCS debkit_smbconf_editar $1 $2; echo RC=\$? TROCADO=\$DEBKIT_SMB_TROCADO"; }
sem_temp() { [ -z "$(find "$AREIA" -maxdepth 1 -name '.debkit-smb.conf.*')" ]; }

caso "edição: sucesso (backup, troca atômica, dono/permissões, reload)"
smb_novo; md5_antes=$(md5sum < "$AREIA/smb.conf"); inode_antes=$(stat -c %i "$AREIA/smb.conf")
saida=$(ed mais_comentario igual_efetivo)
contem "RC=0 TROCADO=1" "$saida"
contem "; comentario do teste" "$(tail -1 "$AREIA/smb.conf")" "alteração gravada"
igual "640 root nogroup" "$(stat -c '%a %U %G' "$AREIA/smb.conf")" "dono e permissões mantidos"
verdadeiro "troca por rename (inode novo)" test "$(stat -c %i "$AREIA/smb.conf")" != "$inode_antes"
igual "$md5_antes" "$(md5sum < "$(find "$AREIA/conf-bkp" -name 'smb.conf.*' | head -1)")" "backup do original em conf-bkp"
igual 1 "$(grep -c reload "$AREIA/reloads")" "Samba recarregado 1 vez"
verdadeiro "nenhum temporário deixado" sem_temp

caso "edição: mudaria mais do que o pretendido -> recusa, nada muda"
smb_novo; md5_antes=$(md5sum < "$AREIA/smb.conf")
saida=$(ed outro_grupo igual_efetivo)
contem "RC=1 TROCADO=0" "$saida"; contem "mudaria no $AREIA/smb.conf mais do que o pretendido" "$saida"
igual "$md5_antes" "$(md5sum < "$AREIA/smb.conf")" "smb.conf intacto"
igual 0 "$(grep -c reload "$AREIA/reloads")" "sem reload"
verdadeiro "nenhum temporário deixado" sem_temp

caso "edição: ficaria inválido -> recusa, nada muda"
smb_novo; md5_antes=$(md5sum < "$AREIA/smb.conf")
saida=$(ed quebra igual_efetivo)
contem "RC=1 TROCADO=0" "$saida"; contem "ficaria inválido (testparm)" "$saida"
igual "$md5_antes" "$(md5sum < "$AREIA/smb.conf")" "smb.conf intacto"
verdadeiro "nenhum temporário deixado" sem_temp

caso "edição: transformação falha -> nada muda"
smb_novo; md5_antes=$(md5sum < "$AREIA/smb.conf")
contem "RC=1 TROCADO=0" "$(ed falha igual_efetivo)"
igual "$md5_antes" "$(md5sum < "$AREIA/smb.conf")" "smb.conf intacto"
verdadeiro "nenhum temporário deixado" sem_temp

caso "edição: reload falha -> restaura o backup (com dono/permissões)"
smb_novo; md5_antes=$(md5sum < "$AREIA/smb.conf")
saida=$(FALHA_RELOAD=1 ed mais_comentario igual_efetivo)
contem "RC=1 TROCADO=0" "$saida"; contem "Não foi possível recarregar o Samba" "$saida"; contem "restaurado do backup" "$saida"
igual "$md5_antes" "$(md5sum < "$AREIA/smb.conf")" "conteúdo original de volta"
igual "640 root nogroup" "$(stat -c '%a %U %G' "$AREIA/smb.conf")" "dono e permissões mantidos"
igual 2 "$(grep -c reload "$AREIA/reloads")" "recarregou de novo depois de restaurar"
verdadeiro "nenhum temporário deixado" sem_temp

caso "edição: smb.conf ausente"
contem "não existe" "$(g "$FUNCS DEBKIT_SMB_CONF='$AREIA/nao_existe.conf'; debkit_smbconf_editar mais_comentario igual_efetivo")"

caso "restaurar sem edição trocada não faz nada"
smb_novo; md5_antes=$(md5sum < "$AREIA/smb.conf")
contem "RC=0" "$(g "DEBKIT_SMB_TROCADO=0; DEBKIT_SMB_BACKUP=/nao/existe; debkit_smbconf_restaurar; echo RC=\$?")"
igual "$md5_antes" "$(md5sum < "$AREIA/smb.conf")"

# ════════════════════════════════════════════════════════════════════════════
# "include" antigo (servidores preparados por versões anteriores)
# ════════════════════════════════════════════════════════════════════════════
MARCA="# debkit - Gerenciador Samba: compartilhamentos do debkit (não remova esta linha)"
# Monta o smb.conf como a versão antiga deixava: original + linha em branco
# + marca + include. $1 = caminho do include; $2 = original sem \n final
antigo() {
    local arq="${1:-$AREIA/debkit-shares.conf}"
    if [ -n "${2:-}" ]; then printf '[global]\n   workgroup = TESTE' > "$AREIA/smb.original"
    else printf '%b' "$SMB_MIN" > "$AREIA/smb.original"; fi
    cp "$AREIA/smb.original" "$AREIA/smb.conf"
    [ -n "$(tail -c 1 "$AREIA/smb.conf")" ] && echo >> "$AREIA/smb.conf"
    printf '\n%s\ninclude = %s\n' "$MARCA" "$arq" >> "$AREIA/smb.conf"
    chmod 644 "$AREIA/smb.conf"
    cp "$AREIA/smb.conf" "$AREIA/smb.antigo"
    rm -rf "$AREIA/conf-bkp" "$AREIA/backups"; : > "$AREIA/reloads"
}
# Arquivo de compartilhamentos como a versão antiga criava
shares_antigo() {
    local arq="${1:-$AREIA/debkit-shares.conf}"
    mkdir -p "$(dirname "$arq")"
    printf '# Compartilhamentos gerenciados pelo debkit (Gerenciador Samba).\n# NÃO edite à mão: use o debkit. Este arquivo é incluído pelo\n# %s (linha "include = %s").\n' "$AREIA/smb.conf" "$arq" > "$arq"
    chmod 644 "$arq"
}
verif_plano() { g "debkit_verificar_ambiente >/dev/null; printf '%s\n' \"\${DEBKIT_VERIF[@]}\" | grep '^samba'; debkit_montar_plano; echo \"PLANO=\${DEBKIT_PLANO[*]}\""; }
migrar() { g "debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(${1:-samba_include_antigo}); ${2:-} debkit_executar_plano; echo RC=\$?"; }

caso "include antigo: detectado e oferecido na preparação"
antigo; shares_antigo
saida=$(verif_plano)
contem "ainda tem a linha antiga \"include = $AREIA/debkit-shares.conf\"" "$saida"
contem "samba_include_antigo" "$(grep '^PLANO=' <<< "$saida")"
contem "Remover do $AREIA/smb.conf a linha antiga" "$(g "debkit_verificar_ambiente >/dev/null; debkit_montar_plano; debkit_mostrar_plano")" "descrição no plano"

caso "include antigo: removido - smb.conf volta a ser o original"
saida=$(migrar)
contem "RC=0" "$saida"
verdadeiro "smb.conf idêntico ao de antes da versão antiga" cmp -s "$AREIA/smb.original" "$AREIA/smb.conf"
verdadeiro "arquivo antigo removido" test ! -e "$AREIA/debkit-shares.conf"
verdadeiro "backup do arquivo antigo em BACKUP_DIR" test -n "$(find "$AREIA/backups" -name 'debkit-shares.conf.*')"
verdadeiro "backup do smb.conf (com o include) em conf-bkp" cmp -s "$AREIA/smb.antigo" "$(find "$AREIA/conf-bkp" -name 'smb.conf.*' | head -1)"
igual 1 "$(grep -c reload "$AREIA/reloads")" "Samba recarregado 1 vez"
contem "acao=samba_include_antigo resultado=ok" "$(cat "$AREIA/debkit.log")" "auditoria"
caso "include antigo: idempotente"
saida=$(verif_plano)
nao_contem "linha antiga" "$saida"; nao_contem "samba_include_antigo" "$saida"

caso "include antigo: smb.conf original sem quebra de linha no final"
antigo "" sem_quebra; shares_antigo
contem "RC=0" "$(migrar)"
igual "$(cat "$AREIA/smb.original")" "$(cat "$AREIA/smb.conf")" "conteúdo original"
nao_contem "$MARCA" "$(cat "$AREIA/smb.conf")"

caso "include antigo: arquivo antigo já não existe - só tira a linha"
antigo; rm -f "$AREIA/debkit-shares.conf"
contem "samba_include_antigo" "$(verif_plano | grep '^PLANO=')"
contem "RC=0" "$(migrar)"
verdadeiro "smb.conf original" cmp -s "$AREIA/smb.original" "$AREIA/smb.conf"

caso "include antigo: arquivo com compartilhamentos - só avisa, nada muda"
antigo; shares_antigo; printf '\n[extra]\n   path = /tmp\n' >> "$AREIA/debkit-shares.conf"
cp "$AREIA/debkit-shares.conf" "$AREIA/shares.antes"
saida=$(verif_plano)
contem "esse arquivo tem conteúdo: mova os compartilhamentos" "$saida"
nao_contem "samba_include_antigo" "$(grep '^PLANO=' <<< "$saida")"
contem "RC=1" "$(migrar)" "a ação, se chamada, recusa"
verdadeiro "smb.conf intacto" cmp -s "$AREIA/smb.antigo" "$AREIA/smb.conf"
verdadeiro "arquivo intacto" cmp -s "$AREIA/shares.antes" "$AREIA/debkit-shares.conf"

caso "include antigo: arquivo sem o cabeçalho do debkit - tira a linha, mantém o arquivo"
antigo; printf '# arquivo de outra pessoa\n' > "$AREIA/debkit-shares.conf"
contem "RC=0" "$(migrar)"
verdadeiro "smb.conf original" cmp -s "$AREIA/smb.original" "$AREIA/smb.conf"
verdadeiro "arquivo mantido" test -f "$AREIA/debkit-shares.conf"

caso "include antigo: arquivo em OUTRA pasta (ex: o real /etc/samba) - tira a linha, nunca apaga o arquivo"
antigo "$AREIA/outra/debkit-shares.conf"; shares_antigo "$AREIA/outra/debkit-shares.conf"
contem "RC=0" "$(migrar)"
verdadeiro "smb.conf original" cmp -s "$AREIA/smb.original" "$AREIA/smb.conf"
verdadeiro "arquivo da outra pasta mantido" test -f "$AREIA/outra/debkit-shares.conf"
# Repetição do incidente da 1.0: a cópia da areia apontando para o arquivo
# REAL. O smb.conf da areia muda; o arquivo real nunca (real_intacto confere)
antigo "/etc/samba/debkit-shares.conf"
contem "RC=0" "$(migrar)" "include para o arquivo real: tira a linha da areia"
verdadeiro "smb.conf da areia original" cmp -s "$AREIA/smb.original" "$AREIA/smb.conf"

caso "include sem a marca do debkit (do administrador) - não é mexido"
printf '%b' "$SMB_MIN" > "$AREIA/smb.conf"; printf '\ninclude = %s\n' "$AREIA/debkit-shares.conf" >> "$AREIA/smb.conf"
shares_antigo
saida=$(verif_plano)
nao_contem "linha antiga" "$saida"; nao_contem "samba_include_antigo" "$saida"

caso "include antigo: duas marcas (caminhos diferentes) - a conferência recusa, nada muda"
antigo; shares_antigo; printf '\n%s\ninclude = %s\n' "$MARCA" "$AREIA/outro.conf" >> "$AREIA/smb.conf"
printf '# nada\n' > "$AREIA/outro.conf"; cp "$AREIA/smb.conf" "$AREIA/smb.antigo"
saida=$(migrar)
contem "RC=1" "$saida"; contem "mais do que o pretendido" "$saida"
verdadeiro "smb.conf intacto" cmp -s "$AREIA/smb.antigo" "$AREIA/smb.conf"
verdadeiro "arquivo antigo intacto" test -f "$AREIA/debkit-shares.conf"

caso "include antigo: falha num passo seguinte - desfaz (smb.conf e arquivo de volta)"
antigo; shares_antigo; cp "$AREIA/debkit-shares.conf" "$AREIA/shares.antes"
saida=$(migrar "samba_include_antigo grupo" "groupadd() { return 1; };")
contem "RC=1" "$saida"; contem "Desfazendo" "$saida"; contem "restaurado do backup" "$saida"
verdadeiro "smb.conf de volta (com o include)" cmp -s "$AREIA/smb.antigo" "$AREIA/smb.conf"
verdadeiro "arquivo antigo de volta" cmp -s "$AREIA/shares.antes" "$AREIA/debkit-shares.conf"
igual 644 "$(stat -c %a "$AREIA/debkit-shares.conf")" "com 644"
igual 644 "$(stat -c %a "$AREIA/smb.conf")" "smb.conf com 644"
contem "acao=samba_include_antigo resultado=desfeito" "$(cat "$AREIA/debkit.log")"

caso "include antigo: --preparar pela linha de comando"
antigo; shares_antigo; rm -f "$AREIA/debkit.log"
saida=$(printf 's\n' | bash "$DEBKIT" --preparar 2>&1); cod=$?
igual 0 "$cod"; contem "Ambiente preparado com sucesso" "$saida"
verdadeiro "smb.conf original" cmp -s "$AREIA/smb.original" "$AREIA/smb.conf"
verdadeiro "arquivo antigo removido" test ! -e "$AREIA/debkit-shares.conf"

# ════════════════════════════════════════════════════════════════════════════
# Chaves antigas no debkit.conf (a preparação tira as linhas)
# ════════════════════════════════════════════════════════════════════════════
CONF_T="$AREIA/ct/debkit.conf"
# debkit.conf da areia + comentários + valor próprio + chaves antigas (com
# espaços, repetida). "esperado" = o mesmo arquivo sem as linhas antigas.
conf_antiga() {
    mkdir -p "$AREIA/ct"
    { echo "# meu comentário"; echo "# SHARES_CONF=/comentado (fica)"; cat "$AREIA/debkit.conf"
      echo "SENHA_MIN=7"; echo "  PREFIXO_GRUPO = debkit_"; echo "SHARES_CONF=/etc/samba/debkit-shares.conf"
      echo "SHARES_CONF=/de/novo"; } > "$CONF_T"
    chmod 640 "$CONF_T"
    grep -vE '^[[:space:]]*(PREFIXO_GRUPO|SHARES_CONF)[[:space:]]*=' "$CONF_T" > "$AREIA/ct/esperado"
    cp -p "$CONF_T" "$AREIA/ct/antigo"
    rm -rf "$AREIA/backups"
}
gc() { DEBKIT_CONF_ARQUIVO="$CONF_T" g "$1"; }
sem_temp_conf() { [ -z "$(find "$AREIA/ct" -name '.debkit.conf.*')" ]; }

caso "chaves antigas: oferecido na preparação"
conf_antiga
saida=$(gc "debkit_verificar_ambiente >/dev/null; debkit_montar_plano; echo \"PLANO=\${DEBKIT_PLANO[*]}\"; debkit_mostrar_plano")
contem "conf_obsoletas" "$(grep '^PLANO=' <<< "$saida")"
contem "Remover do $CONF_T as chaves que não são mais usadas: PREFIXO_GRUPO, SHARES_CONF" "$saida" "descrição (sem repetir, na ordem do arquivo)"

caso "chaves antigas: removidas, o resto do arquivo fica igual"
saida=$(gc "debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(conf_obsoletas); debkit_executar_plano; echo RC=\$?; echo \"AV=[\$DEBKIT_CONF_AVISOS] SENHA=\$DEBKIT_SENHA_MIN\"")
contem "RC=0" "$saida"
verdadeiro "arquivo = original sem as linhas antigas (comentários e valores mantidos)" cmp -s "$AREIA/ct/esperado" "$CONF_T"
contem "# SHARES_CONF=/comentado (fica)" "$(cat "$CONF_T")" "comentário com o nome da chave fica"
igual "640 0" "$(stat -c '%a %u' "$CONF_T")" "dono e permissões mantidos"
verdadeiro "backup do original em BACKUP_DIR" cmp -s "$AREIA/ct/antigo" "$(find "$AREIA/backups" -name 'debkit.conf.*' | head -1)"
contem "AV=[] SENHA=7" "$saida" "configuração recarregada, sem avisos"
verdadeiro "nenhum temporário deixado" sem_temp_conf
contem "acao=conf_obsoletas resultado=ok" "$(cat "$AREIA/debkit.log")" "auditoria"
caso "chaves antigas: idempotente"
nao_contem "conf_obsoletas" "$(gc "debkit_verificar_ambiente >/dev/null; debkit_montar_plano; echo \"PLANO=\${DEBKIT_PLANO[*]}\"")"

caso "chaves antigas: falha ao gravar - nada muda"
conf_antiga
contem "RC=1" "$(gc "mv() { return 1; }; DEBKIT_PLANO=(conf_obsoletas); debkit_executar_plano; echo RC=\$?")"
verdadeiro "arquivo intacto" cmp -s "$AREIA/ct/antigo" "$CONF_T"
verdadeiro "nenhum temporário deixado" sem_temp_conf

caso "chaves antigas: conferência recusa se outro valor mudaria"
conf_antiga
# defeito simulado: o filtro tiraria também a linha SENHA_MIN
saida=$(gc "debkit_conf_linha_obsoleta() { [[ \"\$1\" =~ ^[[:space:]]*(PREFIXO_GRUPO|SHARES_CONF|SENHA_MIN)[[:space:]]*= ]]; }; DEBKIT_PLANO=(conf_obsoletas); debkit_executar_plano; echo RC=\$?")
contem "RC=1" "$saida"; contem "mudaria em outros valores" "$saida"
verdadeiro "arquivo intacto" cmp -s "$AREIA/ct/antigo" "$CONF_T"
verdadeiro "nenhum temporário deixado" sem_temp_conf

caso "chaves antigas: falha num passo seguinte - arquivo de volta"
conf_antiga
saida=$(gc "groupadd() { return 1; }; getent() { [ \"\$1\" == group ] && return 2; command getent \"\$@\"; }; DEBKIT_PLANO=(conf_obsoletas grupo); debkit_executar_plano; echo RC=\$?")
contem "RC=1" "$saida"; contem "Desfazendo" "$saida"
verdadeiro "arquivo de volta (com as chaves antigas)" cmp -s "$AREIA/ct/antigo" "$CONF_T"
igual "640 0" "$(stat -c '%a %u' "$CONF_T")" "dono e permissões mantidos"

caso "chaves antigas: sem elas, nada no plano"
conf_antiga; cp "$AREIA/ct/esperado" "$CONF_T"
nao_contem "conf_obsoletas" "$(gc "debkit_verificar_ambiente >/dev/null; debkit_montar_plano; echo \"PLANO=\${DEBKIT_PLANO[*]}\"")"

caso "chaves antigas: --preparar pela linha de comando tira o aviso"
cp "$AREIA/debkit.conf" "$AREIA/debkit.conf.limpo"
printf 'PREFIXO_GRUPO=debkit_\nSHARES_CONF=/etc/samba/debkit-shares.conf\n' >> "$AREIA/debkit.conf"
contem "não é mais usada" "$(bash "$DEBKIT" --verificar 2>&1)" "antes: aviso"
saida=$(printf 's\n' | bash "$DEBKIT" --preparar 2>&1); cod=$?
igual 0 "$cod"; contem "Ambiente preparado com sucesso" "$saida"
nao_contem "não é mais usada" "$(bash "$DEBKIT" --verificar 2>&1)" "depois: sem aviso"
verdadeiro "debkit.conf = o de antes das chaves antigas" cmp -s "$AREIA/debkit.conf.limpo" "$AREIA/debkit.conf"

# ── Limpeza ──────────────────────────────────────────────────────────────────
getent group "$GRUPO_TESTE" >/dev/null && groupdel "$GRUPO_TESTE"
real_intacto

resumo
