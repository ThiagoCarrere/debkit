#!/usr/bin/env bash
# Testes da tarefa 0.1 - esqueleto: linha de comando, configuração,
# catálogo de mensagens, menu, trava, auditoria e limpeza.
source "$(dirname "$0")/lib.sh"
caixa_de_areia

# ── Qualidade do código ──────────────────────────────────────────────────────
caso "sintaxe"
verdadeiro "bash -n" bash -n "$GSB"
caso "shellcheck"
if command -v shellcheck >/dev/null; then
    verdadeiro "sem avisos" shellcheck "$GSB"
else
    echo "  (shellcheck não instalado: pulado)"
fi

# ── Linha de comando ─────────────────────────────────────────────────────────
caso "executado com sh (não bash)"
saida=$(sh "$GSB" --versao 2>&1); cod=$?
contem "precisa do bash" "$saida"; igual 1 "$cod" "código 1"

caso "--versao / -v"
igual "gsb 0.1.0-dev" "$(bash "$GSB" --versao)"
igual "gsb 0.1.0-dev" "$(bash "$GSB" -v)"

caso "--ajuda em pt_BR e en"
contem "Uso: gsb" "$(bash "$GSB" --ajuda)"
contem "$AREIA/gsb.conf" "$(bash "$GSB" --ajuda)" "mostra o arquivo de configuração"
contem "Usage: gsb" "$(GSB_IDIOMA=en bash "$GSB" --help)"

caso "opção desconhecida"
saida=$(bash "$GSB" --xyz 2>&1); cod=$?
contem "Opção desconhecida: '--xyz'" "$saida"; igual 2 "$cod" "código 2"

caso "sem root"
saida=$(setpriv --reuid=65534 --regid=65534 --clear-groups bash "$GSB" 2>&1); cod=$?
contem "precisa ser executado como root" "$saida"; igual 1 "$cod" "menu recusado, código 1"
saida=$(setpriv --reuid=65534 --regid=65534 --clear-groups bash "$GSB" --ajuda 2>&1); cod=$?
contem "Uso: gsb" "$saida" "ajuda funciona sem root"; igual 0 "$cod"

caso "source não executa nada"
saida=$(bash -c "source '$GSB'; echo carregou; declare -F t >/dev/null && echo tem_t" 2>&1)
igual "carregou"$'\n'"tem_t" "$saida"

# ── Configuração ─────────────────────────────────────────────────────────────
conf() { printf '%b' "$1" > "$AREIA/c.conf"; chmod "${2:-644}" "$AREIA/c.conf"; }
# carregar '<expressão com variáveis>' -> "rc=<código> <expressão avaliada>" + erros/avisos
carregar() { bash -c "source '$GSB'; gsb_conf_carregar '$AREIA/c.conf'; rc=\$?; eval \"echo rc=\$rc \$1\"; printf 'E:%s\nA:%s\n' \"\$GSB_CONF_ERROS\" \"\$GSB_CONF_AVISOS\"" _ "$1"; }

caso "configuração ausente usa padrões"
saida=$(bash -c "source '$GSB'; gsb_conf_carregar /nao/existe.conf; echo \"rc=\$? \$GSB_SENHA_MIN \$GSB_GRUPO_USUARIOS \$GSB_SMB_CONF\"")
igual "rc=0 4 gsb_usuarios /etc/samba/smb.conf" "$saida"

caso "valores válidos (aspas, espaços, comentários, CRLF, sem \\\\n final)"
conf '# comentário\n\n  SENHA_MIN = 8  \nIDIOMA="en"\r\nGRUPO_USUARIOS='"'"'meu_grupo'"'"'\nLOG=/var/log/x.log'
saida=$(carregar '$GSB_SENHA_MIN $GSB_IDIOMA $GSB_GRUPO_USUARIOS $GSB_LOG')
contem "rc=0 8 en meu_grupo /var/log/x.log" "$saida"

caso "valores inválidos são recusados com o número da linha"
conf 'SENHA_MIN=0\nSENHA_MIN=abc\nIDIOMA=fr\nGRUPO_USUARIOS=Maiusc\nLOG=relativo.log\nLOG=/var/../etc/x\nSENHA_MIN=4 # comentário na linha'
saida=$(carregar '')
contem "rc=1" "$saida" "rc=1"
for n in 1 2 3 4 5 6 7; do contem "linha $n: valor inválido" "$saida" "linha $n"; done

caso "tentativa de injetar comando NÃO é executada"
rm -f /tmp/gsb_injecao_teste
conf 'LOG=$(touch /tmp/gsb_injecao_teste)\nIDIOMA=en; touch /tmp/gsb_injecao_teste\n`touch /tmp/gsb_injecao_teste`'
saida=$(carregar '')
contem "rc=1" "$saida" "recusado"
verdadeiro "nenhum comando executado" test ! -e /tmp/gsb_injecao_teste

caso "chave desconhecida = aviso (não impede)"
conf 'CHAVE_NOVA=1\nSENHA_MIN=6'
saida=$(carregar '$GSB_SENHA_MIN')
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
conf 'SENHA_MIN=6' 644; chown 65534 "$AREIA/c.conf"
contem "precisa pertencer ao root" "$(carregar '')" "dono não-root"
chown 0 "$AREIA/c.conf"

caso "configuração inválida impede abrir o menu, mas não a ajuda"
cp "$AREIA/gsb.conf" "$AREIA/gsb.conf.bom"; echo "SENHA_MIN=zero" >> "$AREIA/gsb.conf"
saida=$(bash "$GSB" 2>&1 </dev/null); cod=$?
contem "Configuração inválida" "$saida"; igual 1 "$cod" "código 1"
igual 0 "$(bash "$GSB" --ajuda >/dev/null 2>&1; echo $?)" "--ajuda continua funcionando"
cp "$AREIA/gsb.conf.bom" "$AREIA/gsb.conf"

# ── Catálogo de mensagens ────────────────────────────────────────────────────
caso "catálogo pt_BR e en com as mesmas chaves"
faltas=$(bash -c "source '$GSB'; for k in \"\${!MSG_pt_BR[@]}\"; do [ -n \"\${MSG_en[\$k]+x}\" ] || echo \"en sem \$k\"; done; for k in \"\${!MSG_en[@]}\"; do [ -n \"\${MSG_pt_BR[\$k]+x}\" ] || echo \"pt sem \$k\"; done")
igual "" "$faltas"

caso "t(): idioma, reserva em pt_BR, chave inexistente e % nos argumentos"
igual "Opção inválida: 'x'" "$(bash -c "source '$GSB'; GSB_IDIOMA=pt_BR; t geral.opcao_invalida x")"
igual "Invalid option: 'x'" "$(bash -c "source '$GSB'; GSB_IDIOMA=en; t geral.opcao_invalida x")"
igual "só em pt" "$(bash -c "source '$GSB'; MSG_pt_BR[teste.so_pt]='só em pt'; GSB_IDIOMA=en; t teste.so_pt")"
igual "chave.que.nao.existe" "$(bash -c "source '$GSB'; t chave.que.nao.existe")"
igual "Opção inválida: '100%s %d'" "$(bash -c "source '$GSB'; t geral.opcao_invalida '100%s %d'")"

# ── Menu ─────────────────────────────────────────────────────────────────────
caso "menu: abrir, opção inválida, Enter vazio e sair"
saida=$(pty 0.6 "bash $GSB" "" 7 "" 0)
contem "gsb - Gerenciador Samba" "$saida"; contem "Opção inválida: '7'" "$saida"
nao_contem "Opção inválida: ''" "$saida" "Enter vazio não é erro"
caso "menu em inglês"
contem "gsb - Samba Manager" "$(pty 0.6 "env GSB_IDIOMA=en bash $GSB" 0)"

caso "fim da entrada (Ctrl+D) encerra sem travar"
printf '' | timeout 10 bash "$GSB" >/dev/null 2>&1; igual 0 "$?" "código 0"
printf '7\n' | timeout 10 bash "$GSB" >/dev/null 2>&1; igual 0 "$?" "após opção inválida"

# ── Auditoria ────────────────────────────────────────────────────────────────
caso "auditoria registra início e fim (saída normal, Ctrl+D e Ctrl+C)"
: > "$AREIA/gsb.log"
pty 0.6 "bash $GSB" 0 >/dev/null
printf '' | timeout 10 bash "$GSB" >/dev/null 2>&1
timeout --preserve-status -s INT 2 bash "$GSB" < <(sleep 5) >/dev/null 2>&1; cod=$?
igual 130 "$cod" "Ctrl+C sai com 130"
log=$(cat "$AREIA/gsb.log")
igual 3 "$(grep -c ' sessao_inicio v0.1.0-dev' <<< "$log")" "3 inícios"
contem "sessao_fim motivo=normal" "$log"
contem "sessao_fim motivo=fim_da_entrada" "$log"
contem "sessao_fim motivo=interrompida" "$log"
igual 640 "$(stat -c %a "$AREIA/gsb.log" 2>/dev/null || echo ausente)" "log criado com 640"
: > "$AREIA/gsb.log"; rm -f "$AREIA/gsb.log"
bash -c "source '$GSB'; GSB_LOG='$AREIA/gsb.log'; gsb_auditar teste 'a'"
igual 640 "$(stat -c %a "$AREIA/gsb.log")" "log novo criado com 640"

caso "auditoria: quebra de linha não forja linhas falsas"
bash -c "source '$GSB'; GSB_LOG='$AREIA/gsb.log'; gsb_auditar 'acao
falsa' \$'detalhe\n2026-01-01 root[1] linha_forjada'"
igual 2 "$(wc -l < "$AREIA/gsb.log")" "continua 1 linha por registro"
contem "acao_falsa detalhe 2026-01-01" "$(tail -1 "$AREIA/gsb.log")"

caso "auditoria registra o usuário real (sudo)"
bash -c "source '$GSB'; GSB_LOG='$AREIA/gsb.log'; SUDO_USER=fulano gsb_auditar teste x"
contem " fulano[" "$(tail -1 "$AREIA/gsb.log")"

caso "auditoria com log impossível de gravar retorna erro"
igual 1 "$(bash -c "source '$GSB'; GSB_LOG=/proc/nao_pode/gsb.log; gsb_auditar teste x; echo \$?")"

# ── Trava ────────────────────────────────────────────────────────────────────
caso "trava: segunda sessão é recusada mostrando o PID da primeira"
( sleep 6 | timeout 10 bash "$GSB" >/dev/null 2>&1 ) &
sleep 1.5
pid1=$(cat "$AREIA/gsb.lock" 2>/dev/null)
saida=$(printf '0\n' | timeout 10 bash "$GSB" 2>&1); cod=$?
contem "já está em uso por outra sessão (PID $pid1)" "$saida"; igual 1 "$cod" "código 1"
wait
saida=$(printf '0\n' | timeout 10 bash "$GSB" 2>&1); cod=$?
igual 0 "$cod" "liberada quando a primeira termina"

caso "trava em local impossível"
sed -i "s#^TRAVA=.*#TRAVA=/proc/nao_pode/gsb.lock#" "$AREIA/gsb.conf"
saida=$(printf '0\n' | timeout 10 bash "$GSB" 2>&1); cod=$?
contem "Não foi possível criar o arquivo de trava" "$saida"; igual 1 "$cod"
cp "$AREIA/gsb.conf.bom" "$AREIA/gsb.conf"

# ── Temporários ──────────────────────────────────────────────────────────────
caso "temporários: 600 e apagados ao sair (normal e Ctrl+C)"
saida=$(bash -c "source '$GSB'; trap gsb_ao_sair EXIT; a=\$(gsb_temp); GSB_TEMPORARIOS+=(\"\$a\"); stat -c %a \"\$a\"; echo \"\$a\"")
perm=$(head -1 <<< "$saida"); arq=$(tail -1 <<< "$saida")
igual 600 "$perm" "criado com 600"
verdadeiro "apagado na saída normal" test ! -e "$arq"
bash -c "source '$GSB'; trap gsb_ao_sair EXIT; trap 'exit 130' INT; a=\$(gsb_temp); GSB_TEMPORARIOS+=(\"\$a\"); echo \"\$a\" > '$AREIA/tmpnome'; sleep 5" &
sleep 1; kill -INT $! 2>/dev/null; wait $! 2>/dev/null
verdadeiro "apagado no Ctrl+C" test ! -e "$(cat "$AREIA/tmpnome")"

# ── Nada fora da caixa de areia ──────────────────────────────────────────────
caso "testes não tocaram no log/trava reais"
verdadeiro "/var/log/gsb.log não existe" test ! -e /var/log/gsb.log
verdadeiro "/run/gsb.lock não existe" test ! -e /run/gsb.lock

resumo
