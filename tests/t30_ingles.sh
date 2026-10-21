#!/usr/bin/env bash
# Testes da tarefa 4.5 - bilíngue pt/en (seção 3.9): o menu, a verificação
# e as telas só de leitura inteiros em inglês, sem sobra de português; o
# idioma "auto" pelo sistema; a ajuda nos dois idiomas. (O catálogo com as
# mesmas chaves e a escolha do idioma estão em t01; os comandos em inglês,
# em t27.)
source "$(dirname "$0")/lib.sh"
sandbox
preparar_sandbox
# Palavras que só aparecem se sobrou texto em português
PT='Usuários|Usuário|Grupos|Compartilhamentos|Escolha|Voltar|Pressione|Nenhum|nenhum| não |Sim |Ambiente|Serviço|Configuração|Diagnóstico|Sessões|pasta|senha'
sem_pt() { local achou; achou=$(grep -oE "$PT" <<< "$1" | sort -u | paste -sd,); igual "" "$achou" "${2:-sem português}"; }

caso "menu em inglês: Samba > Users/Groups/Shares/Diagnostics (só leitura) e sair"
saida=$(DEBKIT_IDIOMA=en pty 0.7 "bash $DEBKIT" 1 1 1 "" 0 2 1 "" 0 3 1 "" 0 4 1 "" 4 3 "" 0 0 0)
contem "debkit - Debian server administration" "$saida"; contem "Users" "$saida"; contem "Groups" "$saida"
contem "Shares" "$saida"; contem "Diagnostics" "$saida"; contem "Exit" "$saida"
sem_pt "$saida"
caso "verificação do ambiente em inglês"
saida=$(DEBKIT_IDIOMA=en bash "$DEBKIT" --check 2>&1)
contem "Essential dependencies" "$saida"; contem "Environment ready for debkit." "$saida"
sem_pt "$saida"
caso "idioma auto: inglês num sistema em inglês, português num em português"
sed -i '/^IDIOMA=/d' "$SANDBOX/debkit.conf"
contem "Usage: debkit" "$(env -u LANGUAGE LANG=en_US.UTF-8 bash "$DEBKIT" --help)"
contem "Uso: debkit" "$(env -u LANGUAGE LANG=pt_BR.UTF-8 bash "$DEBKIT" --ajuda)"
# (com ou sem usuários comuns na máquina: a tabela ou o aviso)
verdadeiro "C.UTF-8: inglês" bash -c "env -u LANGUAGE LANG=C.UTF-8 bash '$DEBKIT' samba user list 2>&1 | grep -qE 'Full name|No regular users'"
caso "IDIOMA no debkit.conf ganha do sistema"
echo "IDIOMA=pt_BR" >> "$SANDBOX/debkit.conf"
verdadeiro "listar em português" bash -c "env -u LANGUAGE LANG=en_US.UTF-8 bash '$DEBKIT' samba usuario listar 2>&1 | grep -qE 'Nome completo|Nenhum usuário comum'"
contem "Uso: debkit" "$(env -u LANGUAGE LANG=en_US.UTF-8 bash "$DEBKIT" --ajuda)"
caso "ajuda e instalador em inglês"
saida=$(DEBKIT_IDIOMA=en bash "$DEBKIT" --help)
contem "--uninstall" "$saida"; contem "debkit samba --help" "$saida"; sem_pt "$saida"
saida=$(DEBKIT_IDIOMA=en bash "$DEBKIT" samba --help)
contem "user create <login>" "$saida"; contem "share change-group" "$saida"
saida=$(DEBKIT_IDIOMA=en bash "$REPO/install.sh" --help); contem "Usage: sudo ./install.sh" "$saida"; sem_pt "$saida"
caso "mensagens de antes do catálogo (sh) em inglês"
contem "this program needs bash" "$(env -u LANGUAGE LANG=C sh "$DEBKIT" 2>&1)"
contem "precisa do bash" "$(env LANGUAGE=pt_BR LANG=C.UTF-8 sh "$DEBKIT" 2>&1)"
caso "erros do debkit.conf em inglês"
cp "$SANDBOX/debkit.conf" "$SANDBOX/debkit.conf.bom"; printf 'IDIOMA=en\nSENHA_MIN=zero\n' >> "$SANDBOX/debkit.conf"
contem "invalid value for SENHA_MIN: 'zero'" "$(bash "$DEBKIT" --check 2>&1)"
cp "$SANDBOX/debkit.conf.bom" "$SANDBOX/debkit.conf"; printf 'IDIOMA=en\nXYZ=1\nSHARES_CONF=/x\n' >> "$SANDBOX/debkit.conf"
saida=$(bash "$DEBKIT" --check 2>&1)
contem "unknown key 'XYZ' (ignored)" "$saida"; contem "the key 'SHARES_CONF' is no longer used (debkit edits smb.conf directly)" "$saida"
cp "$SANDBOX/debkit.conf.bom" "$SANDBOX/debkit.conf"

real_intacto
resumo
