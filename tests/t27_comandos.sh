#!/usr/bin/env bash
# Testes da tarefa 4.2 - comandos diretos (debkit samba <grupo> <ação>;
# seção 3.9): as mesmas ações do menu, com as mesmas validações, resumo e
# confirmação (--sim responde), senhas pela entrada padrão, trava e
# auditoria de sessão nos que alteram, códigos de saída 0/1/2. Tudo no
# sandbox (usuários e grupos dkt_*, pastas em /srv/dkt-teste.*, apagados no
# fim); a prova real com o Samba de verdade está em t27b_comandos_real.sh.
source "$(dirname "$0")/lib.sh"
sandbox

if getent passwd | cut -d: -f1 | grep -q '^dkt_'; then echo "  já existem usuários dkt_* - abortando"; exit 1; fi
T=$(mktemp -d /srv/dkt-teste.XXXXXX); chmod 755 "$T"
limpar_tudo() {
    local x
    for x in $(getent passwd | cut -d: -f1 | grep '^dkt_'); do userdel "$x" >/dev/null 2>&1; done
    for x in $(getent group | cut -d: -f1 | grep '^dkt_'); do groupdel "$x" >/dev/null 2>&1; done
    [ -n "${PID_TRAVA:-}" ] && kill "$PID_TRAVA" 2>/dev/null
    rm -rf -- "${T:?}" "${SANDBOX:?}"
}
trap limpar_tudo EXIT

copiar_smb_conf "$SANDBOX/smb.conf"
# Só as seções padrão (os compartilhamentos de demonstração da VM não contam)
awk '/^[ \t]*\[/ { s = tolower($0); gsub(/[ \t\[\]]/, "", s); fora = (s != "global" && s != "homes" && s != "printers" && s != "print$") } !fora' \
    "$SANDBOX/smb.conf" > "$SANDBOX/smb.conf.novo" && cat "$SANDBOX/smb.conf.novo" > "$SANDBOX/smb.conf" && rm -f "$SANDBOX/smb.conf.novo"
preparar_sandbox
LOG() { cat "$SANDBOX/debkit.log" 2>/dev/null; }
param() { testparm -s --section-name="$1" --parameter-name="$2" "$SANDBOX/smb.conf" 2>/dev/null; }
# cli <argumentos...>: debkit samba ..., a entrada padrão vem de quem chama
cli() { bash "$DEBKIT" samba "$@" 2>&1; echo "RC=$?"; }
sem() { cli "$@" < /dev/null; }
SENHA='Cli#Senha1'
groupadd dkt_g1; groupadd dkt_g3

# ── Ajuda e uso ──────────────────────────────────────────────────────────────
caso "ajuda do módulo (com e sem --ajuda; sem root também)"
saida=$(sem --ajuda)
contem "Uso: debkit samba <grupo> <ação>" "$saida"; contem "usuario criar <login>" "$saida"; contem "diagnostico auditoria" "$saida"
contem "RC=0" "$saida"
contem "compartilhamento trocar-grupo" "$(sem)" "sem argumentos = ajuda"
saida=$(setpriv --reuid=65534 --regid=65534 --clear-groups bash "$DEBKIT" samba --ajuda 2>&1; echo "RC=$?")
contem "usuario listar" "$saida"; contem "RC=0" "$saida"
caso "ajuda geral cita os comandos diretos"
contem "debkit samba --ajuda" "$(bash "$DEBKIT" --ajuda)"
caso "sem root: comando recusado"
saida=$(setpriv --reuid=65534 --regid=65534 --clear-groups bash "$DEBKIT" samba usuario listar 2>&1; echo "RC=$?")
contem "precisa ser executado como root" "$saida"; contem "RC=1" "$saida"
caso "uso errado: código 2"
saida=$(bash "$DEBKIT" xyz 2>&1; echo "RC=$?"); contem "Opção desconhecida: 'xyz'" "$saida"; contem "RC=2" "$saida"
saida=$(sem usuario voar); contem "Comando desconhecido: 'usuario voar'" "$saida"; contem "RC=2" "$saida"
saida=$(sem '../x' y); contem "Comando desconhecido" "$saida"; contem "RC=2" "$saida"
saida=$(sem usuario listar --xyz); contem "Opção desconhecida: '--xyz'" "$saida"; contem "RC=2" "$saida"
saida=$(sem usuario criar dkt_c1 --nome); contem "Falta o valor de --nome" "$saida"; contem "RC=2" "$saida"
saida=$(sem usuario criar); contem "Uso incorreto: usuario criar <login>" "$saida"; contem "RC=2" "$saida"
saida=$(sem usuario criar dkt_c1 --tipo xx); contem "Tipo inválido: 'xx'" "$saida"; contem "RC=2" "$saida"
saida=$(sem usuario criar dkt_c1 --senha-linux-diferente); contem "só vale para --tipo servidor" "$saida"; contem "RC=2" "$saida"
saida=$(bash "$DEBKIT" --verificar --sim 2>&1; echo "RC=$?"); contem "só vale para --preparar" "$saida"; contem "RC=2" "$saida"
nao_contem "sessao_inicio" "$(LOG | grep -v 'preparar')" "uso errado não abre sessão"

# ── Usuários ─────────────────────────────────────────────────────────────────
caso "criar com --sim e a senha pela entrada padrão"
: > "$SANDBOX/debkit.log"
saida=$(printf '%s\n' "$SENHA" | cli usuario criar dkt_c1 --nome "Teste Um" --grupos dkt_g1 --sim)
contem "RC=0" "$saida"; contem "Login: dkt_c1" "$saida" "resumo"; contem "s (--sim)" "$saida" "a confirmação aparece respondida"
verdadeiro "usuário existe" id dkt_c1
igual "Teste Um" "$(getent passwd dkt_c1 | cut -d: -f5)"
contem "dkt_g1" "$(id -nG dkt_c1)"
verdadeiro "conta Samba (base do sandbox)" bash -c "pdbedit -s '$SANDBOX/smb.conf' -u dkt_c1"
contem "comando: samba usuario criar dkt_c1" "$(LOG)" "sessão auditada com o comando"
contem "sessao_fim motivo=normal" "$(LOG)"
nao_contem "$SENHA" "$(LOG)" "senha nunca no log"
caso "listar mostra o criado (só leitura: sem sessão no log)"
: > "$SANDBOX/debkit.log"
saida=$(sem usuario listar); contem "dkt_c1" "$saida"; contem "Teste Um" "$saida"; contem "RC=0" "$saida"
igual "" "$(LOG)" "nada no log"
caso "criar: confirmação respondida n pela entrada padrão cancela"
saida=$(printf '%s\nn\n' "$SENHA" | cli usuario criar dkt_c2)
contem "Cancelado. Nada foi feito." "$saida"; contem "RC=1" "$saida"
verdadeiro "não criado" bash -c '! id dkt_c2'
caso "criar: sem senha na entrada, senha curta, grupo que não existe, nome inválido"
saida=$(sem usuario criar dkt_c2 --sim); contem "Nenhuma senha na entrada padrão" "$saida"; contem "RC=1" "$saida"
saida=$(printf 'ab\n' | cli usuario criar dkt_c2 --sim); contem "pelo menos 4" "$saida"; contem "RC=1" "$saida"
saida=$(printf '%s\n' "$SENHA" | cli usuario criar dkt_c2 --grupos dkt_g1,dkt_nao --sim)
contem "'dkt_nao' não é um grupo comum" "$saida"; contem "RC=1" "$saida"
saida=$(printf '%s\n' "$SENHA" | cli usuario criar Dkt_C2 --sim); contem "RC=1" "$saida"
verdadeiro "nenhum criado" bash -c '! id dkt_c2 && ! id Dkt_C2'
caso "criar servidor com a senha do Linux diferente (duas linhas)"
saida=$(printf '%s\n%s\n' "$SENHA" 'Outra#Linux2' | cli usuario criar dkt_c2 --tipo servidor --senha-linux-diferente --sim)
contem "RC=0" "$saida"; contem "Senha do Linux: própria" "$saida"
igual "/bin/bash" "$(getent passwd dkt_c2 | cut -d: -f7)"
igual "P" "$(passwd -S dkt_c2 | awk '{print $2}')" "senha do Linux utilizável"
caso "criar: --pasta-pessoal sem a base definida explica como definir"
saida=$(printf '%s\n' "$SENHA" | cli usuario criar dkt_c4 --pasta-pessoal --sim)
contem "debkit samba pastas-pessoais --base" "$saida"; contem "RC=1" "$saida"; verdadeiro "não criado" bash -c '! id dkt_c4'
saida=$(sem pastas-pessoais); contem "ainda não foi definida" "$saida"; contem "RC=1" "$saida"

caso "senha: usuário de arquivos (só a do Samba); Linux recusado; duas opções = uso errado"
saida=$(printf 'Nova#Senha3\n' | cli usuario senha dkt_c1)
contem "só a senha do Samba é trocada" "$saida"; contem "RC=0" "$saida"
saida=$(printf 'Nova#Senha3\n' | cli usuario senha dkt_c1 --linux); contem "RC=1" "$saida"
saida=$(sem usuario senha dkt_c1 --samba --linux); contem "Use só uma de --samba, --linux e --ambas" "$saida"; contem "RC=2" "$saida"
saida=$(printf 'Nova#Senha3\n' | cli usuario senha dkt_nao_existe); contem "RC=1" "$saida"
caso "senha: servidor troca as duas por padrão"
saida=$(printf 'Duas#Senhas4\n' | cli usuario senha dkt_c2); contem "RC=0" "$saida"
contem "alvo=ambas resultado=ok" "$(LOG)"

caso "conferir: lista sem alterar (código 1) e cada item uma vez só"
useradd -M -s /usr/sbin/nologin -U dkt_c3; gpasswd -a dkt_c3 "$GRUPO_TESTE" >/dev/null
saida=$(sem usuario conferir)
contem "RC=1" "$saida"; contem "debkit samba usuario conferir --corrigir" "$saida"
igual "    - dkt_c3: usuário no Linux sem conta no Samba (não acessa as pastas)" "$(grep 'dkt_c3:' <<< "$saida")" "frase sem repetição"
# --corrigir percorre TODOS os usuários comuns do sistema (os reais aparecem
# no sandbox sem conta Samba): aqui só sem --sim e respondendo "não" a tudo.
# A correção de cada item tem testes próprios (t15).
caso "conferir --corrigir respondendo não a tudo: nada muda (código 1)"
saida=$(cli usuario conferir --corrigir < /dev/null)
contem "RC=1" "$saida"; contem "0 de " "$saida"
verdadeiro "dkt_c3 continua sem conta Samba" bash -c "! pdbedit -s '$SANDBOX/smb.conf' -u dkt_c3"

# ── Grupos ───────────────────────────────────────────────────────────────────
caso "grupo criar / membros / remover"
saida=$(sem grupo criar dkt_g2 --membros dkt_c1,dkt_c3 --sim); contem "RC=0" "$saida"
contem "dkt_c1" "$(getent group dkt_g2)"; contem "dkt_c3" "$(getent group dkt_g2)"
contem "dkt_g2" "$(sem grupo listar)"
saida=$(sem grupo membros dkt_g2); contem "Membros: dkt_c1, dkt_c3" "$saida"; contem "RC=0" "$saida"
saida=$(sem grupo membros dkt_g2 --remover dkt_c3 --adicionar dkt_c2 --sim); contem "RC=0" "$saida"
contem "Adicionar dkt_c2 e remover dkt_c3 do grupo dkt_g2?" "$saida"
igual "dkt_c1,dkt_c2" "$(getent group dkt_g2 | cut -d: -f4)"
saida=$(sem grupo membros dkt_g2 --adicionar dkt_nao --sim); contem "RC=1" "$saida"
saida=$(sem grupo criar dkt_g9 --membros dkt_nao --sim); contem "'dkt_nao' não é um usuário comum" "$saida"; contem "RC=1" "$saida"
verdadeiro "dkt_g9 não criado" bash -c '! getent group dkt_g9'
saida=$(sem grupo remover dkt_g2 --sim); contem "RC=0" "$saida"; verdadeiro "removido" bash -c '! getent group dkt_g2'
saida=$(sem grupo remover dkt_c1 --sim); contem "RC=1" "$saida" "grupo principal de alguém: recusado"
saida=$(sem grupo remover root --sim); contem "não é um grupo comum" "$saida"; contem "RC=1" "$saida"

# ── Compartilhamentos ────────────────────────────────────────────────────────
caso "compartilhamento criar: sem --grupo, sem base"
saida=$(sem compartilhamento criar dkt-s1 --sim); contem "Falta --grupo" "$saida"; contem "RC=2" "$saida"
saida=$(sem compartilhamento criar dkt-s1 --grupo dkt_g1 --sim); contem "use --base <pasta>" "$saida"; contem "RC=1" "$saida"
caso "compartilhamento criar com --base (a primeira vez) e listar"
saida=$(sem compartilhamento criar dkt-s1 --grupo dkt_g1 --base "$T/base" --descricao "Setor teste" --sim)
contem "RC=0" "$saida"; igual "@dkt_g1" "$(param dkt-s1 'valid users')"; igual "$T/base/dkt-s1" "$(param dkt-s1 path)"
contem "SHARES_BASE=$T/base" "$(cat "$SANDBOX/debkit.conf")"
contem "dkt-s1" "$(sem compartilhamento listar)"
caso "compartilhamento criar: pasta com conteúdo só ajusta com --ajustar"
mkdir "$T/base/cheia"; echo x > "$T/base/cheia/a.txt"; chmod 600 "$T/base/cheia/a.txt"
saida=$(sem compartilhamento criar dkt-s2 --grupo dkt_g1 --pasta "$T/base/cheia" --sim)
contem "RC=0" "$saida"; contem "debkit samba compartilhamento ajustar dkt-s2" "$saida"; igual "600" "$(stat -c %a "$T/base/cheia/a.txt")"
saida=$(sem compartilhamento ajustar dkt-s2 --sim); contem "RC=0" "$saida"
igual "dkt_g1" "$(stat -c %G "$T/base/cheia/a.txt")" "conteúdo do grupo depois de ajustar"
mkdir "$T/base/cheia2"; echo x > "$T/base/cheia2/b.txt"
saida=$(sem compartilhamento criar dkt-s3 --grupo dkt_g3 --pasta "$T/base/cheia2" --ajustar --sim)
contem "RC=0" "$saida"; igual "dkt_g3" "$(stat -c %G "$T/base/cheia2/b.txt")" "com --ajustar já ajusta"
caso "trocar-grupo, mesmo grupo e inexistente"
saida=$(sem compartilhamento trocar-grupo dkt-s1 dkt_g3 --sim); contem "RC=0" "$saida"; igual "@dkt_g3" "$(param dkt-s1 'valid users')"
saida=$(sem compartilhamento trocar-grupo dkt-s1 dkt_g3 --sim); contem "já é do grupo dkt_g3" "$saida"; contem "RC=1" "$saida"
saida=$(sem compartilhamento trocar-grupo dkt-nao dkt_g3 --sim); contem "não é um compartilhamento no padrão" "$saida"; contem "RC=1" "$saida"
caso "padronizar um feito à mão"
mkdir "$T/velho"
printf '\n[dkt-velho]\n   path = %s/velho\n   valid users = dkt_c1\n   read only = no\n' "$T" >> "$SANDBOX/smb.conf"
saida=$(sem compartilhamento padronizar dkt-s1 dkt_g1 --sim); contem "não é um compartilhamento fora do padrão" "$saida"; contem "RC=1" "$saida"
saida=$(sem compartilhamento padronizar dkt-velho dkt_g1 --sim); contem "RC=0" "$saida"
igual "@dkt_g1" "$(param dkt-velho 'valid users')"
caso "remover (resposta n cancela; --sim remove; a pasta fica)"
saida=$(printf 'n\n' | cli compartilhamento remover dkt-s1); contem "Cancelado" "$saida"; contem "RC=1" "$saida"
saida=$(sem compartilhamento remover dkt-s1 --sim); contem "RC=0" "$saida"
nao_contem "[dkt-s1]" "$(testparm -s "$SANDBOX/smb.conf" 2>/dev/null)"; verdadeiro "pasta fica" test -d "$T/base/dkt-s1"
saida=$(sem compartilhamento remover dkt-s1 --sim); contem "não encontrado" "$saida"; contem "RC=1" "$saida"

# ── Diagnóstico ──────────────────────────────────────────────────────────────
caso "diagnóstico: sessões, desconectar, logins, saúde"
saida=$(sem diagnostico sessoes); contem "RC=0" "$saida"
saida=$(sem diagnostico desconectar 999999 --sim); contem "Nenhuma sessão do Samba com o PID 999999" "$saida"; contem "RC=1" "$saida"
saida=$(sem diagnostico desconectar abc); contem "RC=2" "$saida"
saida=$(sem diagnostico logins); contem "Logins" "$saida"; contem "RC=0" "$saida"
saida=$(sem diagnostico saude); contem "Saúde do Samba" "$saida"; contem "Serviço e configuração" "$saida"
nao_contem "Pressione Enter" "$saida" "sem pausa"
caso "auditoria: filtros"
saida=$(sem diagnostico auditoria --dias 1 --tipo usuarios); contem "RC=0" "$saida"; contem "dkt_c1" "$saida"
saida=$(sem diagnostico auditoria --dias 1 --afetado dkt-velho); contem "dkt-velho" "$saida"; nao_contem "dkt_c2" "$saida"
saida=$(sem diagnostico auditoria --dia 31/02/2026); contem "Período inválido" "$saida"; contem "RC=2" "$saida"
saida=$(sem diagnostico auditoria --dias 1 --dia 01/01/2026); contem "não os dois" "$saida"; contem "RC=2" "$saida"
saida=$(sem diagnostico auditoria --tipo xyz); contem "RC=2" "$saida"
contem "RC=0" "$(sem diagnostico auditoria --tipo compartilhamentos)"

# ── Trava, ambiente e --preparar --sim ───────────────────────────────────────
caso "outra sessão com a trava: o que altera é recusado; o que só lê funciona"
( exec 9>>"$SANDBOX/debkit.lock"; flock 9; echo 4242 > "$SANDBOX/debkit.lock"; sleep 30 ) &
PID_TRAVA=$!; sleep 1
saida=$(sem grupo criar dkt_g8 --sim); contem "já está em uso" "$saida"; contem "RC=1" "$saida"
verdadeiro "não criado" bash -c '! getent group dkt_g8'
contem "RC=0" "$(sem grupo listar)"
kill "$PID_TRAVA" 2>/dev/null; wait "$PID_TRAVA" 2>/dev/null; PID_TRAVA=""
caso "ambiente não preparado: o que altera é recusado"
rm -f "$SANDBOX/logrotate-debkit"
saida=$(sem grupo criar dkt_g8 --sim); contem "Rode: debkit --preparar" "$saida"; contem "RC=1" "$saida"
caso "--preparar --sim prepara sem perguntar"
saida=$(bash "$DEBKIT" --preparar --sim < /dev/null 2>&1; echo "RC=$?")
contem "Preparar agora? (s/n): s (--sim)" "$saida"; contem "RC=0" "$saida"; verdadeiro "regra recriada" test -f "$SANDBOX/logrotate-debkit"

# ── Excluir ──────────────────────────────────────────────────────────────────
caso "excluir"
saida=$(sem usuario excluir dkt_c3 --sim); contem "RC=0" "$saida"; verdadeiro "excluído" bash -c '! id dkt_c3'
saida=$(sem usuario excluir dkt_c3 --sim); contem "RC=1" "$saida"
saida=$(sem usuario excluir root --sim); contem "RC=1" "$saida"; verdadeiro "root intacto" id root

caso "inglês"
DEBKIT_IDIOMA=en contem "Usage: debkit samba <group> <action>" "$(DEBKIT_IDIOMA=en bash "$DEBKIT" samba --ajuda)"
contem "y (--yes)" "$(DEBKIT_IDIOMA=en bash "$DEBKIT" samba grupo criar dkt_g7 --yes < /dev/null 2>&1)"
verdadeiro "--yes também vale" getent group dkt_g7

real_intacto
resumo
