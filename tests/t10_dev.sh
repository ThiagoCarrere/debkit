#!/usr/bin/env bash
# Testes dos scripts da VM de desenvolvimento (dev/vmnova.sh e
# dev/vmprepara.sh). O Timeshift e o apt são FALSOS (variáveis e PATH):
# nenhum restore e nenhuma instalação de verdade acontecem. O vmnova.sh roda
# a partir de uma cópia num repositório git temporário (limpo/sujo à vontade).
source "$(dirname "$0")/lib.sh"
sandbox

NOVA="$REPO/dev/vmnova.sh"; PREP="$REPO/dev/vmprepara.sh"

caso "scripts: sintaxe, shellcheck e executáveis"
for s in "$NOVA" "$PREP"; do
    verdadeiro "bash -n ${s#"$REPO"/}" bash -n "$s"
    verdadeiro "executável ${s#"$REPO"/}" test -x "$s"
done
if command -v shellcheck >/dev/null; then verdadeiro "shellcheck" shellcheck "$NOVA" "$PREP"; fi
caso "scripts: --ajuda e sem root"
contem "volta a VM de DESENVOLVIMENTO" "$(bash "$NOVA" --ajuda)"
contem "ferramentas que a suíte de testes usa" "$(bash "$PREP" --ajuda)"
contem "precisa ser executado como root" "$(setpriv --reuid=65534 --regid=65534 --clear-groups bash "$NOVA" --simular 2>&1)"
contem "precisa ser executado como root" "$(setpriv --reuid=65534 --regid=65534 --clear-groups bash "$PREP" --simular 2>&1)"
contem "opção desconhecida" "$(bash "$NOVA" --xyz 2>&1)"

# ── Timeshift falso ──────────────────────────────────────────────────────────
mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/timeshift" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_DIR/ts-args"
if [ "$1" == "--list" ]; then
    cat "$FAKE_DIR/ts-lista"
fi
exit 0
EOF
chmod 755 "$SANDBOX/bin/timeshift"
cat > "$SANDBOX/ts-lista" <<'EOF'
Device : /dev/sda1
Status : OK
2 snapshots, 1.0 TB free

Num     Name                 Tags  Description
------------------------------------------------------------------------------
0    >  2026-10-16_09-56-40  O     limpa: Debian 13 sem Samba
1    >  2026-10-20_08-00-00  O     limpa: Debian 13 de novo
2       2026-10-21_10-00-00  O     com samba e testes
EOF

# Repositório git temporário (com remoto) para o vmnova.sh "morar"
git init -q --bare "$SANDBOX/remoto.git"
git clone -q "$SANDBOX/remoto.git" "$SANDBOX/repo" 2>/dev/null
mkdir -p "$SANDBOX/repo/dev"; cp "$NOVA" "$SANDBOX/repo/dev/"
git -C "$SANDBOX/repo" add -A; git -C "$SANDBOX/repo" -c user.name=t -c user.email=t@t commit -qm inicial; git -C "$SANDBOX/repo" push -q origin HEAD 2>/dev/null
printf '{\n  "exclude" : [\n    "%s/**",\n    "/root/**"\n  ]\n}\n' "$SANDBOX/repo" > "$SANDBOX/ts.json"
nova() { FAKE_DIR="$SANDBOX" PATH="$SANDBOX/bin:$PATH" VMNOVA_TIMESHIFT="$SANDBOX/bin/timeshift" VMNOVA_TS_CONF="$SANDBOX/ts.json" bash "$SANDBOX/repo/dev/vmnova.sh" "$@" 2>&1; echo "RC=$?"; }

caso "vmnova --simular: snapshot 'limpa' mais recente, partição do /, nada executado"
: > "$SANDBOX/ts-args"
saida=$(nova --simular)
contem "RC=0" "$saida"; contem "snapshot 2026-10-20_08-00-00" "$saida" "o mais recente com 'limpa'"
contem "--target $(findmnt -n -o SOURCE /) --skip-grub --yes" "$saida" "comando com a partição do /"
contem "(simulação: nada foi feito)" "$saida"
nao_contem "[!]" "$saida" "repositório limpo e enviado: sem avisos"
nao_contem "--restore" "$(cat "$SANDBOX/ts-args")" "restore NÃO chamado"
caso "vmnova --snapshot: escolhido pelo nome; inexistente dá erro"
contem "snapshot 2026-10-16_09-56-40" "$(nova --simular --snapshot 2026-10-16_09-56-40)"
saida=$(nova --simular --snapshot 2099-01-01_00-00-00); contem "não existe" "$saida"; contem "RC=1" "$saida"
contem "Snapshots disponíveis" "$saida" "lista os existentes"
caso "vmnova: sem snapshot 'limpa'"
saida=$(VMNOVA_DESCRICAO=outra nova --simular); contem "nenhum snapshot com descrição começando por 'outra'" "$saida"; contem "RC=1" "$saida"

caso "vmnova: mudança sem commit / commit sem push / repositório fora das exclusões - recusa"
echo x > "$SANDBOX/repo/novo.txt"
saida=$(printf 'RESTAURAR\n' | nova)
contem "mudanças sem commit" "$saida"; contem "resolva os itens acima" "$saida"; contem "RC=1" "$saida"
git -C "$SANDBOX/repo" add -A; git -C "$SANDBOX/repo" -c user.name=t -c user.email=t@t commit -qm local
saida=$(printf 'RESTAURAR\n' | nova)
contem "1 commit(s) ainda não enviados" "$saida"; contem "RC=1" "$saida"
git -C "$SANDBOX/repo" push -q origin HEAD 2>/dev/null
printf '{ "exclude" : [ "/root/**" ] }\n' > "$SANDBOX/ts.json"
saida=$(printf 'RESTAURAR\n' | nova)
contem "não está nas exclusões do Timeshift" "$saida"; contem "RC=1" "$saida"
printf '{\n  "exclude" : [\n    "%s/**"\n  ]\n}\n' "$SANDBOX/repo" > "$SANDBOX/ts.json"
nao_contem "--restore" "$(cat "$SANDBOX/ts-args")" "restore NÃO chamado em nenhuma recusa"

caso "vmnova: confirmação errada cancela"
saida=$(printf 'sim\n' | nova)
contem "Cancelado. Nada foi feito." "$saida"; contem "RC=1" "$saida"
nao_contem "--restore" "$(cat "$SANDBOX/ts-args")"
caso "vmnova: RESTAURAR chama o restore (Timeshift FALSO)"
saida=$(printf 'RESTAURAR\n' | nova)
contem "RC=0" "$saida"
igual "--restore --snapshot 2026-10-20_08-00-00 --target $(findmnt -n -o SOURCE /) --skip-grub --yes" "$(grep -- --restore "$SANDBOX/ts-args")"
caso "vmnova --forcar aceita repositório sujo (mas mostra o aviso)"
echo y > "$SANDBOX/repo/outro.txt"; : > "$SANDBOX/ts-args"
saida=$(printf 'RESTAURAR\n' | nova --forcar)
contem "mudanças sem commit" "$saida"; contem "RC=0" "$saida"
contem "--restore" "$(cat "$SANDBOX/ts-args")"

# ── vmprepara com apt falso ──────────────────────────────────────────────────
cat > "$SANDBOX/bin/apt-falso" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_DIR/apt-args"
exit "${FAKE_APT_RC:-0}"
EOF
chmod 755 "$SANDBOX/bin/apt-falso"
prep() { FAKE_DIR="$SANDBOX" VMPREPARA_APT="$SANDBOX/bin/apt-falso" bash "$PREP" "$@" 2>&1; echo "RC=$?"; }
caso "vmprepara: com tudo instalado não chama o apt e confere o ufw inativo"
: > "$SANDBOX/apt-args"
if command -v shellcheck >/dev/null && command -v smbclient >/dev/null && command -v ufw >/dev/null; then
    saida=$(prep)
    contem "todas já instaladas" "$saida"; contem "✔ ufw inativo" "$saida"; contem "RC=0" "$saida"
    contem "./debkit --preparar" "$saida" "mostra os próximos passos"
    igual "" "$(cat "$SANDBOX/apt-args")" "apt não chamado"
else
    echo "  (ferramentas não instaladas nesta VM: caso pulado)"
fi
caso "vmprepara: faltando ferramenta chama o apt sem os recomendados (apt FALSO)"
: > "$SANDBOX/apt-args"
saida=$(VMPREPARA_FERRAMENTAS="ufw dkt-ferramenta-inexistente" prep)
contem "a instalar: dkt-ferramenta-inexistente" "$saida"
contem "install -y -qq --no-install-recommends dkt-ferramenta-inexistente" "$(cat "$SANDBOX/apt-args")" "só o que falta, sem recomendados"
contem "✘ dkt-ferramenta-inexistente não instalado" "$saida" "confere depois da instalação"; contem "RC=1" "$saida"
caso "vmprepara: falha do apt"
saida=$(FAKE_APT_RC=100 VMPREPARA_FERRAMENTAS="dkt-ferramenta-inexistente" prep)
contem "a instalação falhou" "$saida"; contem "RC=1" "$saida"
caso "vmprepara --simular não instala nada"
: > "$SANDBOX/apt-args"
contem "(simulação: nada foi feito)" "$(prep --simular)"; igual "" "$(cat "$SANDBOX/apt-args")"

real_intacto
resumo
