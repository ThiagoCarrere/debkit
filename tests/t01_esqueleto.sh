#!/usr/bin/env bash
# Testes da tarefa 0.1 - esqueleto: linha de comando, configuração,
# catálogo de mensagens, menu, trava, auditoria e limpeza.
source "$(dirname "$0")/lib.sh"
sandbox

# ── Qualidade do código ──────────────────────────────────────────────────────
caso "sintaxe"
for arq in "$DEBKIT" "$REPO"/install.sh "$REPO"/lib/*.sh "$REPO"/modulos/*.sh; do
    verdadeiro "bash -n ${arq#"$REPO"/}" bash -n "$arq"
done
caso "shellcheck"
if command -v shellcheck >/dev/null; then
    verdadeiro "sem avisos (ponto de entrada, núcleo e módulos)" shellcheck -x "$DEBKIT" "$REPO"/lib/*.sh "$REPO"/modulos/*.sh
    verdadeiro "sem avisos (install.sh)" shellcheck -x "$REPO"/install.sh
else
    echo "  (shellcheck não instalado: pulado)"
fi

# ── Linha de comando ─────────────────────────────────────────────────────────
caso "executado com sh (não bash)"
saida=$(sh "$DEBKIT" --versao 2>&1); cod=$?
contem "precisa do bash" "$saida"; igual 1 "$cod" "código 1"

caso "--versao / -v"
igual "debkit 0.1.0-dev" "$(bash "$DEBKIT" --versao)"
igual "debkit 0.1.0-dev" "$(bash "$DEBKIT" -v)"

caso "--ajuda em pt_BR e en"
contem "Uso: debkit" "$(bash "$DEBKIT" --ajuda)"
contem "$SANDBOX/debkit.conf" "$(bash "$DEBKIT" --ajuda)" "mostra o arquivo de configuração"
contem "Usage: debkit" "$(DEBKIT_IDIOMA=en bash "$DEBKIT" --help)"

caso "opção desconhecida"
saida=$(bash "$DEBKIT" --xyz 2>&1); cod=$?
contem "Opção desconhecida: '--xyz'" "$saida"; igual 2 "$cod" "código 2"

caso "sem root"
saida=$(setpriv --reuid=65534 --regid=65534 --clear-groups bash "$DEBKIT" 2>&1); cod=$?
contem "precisa ser executado como root" "$saida"; igual 1 "$cod" "menu recusado, código 1"
saida=$(setpriv --reuid=65534 --regid=65534 --clear-groups bash "$DEBKIT" --ajuda 2>&1); cod=$?
contem "Uso: debkit" "$saida" "ajuda funciona sem root"; igual 0 "$cod"

caso "source não executa nada"
saida=$(bash -c "source '$DEBKIT'; echo carregou; declare -F t >/dev/null && echo tem_t" 2>&1)
igual "carregou"$'\n'"tem_t" "$saida"

# ── Configuração ─────────────────────────────────────────────────────────────
conf() { printf '%b' "$1" > "$SANDBOX/c.conf"; chmod "${2:-644}" "$SANDBOX/c.conf"; }
# carregar '<expressão com variáveis>' -> "rc=<código> <expressão avaliada>" + erros/avisos
carregar() { bash -c "source '$DEBKIT'; debkit_conf_carregar '$SANDBOX/c.conf'; rc=\$?; eval \"echo rc=\$rc \$1\"; printf 'E:%s\nA:%s\n' \"\$DEBKIT_CONF_ERROS\" \"\$DEBKIT_CONF_AVISOS\"" _ "$1"; }

caso "configuração ausente usa padrões"
saida=$(bash -c "source '$DEBKIT'; debkit_conf_carregar /nao/existe.conf; echo \"rc=\$? \$DEBKIT_SENHA_MIN \$DEBKIT_GRUPO_USUARIOS \$DEBKIT_SMB_CONF\"")
igual "rc=0 4 debkit_usuarios /etc/samba/smb.conf" "$saida"

caso "valores válidos (aspas, espaços, comentários, CRLF, sem \\\\n final)"
conf '# comentário\n\n  SENHA_MIN = 8  \nIDIOMA="en"\r\nGRUPO_USUARIOS='"'"'meu_grupo'"'"'\nLOG=/var/log/x.log'
saida=$(carregar '$DEBKIT_SENHA_MIN $DEBKIT_IDIOMA $DEBKIT_GRUPO_USUARIOS $DEBKIT_LOG')
contem "rc=0 8 en meu_grupo /var/log/x.log" "$saida"

caso "valores inválidos são recusados com o número da linha"
conf 'SENHA_MIN=0\nSENHA_MIN=abc\nIDIOMA=fr\nGRUPO_USUARIOS=Maiusc\nLOG=relativo.log\nLOG=/var/../etc/x\nSENHA_MIN=4 # comentário na linha'
saida=$(carregar '')
contem "rc=1" "$saida" "rc=1"
for n in 1 2 3 4 5 6 7; do contem "linha $n: valor inválido" "$saida" "linha $n"; done

caso "letras acentuadas são recusadas em nomes e caminhos (o [a-z] do bash aceitaria em pt_BR)"
conf 'GRUPO_USUARIOS=usuários\nLOG=/var/log/débkit.log\nGRUPO_USUARIOS=Grupo'
saida=$(carregar '')
contem "rc=1" "$saida"
for n in 1 2 3; do contem "linha $n: valor inválido" "$saida" "linha $n"; done

caso "tentativa de injetar comando NÃO é executada"
rm -f /tmp/debkit_injecao_teste
conf 'LOG=$(touch /tmp/debkit_injecao_teste)\nIDIOMA=en; touch /tmp/debkit_injecao_teste\n`touch /tmp/debkit_injecao_teste`'
saida=$(carregar '')
contem "rc=1" "$saida" "recusado"
verdadeiro "nenhum comando executado" test ! -e /tmp/debkit_injecao_teste

caso "chave desconhecida = aviso (não impede)"
conf 'CHAVE_NOVA=1\nSENHA_MIN=6'
saida=$(carregar '$DEBKIT_SENHA_MIN')
contem "rc=0 6" "$saida"; contem "chave desconhecida 'CHAVE_NOVA'" "$saida"

caso "linha sem formato CHAVE=valor"
conf 'isso nao e configuracao'
contem "formato inválido" "$(carregar '')"

caso "permissões inseguras são recusadas"
conf 'SENHA_MIN=6' 666
contem "não ter escrita para grupo/outros" "$(carregar '')" "666"
conf 'SENHA_MIN=6' 664
contem "não ter escrita para grupo/outros" "$(carregar '')" "664"
conf 'SENHA_MIN=6' 600
contem "rc=0" "$(carregar '')" "600 aceito"
conf 'SENHA_MIN=6' 644; chown 65534 "$SANDBOX/c.conf"
contem "precisa pertencer ao root" "$(carregar '')" "dono não-root"
chown 0 "$SANDBOX/c.conf"

caso "configuração inválida impede abrir o menu, mas não a ajuda"
cp "$SANDBOX/debkit.conf" "$SANDBOX/debkit.conf.bom"; echo "SENHA_MIN=zero" >> "$SANDBOX/debkit.conf"
saida=$(bash "$DEBKIT" 2>&1 </dev/null); cod=$?
contem "Configuração inválida" "$saida"; igual 1 "$cod" "código 1"
igual 0 "$(bash "$DEBKIT" --ajuda >/dev/null 2>&1; echo $?)" "--ajuda continua funcionando"
cp "$SANDBOX/debkit.conf.bom" "$SANDBOX/debkit.conf"

# ── Catálogo de mensagens ────────────────────────────────────────────────────
caso "catálogo pt_BR e en com as mesmas chaves"
faltas=$(bash -c "source '$DEBKIT'; for k in \"\${!MSG_pt_BR[@]}\"; do [ -n \"\${MSG_en[\$k]+x}\" ] || echo \"en sem \$k\"; done; for k in \"\${!MSG_en[@]}\"; do [ -n \"\${MSG_pt_BR[\$k]+x}\" ] || echo \"pt sem \$k\"; done")
igual "" "$faltas"

caso "t(): idioma, reserva em pt_BR, chave inexistente e % nos argumentos"
igual "Opção inválida: 'x'" "$(bash -c "source '$DEBKIT'; DEBKIT_IDIOMA=pt_BR; t geral.opcao_invalida x")"
igual "Invalid option: 'x'" "$(bash -c "source '$DEBKIT'; DEBKIT_IDIOMA=en; t geral.opcao_invalida x")"
igual "só em pt" "$(bash -c "source '$DEBKIT'; MSG_pt_BR[teste.so_pt]='só em pt'; DEBKIT_IDIOMA=en; t teste.so_pt")"
igual "chave.que.nao.existe" "$(bash -c "source '$DEBKIT'; t chave.que.nao.existe")"
igual "Opção inválida: '100%s %d'" "$(bash -c "source '$DEBKIT'; t geral.opcao_invalida '100%s %d'")"

caso "idioma auto (o padrão): o do sistema, na ordem do gettext"
idi() { env -u LANGUAGE -u LC_ALL -u LC_MESSAGES "$@" bash -c "source '$DEBKIT'; debkit_conf_padroes; t geral.sair"; }
igual "auto" "$(bash -c "source '$DEBKIT'; debkit_conf_padroes; echo \$DEBKIT_IDIOMA")" "padrão auto"
igual "Sair" "$(idi LANG=pt_BR.UTF-8)" "LANG pt_BR"
igual "Sair" "$(idi LANG=pt_PT.UTF-8)" "LANG pt_PT"
igual "Exit" "$(idi LANG=en_US.UTF-8)" "LANG en_US"
igual "Exit" "$(idi LANG=C.UTF-8)" "LANG C.UTF-8"
igual "Exit" "$(idi LANG=de_DE.UTF-8)" "outro idioma: inglês"
igual "Exit" "$(idi -u LANG)" "sem LANG: inglês"
igual "Sair" "$(idi LANG=C.UTF-8 LANGUAGE=pt_BR:en)" "LANGUAGE vale"
igual "Exit" "$(idi LANG=C LANGUAGE=pt_BR)" "com o idioma C o LANGUAGE não vale (como no gettext)"
igual "Exit" "$(idi LANG=pt_BR.UTF-8 LC_MESSAGES=en_US.UTF-8)" "LC_MESSAGES antes do LANG"
igual "Sair" "$(idi LANG=en_US.UTF-8 LC_ALL=pt_BR.UTF-8 2>/dev/null)" "LC_ALL antes de tudo"
igual "Sair" "$(env -u LANGUAGE LANG=en_US.UTF-8 bash -c "source '$DEBKIT'; debkit_conf_padroes; DEBKIT_IDIOMA=pt_BR; t geral.sair")" "IDIOMA=pt_BR fixo ganha do sistema"
conf 'IDIOMA=auto'; contem "rc=0 auto" "$(carregar '$DEBKIT_IDIOMA')" "auto aceito no debkit.conf"
caso "toda chave citada no código existe no catálogo"
faltas=$(grep -ohE "\bt \"?[a-z]+\.[a-z0-9_]+\"?( |\)|$)" "$DEBKIT" "$REPO"/install.sh "$REPO"/lib/*.sh "$REPO"/modulos/*.sh \
    | sed -E 's/^t "?//; s/"?[ )]?$//' | sort -u | bash -c "source '$DEBKIT'; while read -r k; do [ -n \"\${MSG_pt_BR[\$k]+x}\" ] || echo \"falta \$k\"; done")
igual "" "$faltas"
caso "t(): argumentos a mais não repetem a frase"
igual "debkit 1" "$(bash -c "source '$DEBKIT'; DEBKIT_IDIOMA=pt_BR; t geral.versao 1 2 3")"

# ── Menu ─────────────────────────────────────────────────────────────────────
preparar_sandbox
caso "menu: abrir, opção inválida, Enter vazio e sair"
saida=$(pty 0.6 "bash $DEBKIT" "" 7 "" 0)
contem "debkit - administração de servidores Debian" "$saida"; contem "Opção inválida: '7'" "$saida"
nao_contem "Opção inválida: ''" "$saida" "Enter vazio não é erro"
caso "menu em inglês"
contem "debkit - Debian server administration" "$(pty 0.6 "env DEBKIT_IDIOMA=en bash $DEBKIT" 0)"

caso "fim da entrada (Ctrl+D) encerra sem travar"
printf '' | timeout 10 bash "$DEBKIT" >/dev/null 2>&1; igual 0 "$?" "código 0"
printf '7\n' | timeout 10 bash "$DEBKIT" >/dev/null 2>&1; igual 0 "$?" "após opção inválida"

# ── Auditoria ────────────────────────────────────────────────────────────────
caso "auditoria registra início e fim (saída normal, Ctrl+D e Ctrl+C)"
: > "$SANDBOX/debkit.log"
pty 0.6 "bash $DEBKIT" 0 >/dev/null
printf '' | timeout 10 bash "$DEBKIT" >/dev/null 2>&1
timeout --preserve-status -s INT 2 bash "$DEBKIT" < <(sleep 5) >/dev/null 2>&1; cod=$?
igual 130 "$cod" "Ctrl+C sai com 130"
log=$(cat "$SANDBOX/debkit.log")
igual 3 "$(grep -c ' sessao_inicio v0.1.0-dev' <<< "$log")" "3 inícios"
contem "sessao_fim motivo=normal" "$log"
contem "sessao_fim motivo=fim_da_entrada" "$log"
contem "sessao_fim motivo=interrompida" "$log"
igual 640 "$(stat -c %a "$SANDBOX/debkit.log" 2>/dev/null || echo ausente)" "log criado com 640"
: > "$SANDBOX/debkit.log"; rm -f "$SANDBOX/debkit.log"
bash -c "source '$DEBKIT'; DEBKIT_LOG='$SANDBOX/debkit.log'; DEBKIT_LOG_LOGROTATE='$SANDBOX/logrotate-debkit'; debkit_auditar teste 'a'"
igual 640 "$(stat -c %a "$SANDBOX/debkit.log")" "log novo criado com 640"

caso "auditoria: quebra de linha não forja linhas falsas"
bash -c "source '$DEBKIT'; DEBKIT_LOG='$SANDBOX/debkit.log'; DEBKIT_LOG_LOGROTATE='$SANDBOX/logrotate-debkit'; debkit_auditar 'acao
falsa' \$'detalhe\n2026-01-01 root[1] linha_forjada'"
igual 2 "$(wc -l < "$SANDBOX/debkit.log")" "continua 1 linha por registro"
contem "acao_falsa detalhe 2026-01-01" "$(tail -1 "$SANDBOX/debkit.log")"

caso "auditoria registra o usuário real (sudo)"
bash -c "source '$DEBKIT'; DEBKIT_LOG='$SANDBOX/debkit.log'; DEBKIT_LOG_LOGROTATE='$SANDBOX/logrotate-debkit'; SUDO_USER=fulano debkit_auditar teste x"
contem " fulano[" "$(tail -1 "$SANDBOX/debkit.log")"

caso "auditoria com log impossível de gravar retorna erro"
igual 1 "$(bash -c "source '$DEBKIT'; DEBKIT_LOG=/proc/nao_pode/debkit.log; debkit_auditar teste x; echo \$?")"

# ── Trava ────────────────────────────────────────────────────────────────────
caso "trava: segunda sessão é recusada mostrando o PID da primeira"
( sleep 6 | timeout 10 bash "$DEBKIT" >/dev/null 2>&1 ) &
sleep 1.5
pid1=$(cat "$SANDBOX/debkit.lock" 2>/dev/null)
saida=$(printf '0\n' | timeout 10 bash "$DEBKIT" 2>&1); cod=$?
contem "já está em uso por outra sessão (PID $pid1)" "$saida"; igual 1 "$cod" "código 1"
wait
saida=$(printf '0\n' | timeout 10 bash "$DEBKIT" 2>&1); cod=$?
igual 0 "$cod" "liberada quando a primeira termina"

caso "trava em local impossível"
sed -i "s#^TRAVA=.*#TRAVA=/proc/nao_pode/debkit.lock#" "$SANDBOX/debkit.conf"
saida=$(printf '0\n' | timeout 10 bash "$DEBKIT" 2>&1); cod=$?
contem "Não foi possível criar o arquivo de trava" "$saida"; igual 1 "$cod"
cp "$SANDBOX/debkit.conf.bom" "$SANDBOX/debkit.conf"

# ── Temporários ──────────────────────────────────────────────────────────────
caso "temporários: 600 e apagados ao sair (normal e Ctrl+C)"
saida=$(bash -c "source '$DEBKIT'; trap debkit_ao_sair EXIT; a=\$(debkit_temp); DEBKIT_TEMPORARIOS+=(\"\$a\"); stat -c %a \"\$a\"; echo \"\$a\"")
perm=$(head -1 <<< "$saida"); arq=$(tail -1 <<< "$saida")
igual 600 "$perm" "criado com 600"
verdadeiro "apagado na saída normal" test ! -e "$arq"
bash -c "source '$DEBKIT'; trap debkit_ao_sair EXIT; trap 'exit 130' INT; a=\$(debkit_temp); DEBKIT_TEMPORARIOS+=(\"\$a\"); echo \"\$a\" > '$SANDBOX/tmpnome'; sleep 5" &
sleep 1; kill -INT $! 2>/dev/null; wait $! 2>/dev/null
verdadeiro "apagado no Ctrl+C" test ! -e "$(cat "$SANDBOX/tmpnome")"

# ── Nada fora do sandbox ──────────────────────────────────────────────
real_intacto

resumo
