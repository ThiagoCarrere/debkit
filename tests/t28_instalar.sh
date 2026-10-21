#!/usr/bin/env bash
# Testes da tarefa 4.3 - install.sh (seção 3.9): instalação nova (só o
# programa, dono root, sem escrita para grupo/outros, marca e comando),
# atualização (a pasta é trocada de uma vez; a antiga fica se a nova não
# funcionar), o repositório já no lugar, e as recusas (pasta ou comando que
# não são do debkit, repositório git). Tudo no sandbox (DEBKIT_INSTALAR_DIR
# e DEBKIT_INSTALAR_LINK); a prova com /opt/debkit e /usr/local/sbin está
# em t28b_instalar_real.sh.
source "$(dirname "$0")/lib.sh"
sandbox
preparar_sandbox

DEST="$SANDBOX/opt/debkit"; LNK="$SANDBOX/sbin/debkit"
inst() { DEBKIT_INSTALAR_DIR="${DEST_T:-$DEST}" DEBKIT_INSTALAR_LINK="${LNK_T:-$LNK}" bash "${INST_T:-$REPO/install.sh}" "$@" 2>&1; echo "RC=$?"; }
VERSAO=$(bash "$DEBKIT" --versao)

caso "ajuda (sem root também), opção desconhecida, sh em vez de bash"
saida=$(inst --ajuda < /dev/null); contem "Uso: sudo ./install.sh" "$saida"; contem "$DEST" "$saida"; contem "RC=0" "$saida"
saida=$(setpriv --reuid=65534 --regid=65534 --clear-groups bash "$REPO/install.sh" --ajuda 2>&1); contem "Uso: sudo ./install.sh" "$saida"
saida=$(setpriv --reuid=65534 --regid=65534 --clear-groups env DEBKIT_INSTALAR_DIR="$DEST" bash "$REPO/install.sh" 2>&1; echo "RC=$?")
contem "precisa ser executado como root" "$saida"; contem "RC=1" "$saida"
saida=$(inst --xyz < /dev/null); contem "Opção desconhecida: '--xyz'" "$saida"; contem "RC=2" "$saida"
saida=$(sh "$REPO/install.sh" 2>&1; echo "RC=$?"); contem "precisa do bash" "$saida"; contem "RC=1" "$saida"
caso "pasta de instalação inválida ou dentro do repositório"
saida=$(DEST_T="opt/debkit" inst < /dev/null); contem "Pasta de instalação inválida" "$saida"; contem "RC=1" "$saida"
saida=$(DEST_T="$REPO/sub" inst < /dev/null); contem "uma dentro da outra" "$saida"; contem "RC=1" "$saida"

caso "--simular mostra o plano e não faz nada"
saida=$(inst --simular < /dev/null)
contem "Copiar o debkit ${VERSAO#debkit } para $DEST" "$saida"; contem "Criar o comando $LNK" "$saida"
contem "(simulação: nada foi feito)" "$saida"; contem "RC=0" "$saida"
verdadeiro "nada criado" test ! -e "$DEST" -a ! -e "$LNK"
caso "resposta n: nada feito"
saida=$(printf 'n\n' | inst); contem "Cancelado" "$saida"; contem "RC=1" "$saida"; verdadeiro "nada criado" test ! -e "$DEST"

caso "instalação nova (sem preparar)"
saida=$(printf 's\nn\n' | inst)
contem "RC=0" "$saida"; contem "instalado em $DEST. Comando: $LNK" "$saida"; contem "Quando quiser: sudo debkit --preparar" "$saida"
for f in debkit install.sh lib/nucleo.sh modulos/samba.sh debkit.conf.exemplo LICENSE README.md CHANGELOG.md docs/PLANEJAMENTO.md .debkit-instalado; do
    verdadeiro "$f" test -f "$DEST/$f"
done
for f in tests dev .git .github; do verdadeiro "sem $f" test ! -e "$DEST/$f"; done
igual "0:0 755" "$(stat -c '%u:%g %a' "$DEST")" "pasta: root, 755"
igual "755 644 644" "$(stat -c %a "$DEST/debkit" "$DEST/lib/nucleo.sh" "$DEST/modulos/samba.sh" | paste -sd' ')" "permissões"
igual "" "$(find "$DEST" ! -user root -o -perm /022 ! -type l)" "tudo do root, sem escrita para grupo/outros"
igual "$DEST/debkit" "$(readlink "$LNK")" "comando é o link"
igual "$VERSAO" "$("$LNK" --versao)" "comando funciona"
contem "versao=${VERSAO#debkit }" "$(cat "$DEST/.debkit-instalado")"
contem "instalar versao=${VERSAO#debkit } modo=novo destino=$DEST comando=$LNK" "$(cat "$SANDBOX/debkit.log")" "auditado"
verdadeiro "sem sobra de pasta temporária" bash -c "! ls -d '$SANDBOX/opt/'.debkit-novo.* 2>/dev/null"

caso "de novo: atualização (pasta trocada inteira; o comando já aponta)"
echo "# sobra" > "$DEST/lib/velho.sh"; echo "# mexido" >> "$DEST/lib/nucleo.sh"
saida=$(printf 's\nn\n' | inst)
contem "Atualizar $DEST (de ${VERSAO#debkit } para ${VERSAO#debkit })" "$saida"; contem "já aponta para esta instalação" "$saida"; contem "RC=0" "$saida"
verdadeiro "arquivo que sobrava saiu" test ! -e "$DEST/lib/velho.sh"
verdadeiro "nucleo igual ao do repositório" cmp -s "$REPO/lib/nucleo.sh" "$DEST/lib/nucleo.sh"
contem "modo=atualizar" "$(cat "$SANDBOX/debkit.log")"
verdadeiro "sem sobra da pasta antiga" bash -c "! ls -d '$DEST'.antigo.* 2>/dev/null"

caso "atualização com uma cópia que não funciona: a instalação antiga fica"
QUEBRADO="$SANDBOX/src-quebrado"; mkdir -p "$QUEBRADO"
cp -R "$REPO/debkit" "$REPO/install.sh" "$REPO/lib" "$REPO/modulos" "$QUEBRADO/"
echo 'isto não é bash (' >> "$QUEBRADO/modulos/samba.sh"
md5_antes=$(find "$DEST" -type f -exec md5sum {} + | sort | md5sum)
saida=$(printf 's\nn\n' | INST_T="$QUEBRADO/install.sh" inst)
contem "A instalação falhou: a cópia não funciona" "$saida"; contem "RC=1" "$saida"
igual "$md5_antes" "$(find "$DEST" -type f -exec md5sum {} + | sort | md5sum)" "instalação antiga intacta"
verdadeiro "sem sobra de pasta temporária" bash -c "! ls -d '$SANDBOX/opt/'.debkit-novo.* 2>/dev/null"

caso "recusas: pasta de outro programa, repositório git, comando que não é do debkit"
mkdir -p "$SANDBOX/outro"; echo x > "$SANDBOX/outro/arquivo"
saida=$(DEST_T="$SANDBOX/outro" inst < /dev/null); contem "não é uma instalação do debkit" "$saida"; contem "RC=1" "$saida"
igual "x" "$(cat "$SANDBOX/outro/arquivo")" "intocada"
mkdir -p "$SANDBOX/clonegit/.git"; cp "$REPO/debkit" "$SANDBOX/clonegit/"
saida=$(DEST_T="$SANDBOX/clonegit" inst < /dev/null); contem "git -C $SANDBOX/clonegit pull" "$saida"; contem "RC=1" "$saida"
echo "#!/bin/sh" > "$SANDBOX/sbin/outro"
saida=$(LNK_T="$SANDBOX/sbin/outro" inst < /dev/null); contem "não aponta para $DEST/debkit" "$saida"; contem "RC=1" "$saida"
ln -s /bin/true "$SANDBOX/sbin/link-alheio"
saida=$(LNK_T="$SANDBOX/sbin/link-alheio" inst < /dev/null); contem "não aponta para" "$saida"; contem "RC=1" "$saida"
igual "/bin/true" "$(readlink "$SANDBOX/sbin/link-alheio")" "link alheio intocado"

caso "repositório já no lugar: só dono/permissões e o comando"
CLONE="$SANDBOX/clone"; mkdir -p "$CLONE"
cp -R "$REPO/debkit" "$REPO/install.sh" "$REPO/lib" "$REPO/modulos" "$CLONE/"
chmod 664 "$CLONE/lib/nucleo.sh"
saida=$(printf 's\nn\n' | DEST_T="$CLONE" LNK_T="$SANDBOX/sbin/debkit-clone" INST_T="$CLONE/install.sh" inst)
contem "Usar o debkit que já está em $CLONE" "$saida"; contem "RC=0" "$saida"
igual "644" "$(stat -c %a "$CLONE/lib/nucleo.sh")" "escrita do grupo tirada"
verdadeiro "sem marca (não é cópia do instalador)" test ! -e "$CLONE/.debkit-instalado"
igual "$CLONE/debkit" "$(readlink "$SANDBOX/sbin/debkit-clone")"

caso "--sim instala e prepara (o servidor do sandbox já está preparado)"
rm -rf "$DEST" "$LNK"
saida=$(inst --sim < /dev/null)
contem "Instalar agora? (s/n): s (--sim)" "$saida"; contem "Preparar o servidor agora (debkit --preparar)? (s/n): s (--sim)" "$saida"
contem "já está preparado" "$saida"; contem "RC=0" "$saida"

caso "inglês"
contem "Usage: sudo ./install.sh" "$(DEBKIT_IDIOMA=en bash "$REPO/install.sh" --help)"

real_intacto
resumo
