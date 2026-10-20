#!/usr/bin/env bash
# Testes das sessões ativas (Fase 3, tarefa 3.1; decisões na seção 3.8):
# leitura do smbstatus (-p, -S, -L; nomes com espaços lidos da direita),
# resumo por sessão, tela e desconectar UMA sessão. smbstatus simulado e
# encerramento simulado no sandbox; a prova com sessões de verdade está em
# t22b_sessoes_real.sh.
source "$(dirname "$0")/lib.sh"
sandbox

cat > "$SANDBOX/st_p" <<'EOF'

Samba version 4.22.11-Debian
PID     Username     Group        Machine                                   Protocol Version  Encryption           Signing
----------------------------------------------------------------------------------------------------------------------------------------
1001    dkt_ana      dkt_ana      192.168.0.10 (ipv4:192.168.0.10:55304)    SMB3_11           -                    partial(AES-128-CMAC)
1002    dkt_bruno    dkt_bruno    192.168.0.22 (ipv4:192.168.0.22:50001)    SMB3_11           -                    partial(AES-128-GMAC)
1002    dkt_bruno    dkt_bruno    192.168.0.22 (ipv4:192.168.0.22:50002)    SMB3_11           -                    partial(AES-128-GMAC)
1003    dkt_ana      dkt_ana      10.0.0.5 (ipv4:10.0.0.5:40000)            SMB2_10           -                    -
EOF
cat > "$SANDBOX/st_S" <<'EOF'

Service      pid     Machine       Connected at                     Encryption   Signing
---------------------------------------------------------------------------------------------
financeiro   1001    192.168.0.10  Tue Oct 20 10:02:21 2026 -03     -            -
Meus Docs    1001    192.168.0.10  Tue Oct 20 09:15:00 2026 -03     -            -
IPC$         1001    192.168.0.10  Tue Oct 20 09:15:00 2026 -03     -            -
projetos     1002    192.168.0.22  Tue Oct 20 11:28:40 2026 -03     -            -
EOF
cat > "$SANDBOX/st_L" <<'EOF'
Locked files:
Pid          User(ID)   DenyMode   Access      R/W        Oplock           SharePath   Name   Time
--------------------------------------------------------------------------------------------------
1001         1005       DENY_NONE  0x3         RDWR       NONE             /srv/samba/financeiro   planilha 2026.xlsx   Tue Oct 20 11:27:12 2026
1001         1005       DENY_NONE  0x100081    RDONLY     NONE             /srv/samba/financeiro   .   Tue Oct 20 11:27:12 2026
1001         1005       DENY_NONE  0x3         RDWR       NONE             /srv/meus docs   notas/ata da reuniao.docx   Tue Oct 20 11:27:15 2026
EOF
CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;
     smbstatus() { case \"\$*\" in *-p*) cat '$SANDBOX/st_p' ;; *-S*) cat '$SANDBOX/st_S' ;; *-L*) cat '$SANDBOX/st_L' ;; esac; };
     debkit_samba_encerrar_pids() { echo \"ENCERRAR: \$*\" >> '$SANDBOX/encerrados'; [ ! -e '$SANDBOX/encerrar_falha' ]; };"
p() { bash -c "source '$DEBKIT'; $CFG $1" 2>&1; }
LOG() { cat "$SANDBOX/debkit.log" 2>/dev/null; }
tela() { local f="$1"; shift; printf '%s\n' "$@" | p "$f; echo RC=\$?"; }
preparar_sandbox

# ════════════════════════════════════════════════════════════════════════════
# Leitura do smbstatus
# ════════════════════════════════════════════════════════════════════════════
caso "sessões: pid, usuário, IP e protocolo; o mesmo PID uma vez só"
igual "$(printf '1001|dkt_ana|192.168.0.10|SMB3_11\n1002|dkt_bruno|192.168.0.22|SMB3_11\n1003|dkt_ana|10.0.0.5|SMB2_10')" "$(p debkit_diag_sessoes)"
caso "compartilhamentos: nome com espaços, sem o IPC\$, data lida da direita"
igual "$(printf '1001|financeiro|20 Oct 2026 10:02:21\n1001|Meus Docs|20 Oct 2026 09:15:00\n1002|projetos|20 Oct 2026 11:28:40')" "$(p debkit_diag_conexoes)"
caso "arquivos abertos: pasta e arquivo com espaços, sem a pasta '.'"
igual "$(printf '1001|/srv/samba/financeiro|planilha 2026.xlsx\n1001|/srv/meus docs|notas/ata da reuniao.docx')" "$(p debkit_diag_arquivos)"
caso "resumo: uma linha por sessão, compartilhamentos, arquivos e a conexão mais antiga"
saida=$(p debkit_diag_resumo)
contem "1001|dkt_ana|192.168.0.10|financeiro, Meus Docs|2|20/10/2026 09:15" "$saida"
contem "1002|dkt_bruno|192.168.0.22|projetos|0|20/10/2026 11:28" "$saida"
contem "1003|dkt_ana|10.0.0.5||0|" "$saida" "sessão sem compartilhamento aberto"
igual 3 "$(wc -l <<< "$saida")"
caso "sem ninguém conectado"
igual "" "$(p "smbstatus() { :; }; debkit_diag_resumo")"

# ════════════════════════════════════════════════════════════════════════════
# Desconectar
# ════════════════════════════════════════════════════════════════════════════
caso "desconectar: só o PID escolhido, auditado"
: > "$SANDBOX/encerrados"
saida=$(p "debkit_diag_desconectar 1002; echo RC=\$?")
contem "RC=0" "$saida"; contem "Sessão de dkt_bruno em 192.168.0.22 desconectada" "$saida"
igual "ENCERRAR: 1002" "$(cat "$SANDBOX/encerrados")"
contem "sessao_desconectar usuario=dkt_bruno ip=192.168.0.22 pid=1002 resultado=ok" "$(LOG)"
caso "desconectar: PID que não é uma sessão do Samba é recusado sem encerrar nada"
: > "$SANDBOX/encerrados"
for x in 999 "$$" 1 abc "" "1001 1002"; do
    contem "não existe mais" "$(p "debkit_diag_desconectar '$x'; echo RC=\$?")" "pid '$x'"
done
igual "" "$(cat "$SANDBOX/encerrados")" "nada encerrado"
caso "desconectar: a sessão continua - informado e auditado"
touch "$SANDBOX/encerrar_falha"
saida=$(p "debkit_diag_desconectar 1001; echo RC=\$?")
contem "RC=1" "$saida"; contem "a sessão continua aberta" "$saida"
contem "pid=1001 resultado=falha" "$(LOG)"
rm -f "$SANDBOX/encerrar_falha"

# ════════════════════════════════════════════════════════════════════════════
# Telas
# ════════════════════════════════════════════════════════════════════════════
caso "tela: tabela, total e Enter volta sem desconectar"
: > "$SANDBOX/encerrados"
saida=$(tela debkit_diag_tela_sessoes "")
contem "Usuário" "$saida"; contem "Compartilhamentos" "$saida"
contem " 1) dkt_ana " "$saida"; contem "financeiro, Meus Docs" "$saida"; contem "20/10/2026 09:15" "$saida"
contem " 2) dkt_bruno " "$saida"; contem "3 sessão(ões)." "$saida"; contem "RC=0" "$saida"
igual "" "$(cat "$SANDBOX/encerrados")"
caso "tela: escolhe, resumo com os arquivos abertos e 'n' cancela"
saida=$(tela debkit_diag_tela_sessoes 1 n "")
contem "Sessão: dkt_ana em 192.168.0.10 (desde 20/10/2026 09:15)" "$saida"
contem "Compartilhamentos abertos: financeiro, Meus Docs" "$saida"
contem "2 arquivo(s) aberto(s): planilha 2026.xlsx, notas/ata da reuniao.docx" "$saida"
contem "Só esta sessão (esta máquina) é encerrada" "$saida"; contem "Cancelado" "$saida"
igual "" "$(cat "$SANDBOX/encerrados")"
caso "tela: 's' desconecta só a sessão escolhida"
saida=$(tela debkit_diag_tela_sessoes 3 s "")
contem "Sessão de dkt_ana em 10.0.0.5 desconectada" "$saida"; nao_contem "arquivo(s) aberto(s)" "$saida"
igual "ENCERRAR: 1003" "$(cat "$SANDBOX/encerrados")"
caso "tela: número inválido pede de novo"
contem "Opção inválida: '9'" "$(tela debkit_diag_tela_sessoes 9 "")"
caso "tela: ninguém conectado"
contem "Ninguém conectado ao Samba agora" "$(tela "smbstatus() { :; }; debkit_diag_tela_sessoes" "")"
caso "menu Samba > 4) Diagnóstico > 1) Sessões ativas"
saida=$(pty 0.6 "bash $DEBKIT" 1 4 "" 0 0 0)
contem "4) Diagnóstico" "$saida"; contem "Samba: diagnóstico" "$saida"; contem "1) Sessões ativas" "$saida"
caso "inglês"
contem "3 session(s)." "$(printf '\n' | p "DEBKIT_IDIOMA=en; debkit_diag_tela_sessoes")"

real_intacto
resumo
