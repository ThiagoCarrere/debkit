#!/usr/bin/env bash
# Testes da saúde do Samba (Fase 3, tarefa 3.3; decisões na seção 3.8): o
# relatório reaproveita a verificação do ambiente e os alertas dos
# compartilhamentos e das contas, e soma porta, disco e atividade. Cada fonte
# é simulada no sandbox; um caso roda sem simulação para conferir que nada
# muda. A prova com o servidor de verdade está em t24b_saude_real.sh.
source "$(dirname "$0")/lib.sh"
sandbox

CFG="debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; debkit_ler_login_defs;"
# Tudo em ordem (cada caso troca uma parte)
OK="debkit_verificar_ambiente() { DEBKIT_VERIF=(); DEBKIT_SVC_SAMBA=''; DEBKIT_BLOQ_MANUAL=0
        debkit_verif_add samba ok 'smb.conf válido'; debkit_verif_add firewall ok 'firewall libera'
        debkit_verif_add ssh aviso 'item do SSH'; debkit_verif_add samba na 'não se aplica'; }
    debkit_montar_plano() { DEBKIT_PLANO=(); DEBKIT_PLANO_IMPOSSIVEL=''; }
    ss() { echo 'LISTEN 0 50 0.0.0.0:445 0.0.0.0:*'; }
    debkit_saude_pastas() { printf '%s\n' 'financeiro|/srv/a' 'suporte|/srv/b' 'pastas pessoais|/home/x'; }
    df() { echo 'Montado Uso% IUso% Disp'; case \"\${@: -1}\" in /srv/*) echo '/srv/meus dados 40% 2% 204800' ;; *) echo '/ 10% - 512' ;; esac; }
    debkit_shr_dados() { printf '%s\n' 'financeiro|/srv/a|@gf||' 'suporte|/srv/b|@gs||'; }
    debkit_shr_gerenciaveis() { printf '%s\n' 'financeiro|/srv/a|gf' 'suporte|/srv/b|gs'; }
    debkit_shr_usuarios() { echo fulano; }
    debkit_samba_usuarios_dados() { printf '%s\n' 'ana|Ana|arquivos|ativa|||' 'bia|Bia|arquivos|ativa|||' 'dev|Dev|admin|nao|||'; }
    debkit_samba_inconsistencias() { :; }
    debkit_diag_sessoes() { echo '1|ana|192.168.0.10|SMB3_11'; }
    debkit_diag_falhas() { :; };"
p() { bash -c "source '$DEBKIT'; $CFG $OK $1" 2>&1; }
estado() { p "$1; debkit_saude_coletar; printf '%s\n' \"\${DEBKIT_SAUDE[@]}\"" | tr '\t' '|'; }
tela() { printf '\n' | p "$1; debkit_diag_tela_saude; echo RC=\$?"; }
preparar_sandbox

# ════════════════════════════════════════════════════════════════════════════
# Coleta
# ════════════════════════════════════════════════════════════════════════════
caso "tudo em ordem: cada grupo com o que se espera"
saida=$(estado ":")
contem "config|ok|smb.conf válido" "$saida"; contem "rede|ok|firewall libera" "$saida"
nao_contem "item do SSH" "$saida" "só os itens do Samba e do firewall"; nao_contem "não se aplica" "$saida"
contem "rede|ok|smbd escutando na porta 445" "$saida"
contem "disco|ok|/srv/meus dados: 40% usado, 200 GB livres (financeiro, suporte)" "$saida" "montagem com espaço; pastas juntas"
contem "disco|ok|/: 10% usado, 512 MB livres (pastas pessoais)" "$saida"
contem "shr|info|2 compartilhamento(s)." "$saida"
contem "contas|info|2 usuário(s) com conta no Samba" "$saida"
contem "atividade|info|1 sessão(ões) ativa(s)" "$saida"; contem "atividade|ok|Nenhuma falha de login nas últimas 24 horas" "$saida"
nao_contem "|aviso|" "$saida"; nao_contem "|erro|" "$saida"
caso "verificação: o que impede vira problema; preparação pendente avisa"
saida=$(estado "debkit_verificar_ambiente() { DEBKIT_VERIF=(); DEBKIT_SVC_SAMBA=''; debkit_verif_add samba falta 'smb.conf com erro'; debkit_verif_add firewall aviso 'firewall bloqueia'; }
                debkit_montar_plano() { DEBKIT_PLANO=(a b); DEBKIT_PLANO_IMPOSSIVEL=''; }")
contem "config|erro|smb.conf com erro" "$saida"; contem "rede|aviso|firewall bloqueia" "$saida"
contem "config|aviso|A preparação tem 2 item(ns) pendente(s): rode debkit --preparar" "$saida"
caso "porta fechada"
contem "rede|erro|Ninguém escutando na porta 445" "$(estado "ss() { :; }")"
caso "disco: aviso a partir de 85%, problema a partir de 95%, inodes"
saida=$(estado "df() { echo 'h'; case \"\${@: -1}\" in /srv/a) echo '/a 85% 10% 2048' ;; /srv/b) echo '/b 95% 96% 100' ;; *) echo '/c 84% - 1' ;; esac; }")
contem "disco|aviso|/a: 85% usado, 2 GB livres" "$saida"
contem "disco|erro|/b: 95% usado, 100 MB livres" "$saida"
contem "disco|aviso|/b: 96% dos inodes usados" "$saida"
contem "disco|ok|/c: 84% usado" "$saida"
caso "disco: pasta que o df não lê fica de fora"
saida=$(estado "df() { return 1; }"); nao_contem "disco|" "$saida"
caso "compartilhamentos: sem pasta é problema; convidado, todos, fora do padrão e grupo sem membros avisam"
saida=$(estado "debkit_shr_dados() { printf '%s\n' 'a|/srv/x|@g||sem_pasta' 'b|/srv/b|*||convidado,todos' 'c|/srv/c|@g|@h|fora_padrao'; }
                debkit_shr_usuarios() { :; }")
contem "shr|info|3 compartilhamento(s)." "$saida"
contem "shr|erro|a: a pasta /srv/x não existe" "$saida"
contem "shr|aviso|b: aberto para convidado" "$saida"; contem "shr|aviso|b: sem \"valid users\"" "$saida"
contem "shr|aviso|c: fora do padrão do debkit" "$saida"
contem "shr|aviso|financeiro: o grupo gf não tem membros: ninguém acessa" "$saida"
contem "shr|aviso|suporte: o grupo gs não tem membros" "$saida"
caso "contas: desativadas e fora do padrão (cada conta uma vez)"
saida=$(estado "debkit_samba_usuarios_dados() { printf '%s\n' 'ana|||ativa|||' 'bia|||desativada|||' 'orfa|||so_samba|||' 'dev|||nao|||'; }
                debkit_samba_inconsistencias() { printf '%s\n' 'so_linux|dev' 'tunel|dev' 'so_samba|orfa'; }")
contem "contas|info|3 usuário(s) com conta no Samba" "$saida"
contem "contas|info|Contas desativadas: bia" "$saida"
contem "contas|aviso|2 conta(s) fora do padrão: dev, orfa (Samba > Usuários > Consistência)" "$saida"
caso "atividade: falhas nas últimas 24 horas; muitas do mesmo usuário e máquina avisam"
saida=$(estado "debkit_diag_sessoes() { :; }
                debkit_diag_falhas() { printf '%s\n' 'ana|192.168.0.10|10|2026-10-20 10:00:00|NT_STATUS_WRONG_PASSWORD' 'x|10.0.0.9|9|2026-10-20 09:00:00|NT_STATUS_NO_SUCH_USER'; }")
contem "atividade|info|0 sessão(ões)" "$saida"
contem "atividade|info|19 falha(s) de login nas últimas 24 horas" "$saida"
contem "atividade|aviso|ana em 192.168.0.10: 10 falhas" "$saida"; nao_contem "x em 10.0.0.9" "$saida"
caso "atividade: a janela é de 24 horas"
contem "$(date -d '24 hours ago' '+%Y-%m-%d %H:')" "$(estado "debkit_diag_falhas() { echo \"x|y|1|z|\$1\" > '$SANDBOX/desde'; }"; cat "$SANDBOX/desde")"

# ════════════════════════════════════════════════════════════════════════════
# Tela
# ════════════════════════════════════════════════════════════════════════════
caso "tela: grupos, ícones e 'tudo certo'"
saida=$(tela ":")
for x in "Verificado em" "Serviço e configuração" "Rede" "Espaço em disco" "Compartilhamentos" "Contas" "Atividade"; do contem "$x" "$saida"; done
contem "✔ smbd escutando na porta 445" "$saida"; contem "· 2 compartilhamento(s)." "$saida"
contem "Tudo certo com o Samba." "$saida"; contem "RC=0" "$saida"
caso "tela: só avisos"
saida=$(tela "ss() { echo x; }; debkit_samba_inconsistencias() { echo 'tunel|ana'; }")
contem "! 1 conta(s) fora do padrão" "$saida"; contem "1 aviso(s)." "$saida"; nao_contem "Tudo certo" "$saida"
caso "tela: problemas e avisos"
saida=$(tela "ss() { :; }; debkit_samba_inconsistencias() { echo 'tunel|ana'; }")
contem "✘ Ninguém escutando na porta 445" "$saida"; contem "1 problema(s) e 1 aviso(s)." "$saida"
caso "sem simulação (sandbox): o relatório sai e nada muda"
saida=$(printf '\n' | bash -c "source '$DEBKIT'; $CFG debkit_diag_tela_saude; echo RC=\$?" 2>&1)
contem "RC=0" "$saida"; contem "Verificado em" "$saida"; contem "Espaço em disco" "$saida"
caso "menu Samba > 4) Diagnóstico > 3) Saúde"
saida=$(pty 1.5 "bash $DEBKIT" 1 4 3 "" 0 0 0)
contem "3) Saúde do Samba (relatório)" "$saida"; contem "Serviço e configuração" "$saida"
caso "inglês"
saida=$(tela "DEBKIT_IDIOMA=en")
contem "Service and configuration" "$saida"; contem "Disk space" "$saida"; contem "All good with Samba." "$saida"

real_intacto
resumo
