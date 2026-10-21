#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  debkit - instalador                                                     ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# Instala (ou atualiza) o debkit neste servidor (tarefa 4.3; seção 3.9 do
# planejamento):
#   - programa em /opt/debkit (só o programa: debkit, lib/, modulos/, docs/
#     e os textos; os testes e o dev/ ficam de fora), dono root, sem escrita
#     para grupo/outros (o debkit se recusa a carregar código que outra
#     pessoa possa alterar);
#   - comando /usr/local/sbin/debkit (link para /opt/debkit/debkit).
# Três casos: instalação nova; atualização de uma instalação feita por este
# instalador (marca .debkit-instalado; a pasta é trocada de uma vez); ou o
# repositório clonado direto em /opt/debkit (aí só confere dono/permissões
# e cria o comando). Nunca sobrescreve pasta ou comando que não sejam do
# debkit. A configuração (/etc/debkit), o log e os backups não são tocados.
# No fim, oferece preparar o servidor (debkit --preparar).
#
# Uso: sudo ./install.sh [--sim] [--simular]
# Desinstalar: debkit --desinstalar
#
# Copyright (c) 2026 Thiago Carrere - Licença MIT (ver LICENSE)
# Desenvolvido por Thiago Carrere em parceria com Claude (Anthropic).

# Só sintaxe POSIX até conferir o bash (pode ser chamado com "sh install.sh")
if [ -z "${BASH_VERSINFO:-}" ]; then
    echo "install.sh: este programa precisa do bash (execute: sudo bash install.sh)" >&2
    exit 1
fi
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
    echo "install.sh: é necessário bash 4.4 ou mais novo (atual: ${BASH_VERSION})" >&2
    exit 1
fi

ORIGEM="$(cd "$(dirname "$(realpath -- "${BASH_SOURCE[0]}")")" && pwd)"
# Os testes instalam no sandbox
DESTINO="${DEBKIT_INSTALAR_DIR:-/opt/debkit}"
LINK="${DEBKIT_INSTALAR_LINK:-/usr/local/sbin/debkit}"
MARCA=".debkit-instalado"
# O que vai para a instalação (o resto do repositório não)
ARQUIVOS=(debkit install.sh debkit.conf.exemplo LICENSE README.md CHANGELOG.md)
PASTAS=(lib modulos docs)

if [ ! -f "$ORIGEM/debkit" ] || [ ! -f "$ORIGEM/lib/nucleo.sh" ]; then
    echo "install.sh: $ORIGEM não tem o debkit completo (debkit e lib/nucleo.sh)" >&2
    exit 1
fi
# Mensagens, saída, confirmação e auditoria vêm do núcleo do debkit (o
# idioma por variável de ambiente vale, como no debkit)
idioma_env="${DEBKIT_IDIOMA:-}"
# shellcheck source=SCRIPTDIR/lib/nucleo.sh
source "$ORIGEM/lib/nucleo.sh"
debkit_conf_carregar "$DEBKIT_CONF_ARQUIVO" >/dev/null 2>&1 || debkit_conf_padroes
if [ -n "$idioma_env" ] && debkit_conf_valor_valido idioma "$idioma_env"; then DEBKIT_IDIOMA="$idioma_env"; fi
DEBKIT_CLI=1    # sem limpar a tela

DEBKIT_SIM=0; simular=0
for arg in "$@"; do
    case "$arg" in
        --sim|--yes)         DEBKIT_SIM=1 ;;
        --simular|--dry-run) simular=1 ;;
        -h|--ajuda|--help)   t inst.ajuda "$DESTINO" "$LINK"; echo; exit 0 ;;
        *)                   msg_erro "$(t inst.opcao "$arg")"; exit 2 ;;
    esac
done
if [ "$EUID" -ne 0 ]; then msg_erro "$(t erro.root)"; exit 1; fi

# ── O que fazer ──────────────────────────────────────────────────────────────
if ! debkit_conf_valor_valido caminho "$DESTINO" || ! debkit_conf_valor_valido caminho "$LINK" \
   || [ "$DESTINO" == "/" ]; then
    msg_erro "$(t inst.destino_invalido "$DESTINO")"; exit 1
fi
DESTINO="${DESTINO%/}"
real_destino=$(realpath -m -- "$DESTINO")
if [ "$real_destino" == "$ORIGEM" ]; then
    modo=no_lugar
else
    if [[ "$real_destino/" == "$ORIGEM/"* || "$ORIGEM/" == "$real_destino/"* ]]; then
        msg_erro "$(t inst.dentro "$DESTINO" "$ORIGEM")"; exit 1
    fi
    if [ -L "$DESTINO" ] || { [ -e "$DESTINO" ] && [ ! -d "$DESTINO" ]; }; then
        msg_erro "$(t inst.destino_alheio "$DESTINO")"; exit 1
    elif [ -f "$DESTINO/$MARCA" ]; then
        modo=atualizar
        versao_antiga=$(sed -n 's/^versao=//p' "$DESTINO/$MARCA" | head -1)
    elif [ -d "$DESTINO/.git" ] && [ -f "$DESTINO/debkit" ]; then
        msg_erro "$(t inst.destino_git "$DESTINO" "$DESTINO")"; exit 1
    elif [ -d "$DESTINO" ] && [ -n "$(ls -A -- "$DESTINO")" ]; then
        msg_erro "$(t inst.destino_alheio "$DESTINO")"; exit 1
    else
        modo=novo
    fi
fi
link_ok=0
if [ -L "$LINK" ]; then
    if [ "$(readlink -- "$LINK")" == "$DESTINO/debkit" ]; then
        link_ok=1
    else
        msg_erro "$(t inst.link_alheio "$LINK" "$DESTINO/debkit")"; exit 1
    fi
elif [ -e "$LINK" ]; then
    msg_erro "$(t inst.link_alheio "$LINK" "$DESTINO/debkit")"; exit 1
fi

# ── Plano e UMA confirmação ─────────────────────────────────────────────────
titulo "$(t inst.titulo "$DEBKIT_VERSAO")"
printf '  %s%s%s\n' "$C_NEGRITO" "$(t inst.plano)" "$C_RESET"
case "$modo" in
    novo)      printf '    • %s\n' "$(t inst.p_novo "$DEBKIT_VERSAO" "$DESTINO")" ;;
    atualizar) printf '    • %s\n' "$(t inst.p_atualizar "$DESTINO" "${versao_antiga:-?}" "$DEBKIT_VERSAO" "$(debkit_dir_conf)")" ;;
    no_lugar)  printf '    • %s\n' "$(t inst.p_no_lugar "$DESTINO")" ;;
esac
if [ "$link_ok" -eq 1 ]; then
    printf '    · %s\n' "$(t inst.link_ok "$LINK")"
else
    printf '    • %s\n' "$(t inst.p_link "$LINK" "$DESTINO/debkit")"
fi
echo ""
if [ "$simular" -eq 1 ]; then t inst.simulacao; echo; exit 0; fi
if ! confirmar "$(t inst.pergunta)"; then msg_aviso "$(t inst.cancelado)"; exit 1; fi

# Falha: avisa e sai (o que estava antes não foi trocado)
falhou() { msg_erro "$(t inst.falhou "$1" "$DESTINO")"; [ -n "${novo:-}" ] && rm -rf -- "$novo"; exit 1; }

# Dono root e sem escrita para grupo/outros em tudo (pastas 755, arquivos
# 644, os executáveis 755). No repositório clonado no lugar, só o mínimo:
# dono root e sem escrita para grupo/outros (o resto fica como o git deixou).
permissoes_minimas() { chown -R 0:0 -- "$1" && chmod -R go-w -- "$1"; }
permissoes() {
    chown -R 0:0 -- "$1" \
        && find "$1" -type d -exec chmod 755 {} + \
        && find "$1" -type f ! -perm -u+x -exec chmod 644 {} + \
        && find "$1" -type f -perm -u+x -exec chmod 755 {} +
}

# ── Programa ─────────────────────────────────────────────────────────────────
novo=""
case "$modo" in
    novo|atualizar)
        mkdir -p -- "$(dirname -- "$DESTINO")" || falhou "$(t inst.f_copiar)"
        novo=$(mktemp -d -- "$(dirname -- "$DESTINO")/.debkit-novo.XXXXXX") || falhou "$(t inst.f_copiar)"
        for f in "${ARQUIVOS[@]}"; do
            [ -f "$ORIGEM/$f" ] || continue
            cp -- "$ORIGEM/$f" "$novo/$f" || falhou "$(t inst.f_copiar)"
        done
        for d in "${PASTAS[@]}"; do
            [ -d "$ORIGEM/$d" ] || continue
            cp -R -- "$ORIGEM/$d" "$novo/$d" || falhou "$(t inst.f_copiar)"
        done
        chmod 755 -- "$novo/debkit" "$novo/install.sh" 2>/dev/null
        printf 'versao=%s\ndata=%s\norigem=%s\n' "$DEBKIT_VERSAO" "$(date '+%Y-%m-%d %H:%M')" "$ORIGEM" > "$novo/$MARCA" \
            || falhou "$(t inst.f_copiar)"
        permissoes "$novo" || falhou "$(t inst.f_permissoes)"
        # A cópia funciona? (o debkit confere dono e permissões ao carregar)
        [ "$(bash "$novo/debkit" --versao 2>/dev/null)" == "$(t geral.versao "$DEBKIT_VERSAO")" ] || falhou "$(t inst.f_conferir)"
        # Troca: a pasta antiga sai de uma vez (e volta se a nova não entrar)
        if [ -d "$DESTINO" ]; then
            antiga="$DESTINO.antigo.$$"
            mv -T -- "$DESTINO" "$antiga" || falhou "$(t inst.f_trocar)"
            if ! mv -T -- "$novo" "$DESTINO"; then
                mv -T -- "$antiga" "$DESTINO"; falhou "$(t inst.f_trocar)"
            fi
            rm -rf -- "$antiga"
        else
            mv -T -- "$novo" "$DESTINO" || falhou "$(t inst.f_trocar)"
        fi
        novo="" ;;
    no_lugar)
        permissoes_minimas "$DESTINO" || falhou "$(t inst.f_permissoes)" ;;
esac

# ── Comando ──────────────────────────────────────────────────────────────────
if [ "$link_ok" -eq 0 ]; then
    if ! mkdir -p -- "$(dirname -- "$LINK")" || ! ln -s -- "$DESTINO/debkit" "$LINK"; then
        msg_erro "$(t inst.f_link "$LINK")"; exit 1
    fi
fi
if [ "$("$LINK" --versao 2>/dev/null)" != "$(t geral.versao "$DEBKIT_VERSAO")" ]; then
    msg_erro "$(t inst.f_link "$LINK")"; exit 1
fi
debkit_auditar instalar "versao=$DEBKIT_VERSAO modo=$modo destino=$DESTINO comando=$LINK${versao_antiga:+ versao_antiga=$versao_antiga}"
msg_ok "$(t inst.ok "$DEBKIT_VERSAO" "$DESTINO" "$LINK")"

# ── Preparar o servidor ──────────────────────────────────────────────────────
echo ""
if confirmar "$(t inst.p_preparar)"; then
    sim=(); [ "$DEBKIT_SIM" -eq 1 ] && sim=(--sim)
    "$LINK" --preparar "${sim[@]}"
    exit $?
fi
msg_info "$(t inst.depois)"
exit 0
