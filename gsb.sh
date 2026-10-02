#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  gsb - Gerenciador Samba                                                 ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# Gerenciador de servidor de arquivos Samba, com foco em segurança.
# Só gerencia o que ele mesmo cria (ver docs/PLANEJAMENTO.md).
#
# Copyright (c) 2026 Thiago Carrere - Licença MIT (ver LICENSE)
# Desenvolvido por Thiago Carrere em parceria com Claude (Anthropic).
#
# Uso:
#   gsb                abre o menu (precisa ser root)
#   gsb --ajuda        mostra a ajuda
#   gsb --versao       mostra a versão
#   source gsb.sh      carrega as funções sem executar nada (para testes)
#
# Códigos de saída:
#   0 sucesso | 1 erro | 2 uso incorreto | 130 interrompido (Ctrl+C)
#
# Seções do arquivo:
#   1. Versão e verificação do bash
#   2. Configuração
#   3. Mensagens (catálogo pt_BR / en)
#   4. Cores e saída
#   5. Utilitários
#   6. Funções
#   7. Menus
#   8. Linha de comando e início

# ════════════════════════════════════════════════════════════════════════════
# 1. VERSÃO E VERIFICAÇÃO DO BASH
# ════════════════════════════════════════════════════════════════════════════
# Esta verificação usa só sintaxe POSIX, para funcionar mesmo se o arquivo
# for executado por outro shell (ex: "sh gsb.sh").
if [ -z "${BASH_VERSINFO:-}" ]; then
    echo "gsb: este programa precisa do bash (execute: bash gsb.sh)" >&2
    exit 1
fi
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
    echo "gsb: é necessário bash 4.4 ou mais novo (atual: ${BASH_VERSION})" >&2
    exit 1
fi

GSB_VERSAO="0.1.0-dev"

# ════════════════════════════════════════════════════════════════════════════
# 2. CONFIGURAÇÃO
# ════════════════════════════════════════════════════════════════════════════
# Padrões; podem ser alterados em /etc/gsb/gsb.conf (ver gsb.conf.exemplo).
# O arquivo NÃO é executado: é lido linha a linha (CHAVE=valor), só chaves
# conhecidas são aceitas e cada valor é validado.

GSB_CONF_ARQUIVO="${GSB_CONF_ARQUIVO:-/etc/gsb/gsb.conf}"

# Chave -> valor padrão
declare -A GSB_CONF_PADRAO=(
    [IDIOMA]="pt_BR"
    [SENHA_MIN]="4"
    [GRUPO_USUARIOS]="gsb_usuarios"
    [PREFIXO_GRUPO]="gsb_"
    [SMB_CONF]="/etc/samba/smb.conf"
    [SHARES_CONF]="/etc/samba/gsb-shares.conf"
    [SSH_DROPIN]="/etc/ssh/sshd_config.d/gsb.conf"
    [LOG]="/var/log/gsb.log"
    [BACKUP_DIR]="/var/backups/gsb"
    [BACKUP_MANTER]="30"
    [TRAVA]="/run/gsb.lock"
)

# Chave -> tipo de validação
declare -A GSB_CONF_TIPO=(
    [IDIOMA]="idioma"
    [SENHA_MIN]="inteiro_1_128"
    [GRUPO_USUARIOS]="nome"
    [PREFIXO_GRUPO]="prefixo"
    [SMB_CONF]="caminho"
    [SHARES_CONF]="caminho"
    [SSH_DROPIN]="caminho"
    [LOG]="caminho"
    [BACKUP_DIR]="caminho"
    [BACKUP_MANTER]="inteiro_1_9999"
    [TRAVA]="caminho"
)

# Valida um valor conforme o tipo. Retorna 0 se válido.
gsb_conf_valor_valido() {
    local tipo="$1" valor="$2"
    case "$tipo" in
        idioma)         [[ "$valor" == "pt_BR" || "$valor" == "en" ]] ;;
        inteiro_1_128)  [[ "$valor" =~ ^[0-9]{1,3}$ ]] && [ "$valor" -ge 1 ] && [ "$valor" -le 128 ] ;;
        inteiro_1_9999) [[ "$valor" =~ ^[0-9]{1,4}$ ]] && [ "$valor" -ge 1 ] ;;
        nome)           [[ "$valor" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] ;;
        prefixo)        [[ "$valor" =~ ^[a-z_][a-z0-9_-]{0,15}$ ]] ;;
        caminho)        [[ "$valor" == /* && "$valor" != *..* && "$valor" =~ ^[A-Za-z0-9/._-]+$ ]] ;;
        *)              return 1 ;;
    esac
}

# Aplica os padrões nas variáveis GSB_<CHAVE>
gsb_conf_padroes() {
    local chave
    for chave in "${!GSB_CONF_PADRAO[@]}"; do
        printf -v "GSB_${chave}" '%s' "${GSB_CONF_PADRAO[$chave]}"
    done
}

# Lê o arquivo de configuração (se existir) por cima dos padrões.
# Erros vão para GSB_CONF_ERROS (um por linha); retorna 1 se houver erro.
# Chaves desconhecidas vão para GSB_CONF_AVISOS (não impedem o uso).
gsb_conf_carregar() {
    local arquivo="${1:-$GSB_CONF_ARQUIVO}" linha n=0 chave valor dono perm
    GSB_CONF_ERROS=""
    GSB_CONF_AVISOS=""
    gsb_conf_padroes
    [ -e "$arquivo" ] || return 0

    if [ ! -f "$arquivo" ] || [ ! -r "$arquivo" ]; then
        GSB_CONF_ERROS="$arquivo: não é um arquivo legível"
        return 1
    fi
    # Segurança: só root pode poder alterar o arquivo
    dono=$(stat -c '%u' -- "$arquivo")
    perm=$(stat -c '%a' -- "$arquivo")
    if [ "$dono" != "0" ] || (( 8#$perm & 8#022 )); then
        GSB_CONF_ERROS="$arquivo: precisa pertencer ao root e não ter escrita para grupo/outros (atual: dono UID $dono, permissão $perm)"
        return 1
    fi

    while IFS= read -r linha || [ -n "$linha" ]; do
        n=$((n + 1))
        linha="${linha%$'\r'}"
        [[ "$linha" =~ ^[[:space:]]*(#.*)?$ ]] && continue
        if [[ ! "$linha" =~ ^[[:space:]]*([A-Z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            GSB_CONF_ERROS+="linha $n: formato inválido (use CHAVE=valor)"$'\n'
            continue
        fi
        chave="${BASH_REMATCH[1]}"
        valor="${BASH_REMATCH[2]}"
        valor="${valor%"${valor##*[![:space:]]}"}"        # tira espaços do fim
        if [[ "$valor" =~ ^\"(.*)\"$ || "$valor" =~ ^\'(.*)\'$ ]]; then
            valor="${BASH_REMATCH[1]}"                    # tira aspas
        fi
        if [ -z "${GSB_CONF_TIPO[$chave]+x}" ]; then
            GSB_CONF_AVISOS+="linha $n: chave desconhecida '$chave' (ignorada)"$'\n'
            continue
        fi
        if ! gsb_conf_valor_valido "${GSB_CONF_TIPO[$chave]}" "$valor"; then
            GSB_CONF_ERROS+="linha $n: valor inválido para $chave: '$valor'"$'\n'
            continue
        fi
        printf -v "GSB_${chave}" '%s' "$valor"
    done < "$arquivo"

    GSB_CONF_ERROS="${GSB_CONF_ERROS%$'\n'}"
    GSB_CONF_AVISOS="${GSB_CONF_AVISOS%$'\n'}"
    [ -z "$GSB_CONF_ERROS" ]
}

# ════════════════════════════════════════════════════════════════════════════
# 3. MENSAGENS (catálogo)
# ════════════════════════════════════════════════════════════════════════════
# Todo texto visível sai daqui. Uso: t <chave> [argumentos do printf]
# Chave que faltar no idioma escolhido cai no pt_BR; se faltar nos dois,
# aparece a própria chave (facilita achar o que falta).

declare -A MSG_pt_BR=(
    [geral.titulo]="gsb - Gerenciador Samba"
    [geral.versao]="gsb %s"
    [geral.sim_nao]="(s/n)"
    [geral.escolha]="Escolha uma opção: "
    [geral.enter_voltar]="Pressione Enter para voltar..."
    [geral.opcao_invalida]="Opção inválida: '%s'"
    [geral.sair]="Sair"
    [geral.em_construcao]="(as funções serão adicionadas nas próximas etapas)"
    [geral.interrompido]="Interrompido. Nada mais foi feito."
    [erro.root]="Este comando precisa ser executado como root (ex: sudo gsb)."
    [erro.uso]="Opção desconhecida: '%s'. Veja: gsb --ajuda"
    [erro.conf]="Configuração inválida em %s:"
    [aviso.conf]="Avisos da configuração %s:"
    [erro.trava]="O gsb já está em uso por outra sessão (PID %s). Tente novamente quando ela terminar."
    [erro.trava_abrir]="Não foi possível criar o arquivo de trava %s."
    [ajuda.texto]="Uso: gsb [opção]

  (sem opção)    abre o menu interativo (precisa ser root)
  -h, --ajuda    mostra esta ajuda
  -v, --versao   mostra a versão

Configuração: %s
Documentação: docs/PLANEJAMENTO.md"
)

declare -A MSG_en=(
    [geral.titulo]="gsb - Samba Manager"
    [geral.versao]="gsb %s"
    [geral.sim_nao]="(y/n)"
    [geral.escolha]="Choose an option: "
    [geral.enter_voltar]="Press Enter to go back..."
    [geral.opcao_invalida]="Invalid option: '%s'"
    [geral.sair]="Exit"
    [geral.em_construcao]="(features will be added in the next steps)"
    [geral.interrompido]="Interrupted. Nothing else was done."
    [erro.root]="This command must be run as root (e.g. sudo gsb)."
    [erro.uso]="Unknown option: '%s'. See: gsb --help"
    [erro.conf]="Invalid configuration in %s:"
    [aviso.conf]="Configuration warnings in %s:"
    [erro.trava]="gsb is already in use by another session (PID %s). Try again when it finishes."
    [erro.trava_abrir]="Could not create the lock file %s."
    [ajuda.texto]="Usage: gsb [option]

  (no option)    opens the interactive menu (requires root)
  -h, --help     shows this help
  -v, --version  shows the version

Configuration: %s
Documentation: docs/PLANEJAMENTO.md"
)

# Imprime a mensagem <chave> formatada com os argumentos (sem quebra de linha)
t() {
    local chave="$1" formato
    shift
    if [ "${GSB_IDIOMA:-pt_BR}" == "en" ] && [ -n "${MSG_en[$chave]+x}" ]; then
        formato="${MSG_en[$chave]}"
    elif [ -n "${MSG_pt_BR[$chave]+x}" ]; then
        formato="${MSG_pt_BR[$chave]}"
    else
        formato="$chave"
    fi
    # shellcheck disable=SC2059  # o formato vem do catálogo (confiável)
    printf -- "$formato" "$@"
}

# ════════════════════════════════════════════════════════════════════════════
# 4. CORES E SAÍDA
# ════════════════════════════════════════════════════════════════════════════
gsb_cores() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
        C_VERDE=$'\033[0;32m'; C_AMARELO=$'\033[1;33m'; C_VERMELHO=$'\033[0;31m'
        C_CIANO=$'\033[0;36m'; C_CINZA=$'\033[0;90m'; C_NEGRITO=$'\033[1m'; C_RESET=$'\033[0m'
    else
        C_VERDE=""; C_AMARELO=""; C_VERMELHO=""; C_CIANO=""; C_CINZA=""; C_NEGRITO=""; C_RESET=""
    fi
}
gsb_cores

GSB_LINHA="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

msg_ok()    { printf '%s>> [OK]%s %s\n' "$C_VERDE" "$C_RESET" "$*"; }
msg_info()  { printf '%s>>%s %s\n' "$C_CIANO" "$C_RESET" "$*"; }
msg_aviso() { printf '%s>> [!]%s %s\n' "$C_AMARELO" "$C_RESET" "$*"; }
msg_erro()  { printf '%s>> [X]%s %s\n' "$C_VERMELHO" "$C_RESET" "$*" >&2; }

# Título de tela: limpa a tela (se for terminal) e mostra o título
titulo() {
    [ -t 1 ] && clear
    printf '%s%s%s\n' "$C_CIANO" "$GSB_LINHA" "$C_RESET"
    printf '%s  %s%s\n' "$C_NEGRITO" "$*" "$C_RESET"
    printf '%s%s%s\n' "$C_CIANO" "$GSB_LINHA" "$C_RESET"
}

# ════════════════════════════════════════════════════════════════════════════
# 5. UTILITÁRIOS
# ════════════════════════════════════════════════════════════════════════════

# Espera Enter antes de voltar ao menu
pausar() {
    echo ""
    read -rp "$(t geral.enter_voltar)" _ || true
}

# Pergunta sim/não. Retorna 0 só para s/S/y/Y (fim da entrada = não).
confirmar() {
    local resp
    read -rp "$1 $(t geral.sim_nao): " resp || return 1
    [[ "$resp" =~ ^[SsYy]$ ]]
}

# Lê uma opção de menu para a variável indicada. Fim da entrada (Ctrl+D)
# encerra o gsb, em vez de repetir o menu para sempre.
ler_opcao() {
    local -n _destino="$1"
    if ! read -rp "$(t geral.escolha)" _destino; then
        echo ""
        GSB_MOTIVO_SAIDA="fim_da_entrada"
        exit 0
    fi
}

# ── Arquivos temporários (apagados ao sair, mesmo com Ctrl+C) ───────────────
GSB_TEMPORARIOS=()

# Cria um arquivo temporário protegido (600) e imprime o caminho
gsb_temp() {
    local arq
    arq=$(umask 077; mktemp "${TMPDIR:-/tmp}/gsb.XXXXXX") || return 1
    GSB_TEMPORARIOS+=("$arq")
    echo "$arq"
}

gsb_limpar() {
    local arq
    for arq in "${GSB_TEMPORARIOS[@]}"; do
        [ -n "$arq" ] && rm -f -- "$arq"
    done
    GSB_TEMPORARIOS=()
}

# ── Saída: roda SEMPRE (trap EXIT), seja qual for o jeito de sair ───────────
# Apaga temporários e, se havia sessão aberta, registra no log como ela
# terminou (normal, interrompida, fim_da_entrada). Assim a auditoria nunca
# fica com um "início" sem "fim".
GSB_SESSAO_ATIVA=0
GSB_MOTIVO_SAIDA="normal"

gsb_ao_sair() {
    gsb_limpar
    if [ "$GSB_SESSAO_ATIVA" -eq 1 ]; then
        gsb_auditar sessao_fim "motivo=$GSB_MOTIVO_SAIDA"
        GSB_SESSAO_ATIVA=0
    fi
}

# ── Trava: uma execução do gsb por vez ──────────────────────────────────────
# Mantém o descritor aberto até o fim do processo (o sistema libera sozinho).
gsb_travar() {
    local pid
    if ! { exec {GSB_FD_TRAVA}>>"$GSB_TRAVA"; } 2>/dev/null; then
        msg_erro "$(t erro.trava_abrir "$GSB_TRAVA")"
        return 1
    fi
    if ! flock -n "$GSB_FD_TRAVA"; then
        pid=$(head -c 20 -- "$GSB_TRAVA" 2>/dev/null | tr -cd '0-9')
        msg_erro "$(t erro.trava "${pid:-?}")"
        return 1
    fi
    : > "$GSB_TRAVA"
    echo "$$" > "$GSB_TRAVA"
}

# ── Log de auditoria ────────────────────────────────────────────────────────
# Registra: data/hora, quem (usuário real, mesmo via sudo), PID, ação e
# detalhes. NUNCA passar senhas. Quebras de linha viram espaço (impede
# forjar linhas falsas no log). Retorna 1 se não conseguir gravar.
gsb_auditar() {
    local acao="$1" quem detalhes
    shift
    quem="${SUDO_USER:-$(logname 2>/dev/null || id -un)}"
    detalhes="$*"
    detalhes="${detalhes//$'\n'/ }"
    detalhes="${detalhes//$'\r'/ }"
    acao="${acao//[$'\n\r ']/_}"
    ( umask 027; printf '%s %s[%s] %s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$quem" "$$" "$acao" "$detalhes" >> "$GSB_LOG" ) 2>/dev/null
}

# ════════════════════════════════════════════════════════════════════════════
# 6. FUNÇÕES
# ════════════════════════════════════════════════════════════════════════════
# (adicionadas nas próximas etapas)

# ════════════════════════════════════════════════════════════════════════════
# 7. MENUS
# ════════════════════════════════════════════════════════════════════════════
menu_principal() {
    local opcao
    while true; do
        titulo "$(t geral.titulo)  ${C_CINZA}v${GSB_VERSAO}${C_RESET}"
        echo "  $(t geral.em_construcao)"
        echo ""
        echo "  0) $(t geral.sair)"
        echo ""
        ler_opcao opcao
        case "$opcao" in
            "") continue ;;
            0) [ -t 1 ] && clear; return 0 ;;
            *) msg_erro "$(t geral.opcao_invalida "$opcao")"; pausar ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════════════════════
# 8. LINHA DE COMANDO E INÍCIO
# ════════════════════════════════════════════════════════════════════════════

# Carrega a configuração mostrando avisos/erros. Retorna 1 se inválida.
gsb_iniciar_conf() {
    if ! gsb_conf_carregar "$GSB_CONF_ARQUIVO"; then
        msg_erro "$(t erro.conf "$GSB_CONF_ARQUIVO")"
        printf '%s\n' "$GSB_CONF_ERROS" | sed 's/^/     /' >&2
        return 1
    fi
    if [ -n "$GSB_CONF_AVISOS" ]; then
        msg_aviso "$(t aviso.conf "$GSB_CONF_ARQUIVO")"
        printf '%s\n' "$GSB_CONF_AVISOS" | sed 's/^/     /'
    fi
}

main() {
    # Idioma por variável de ambiente tem prioridade (útil em testes)
    local idioma_env="${GSB_IDIOMA:-}"

    # Ajuda e versão funcionam mesmo com a configuração com erro (é
    # justamente quando o administrador mais precisa delas)
    case "${1:-}" in
        -h|--ajuda|--help|-v|--versao|--version)
            gsb_conf_carregar "$GSB_CONF_ARQUIVO" || gsb_conf_padroes
            if [ -n "$idioma_env" ] && gsb_conf_valor_valido idioma "$idioma_env"; then
                GSB_IDIOMA="$idioma_env"
            fi
            case "$1" in
                -h|--ajuda|--help) t ajuda.texto "$GSB_CONF_ARQUIVO"; echo ;;
                *)                 t geral.versao "$GSB_VERSAO"; echo ;;
            esac
            exit 0 ;;
    esac

    gsb_iniciar_conf || exit 1
    if [ -n "$idioma_env" ] && gsb_conf_valor_valido idioma "$idioma_env"; then
        GSB_IDIOMA="$idioma_env"
    fi

    if [ -n "${1:-}" ]; then
        msg_erro "$(t erro.uso "$1")"
        exit 2
    fi

    if [ "$EUID" -ne 0 ]; then
        msg_erro "$(t erro.root)"
        exit 1
    fi

    trap gsb_ao_sair EXIT
    trap 'echo; msg_aviso "$(t geral.interrompido)"; GSB_MOTIVO_SAIDA="interrompida"; exit 130' INT TERM

    gsb_travar || exit 1
    gsb_auditar sessao_inicio "v$GSB_VERSAO"
    GSB_SESSAO_ATIVA=1
    menu_principal
}

# Só executa quando chamado diretamente; com "source" apenas carrega
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
