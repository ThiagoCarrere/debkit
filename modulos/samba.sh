# shellcheck shell=bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  debkit - módulo samba                                                   ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# Servidor de arquivos Samba (modo standalone, base de senhas tdbsam).
# Nesta etapa: dependências, verificação e preparação do Samba, backups do
# smb.conf (SMB_BACKUP_DIR, com rotação) e a edição segura do smb.conf
# (debkit_smbconf_editar). Usuários, grupos e compartilhamentos vêm nas
# próximas tarefas (ver docs/PLANEJAMENTO.md, seções 3, 4 e 6).
#
# Carregado pelo programa debkit depois do núcleo (lib/nucleo.sh).
#
# Copyright (c) 2026 Thiago Carrere - Licença MIT (ver LICENSE)

debkit_modulo_registrar samba

# ── Configuração ────────────────────────────────────────────────────────────
# shellcheck disable=SC2034  # tabelas do núcleo
{
    DEBKIT_CONF_PADRAO[SMB_CONF]="/etc/samba/smb.conf"
    DEBKIT_CONF_PADRAO[SMB_BACKUP_DIR]="/etc/samba/conf-bkp"
    DEBKIT_CONF_TIPO[SMB_CONF]="caminho"
    DEBKIT_CONF_TIPO[SMB_BACKUP_DIR]="caminho"
    DEBKIT_CONF_ORDEM+=(SMB_CONF SMB_BACKUP_DIR)
}

# ── Mensagens ───────────────────────────────────────────────────────────────
# shellcheck disable=SC2034  # catálogo do núcleo
MSG_pt_BR+=(
    [menu.samba]="Samba: usuários, grupos e compartilhamentos"
    [samba.titulo]="Samba"
    [amb.grupo_samba]="Samba"
    [amb.samba_ausente]="Samba não instalado"
    [amb.servico_nao_encontrado]="Serviço do Samba (%s) não encontrado no systemd"
    [amb.smbconf_ausente]="%s não existe"
    [amb.smbconf_invalido]="%s com erro (veja: testparm)"
    [amb.smbconf_ok]="%s válido"
    [amb.papel_ok]="Modo: servidor de arquivos independente (standalone)"
    [amb.papel_dc]="Modo: %s - controlador de domínio NÃO é suportado pelo debkit"
    [amb.papel_outro]="Modo: %s (não testado com o debkit)"
    [amb.backend_ok]="Base de senhas: %s"
    [amb.backend_outro]="Base de senhas: %s - não suportada (o debkit usa tdbsam)"
    [amb.include_antigo]="%s ainda tem a linha antiga \"include = %s\" do debkit (agora o debkit edita o smb.conf diretamente): a preparação vai removê-la"
    [amb.include_antigo_ocupado]="%s tem a linha antiga \"include = %s\" do debkit e esse arquivo tem conteúdo: mova os compartilhamentos para o smb.conf e apague a linha (o debkit não faz isso sozinho)"
    [prep.d_samba_servico]="Deixar o serviço do Samba ativo e iniciando junto com o sistema"
    [prep.d_samba_include_antigo]="Remover do %s a linha antiga \"include = %s\" e o arquivo antigo, vazio (com backup e conferência de que nada mais muda no Samba)"
    [prep.mantido_servico]="O serviço do Samba foi mantido ligado."
    [prep.recarregar_falhou]="Não foi possível recarregar o Samba."
    [smb.testparm]="Com a alteração, o %s ficaria inválido (testparm). Nada foi alterado."
    [smb.conferencia]="A alteração mudaria no %s mais do que o pretendido. Nada foi alterado."
    [smb.gravar_falhou]="Não foi possível gravar o %s. Nada foi alterado."
    [smb.restaurado]="%s restaurado do backup %s."
    [smb.restaurar_falhou]="ATENÇÃO: não foi possível restaurar o %s do backup %s. Restaure à mão."
)
# shellcheck disable=SC2034  # catálogo do núcleo
MSG_en+=(
    [menu.samba]="Samba: users, groups and shares"
    [samba.titulo]="Samba"
    [amb.grupo_samba]="Samba"
    [amb.samba_ausente]="Samba is not installed"
    [amb.servico_nao_encontrado]="Samba service (%s) not found in systemd"
    [amb.smbconf_ausente]="%s does not exist"
    [amb.smbconf_invalido]="%s has errors (see: testparm)"
    [amb.smbconf_ok]="%s is valid"
    [amb.papel_ok]="Role: standalone file server"
    [amb.papel_dc]="Role: %s - domain controllers are NOT supported by debkit"
    [amb.papel_outro]="Role: %s (not tested with debkit)"
    [amb.backend_ok]="Password backend: %s"
    [amb.backend_outro]="Password backend: %s - not supported (debkit uses tdbsam)"
    [amb.include_antigo]="%s still has the old debkit line \"include = %s\" (debkit now edits smb.conf directly): the setup will remove it"
    [amb.include_antigo_ocupado]="%s has the old debkit line \"include = %s\" and that file has content: move the shares into smb.conf and delete the line (debkit will not do it by itself)"
    [prep.d_samba_servico]="Make the Samba service active and start at boot"
    [prep.d_samba_include_antigo]="Remove from %s the old line \"include = %s\" and the old, empty file (with backup and a check that nothing else changes in Samba)"
    [prep.mantido_servico]="The Samba service was kept running."
    [prep.recarregar_falhou]="Could not reload Samba."
    [smb.testparm]="With the change, %s would become invalid (testparm). Nothing was changed."
    [smb.conferencia]="The change would alter more than intended in %s. Nothing was changed."
    [smb.gravar_falhou]="Could not write %s. Nothing was changed."
    [smb.restaurado]="%s restored from the backup %s."
    [smb.restaurar_falhou]="WARNING: could not restore %s from the backup %s. Restore it by hand."
)

# ── Dependências (comando | tipo | pacote no Debian; ver núcleo) ───────────
DEBKIT_DEPENDENCIAS+=(
    "smbd|essencial|samba"
    "pdbedit|essencial|samba"
    "smbstatus|essencial|samba"
    "testparm|essencial|samba-common-bin"
    "smbpasswd|essencial|samba-common-bin"
    "smbcontrol|essencial|samba-common-bin"
    "smbclient|desenvolvimento|smbclient"
)

# ── Detecção ────────────────────────────────────────────────────────────────
# Lê um parâmetro do Samba já interpretado pelo testparm (ex: "server role")
debkit_samba_param() {
    testparm -s --parameter-name="$1" "$DEBKIT_SMB_CONF" 2>/dev/null
}

# Modo efetivo do Samba. Com "server role = auto" (padrão quando a linha não
# existe) o modo real vem do "security": AUTO/USER = servidor independente,
# ADS/DOMAIN = membro de domínio.
debkit_samba_papel_efetivo() {
    local papel seguranca
    papel=$(debkit_samba_param "server role")
    if [ "$papel" == "auto" ]; then
        seguranca=$(debkit_samba_param "security")
        case "${seguranca^^}" in
            AUTO|USER)  papel="standalone server" ;;
            ADS|DOMAIN) papel="member server" ;;
        esac
    fi
    echo "$papel"
}

# Recarrega o Samba (só se o serviço estiver ativo)
debkit_samba_recarregar() {
    [ -n "$DEBKIT_SVC_SAMBA" ] || DEBKIT_SVC_SAMBA=$(debkit_descobrir_servico smbd smb) || return 0
    debkit_servico_ativo "$DEBKIT_SVC_SAMBA" || return 0
    systemctl reload "$DEBKIT_SVC_SAMBA.service"
}

# ── "include" antigo (versões anteriores do debkit) ─────────────────────────
# Antes, a preparação criava um arquivo só de compartilhamentos do debkit
# (SHARES_CONF, ex: /etc/samba/debkit-shares.conf) e acrescentava ao
# smb.conf uma linha em branco, a marca abaixo e "include = <arquivo>".
# Agora o smb.conf é editado diretamente: a preparação remove essas linhas
# (só se o arquivo não tem compartilhamentos) e o arquivo antigo (só se tem
# o cabeçalho do debkit e está na mesma pasta do smb.conf).
# NÃO mudar os textos: identificam o que versões anteriores escreveram.
DEBKIT_SAMBA_MARCA_INCLUDE="# debkit - Gerenciador Samba: compartilhamentos do debkit (não remova esta linha)"
DEBKIT_SAMBA_CABECALHO_SHARES="# Compartilhamentos gerenciados pelo debkit (Gerenciador Samba)."

# Imprime o caminho do "include" que vem logo depois da marca do debkit.
# Retorna 1 se não houver.
debkit_samba_include_antigo() {
    [ -f "$DEBKIT_SMB_CONF" ] || return 1
    awk -v m="$DEBKIT_SAMBA_MARCA_INCLUDE" '
        marca && /^[ \t]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][ \t]*=/ {
            v = $0; sub(/^[^=]*=[ \t]*/, "", v); sub(/[ \t\r]+$/, "", v)
            print v; achou = 1; exit
        }
        { marca = ($0 == m) }
        END { exit !achou }' "$DEBKIT_SMB_CONF"
}

# O arquivo não tem compartilhamentos (ausente, ou só comentários e linhas
# em branco)? Arquivo ilegível ou que não é arquivo comum = não.
debkit_samba_shares_vazio() {
    [ ! -e "$1" ] && [ ! -L "$1" ] && return 0
    [ -f "$1" ] && [ -r "$1" ] && ! grep -qvE '^[[:space:]]*([#;].*)?$' -- "$1"
}

# O arquivo foi criado pelo debkit (cabeçalho) e está na pasta do smb.conf?
debkit_samba_shares_nosso() {
    [ -f "$1" ] && [ ! -L "$1" ] || return 1
    [ "$(head -n 1 -- "$1")" == "$DEBKIT_SAMBA_CABECALHO_SHARES" ] || return 1
    [ "$(dirname -- "$(realpath -- "$1")")" == "$(dirname -- "$(realpath -- "$DEBKIT_SMB_CONF")")" ]
}

# Filtro (entrada -> saída): tira a marca, o "include" logo depois dela e
# a linha em branco logo antes dela (exatamente o que a versão antiga
# acrescentou).
debkit_samba_filtro_sem_include_antigo() {
    awk -v m="$DEBKIT_SAMBA_MARCA_INCLUDE" '
        { l[NR] = $0 }
        END {
            for (i = 1; i <= NR; i++)
                if (l[i] == m && i < NR && l[i + 1] ~ /^[ \t]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][ \t]*=/) {
                    fora[i] = 1; fora[i + 1] = 1
                    if (i > 1 && l[i - 1] ~ /^[ \t]*$/) fora[i - 1] = 1
                }
            for (i = 1; i <= NR; i++) if (!(i in fora)) print l[i]
        }'
}

# Conferência: a configuração em vigor (testparm -s) depois é igual à de
# antes sem a linha do include antigo - ou seja, só ela saiu.
debkit_samba_conferir_sem_include() {
    cmp -s <(awk -v p="$DEBKIT_SAMBA_INCLUDE_ANTIGO" \
                 '{ s = $0; sub(/^[ \t]+/, "", s); if (s == "include = " p) next; print }' "$1") "$2"
}

# ── Verificação (gancho) ────────────────────────────────────────────────────
# Deixa prontos para a preparação:
#   DEBKIT_SVC_SAMBA             nome do serviço (vazio se não encontrado)
#   DEBKIT_SAMBA_INCLUDE_ANTIGO  arquivo do "include" antigo do debkit (ou vazio)
#   DEBKIT_SAMBA_INCLUDE_VAZIO   1 se esse arquivo não tem compartilhamentos
debkit_samba_verificar() {
    local papel backend
    DEBKIT_SVC_SAMBA=""; DEBKIT_SAMBA_INCLUDE_ANTIGO=""; DEBKIT_SAMBA_INCLUDE_VAZIO=0
    if ! debkit_tem_comando smbd; then
        debkit_verif_add samba falta "$(t amb.samba_ausente)"
        return 0
    fi
    if DEBKIT_SVC_SAMBA=$(debkit_descobrir_servico smbd smb); then
        if debkit_servico_ativo "$DEBKIT_SVC_SAMBA"; then
            debkit_verif_add samba ok "$(t amb.servico_ativo "$DEBKIT_SVC_SAMBA")"
        else
            debkit_verif_add samba aviso "$(t amb.servico_parado "$DEBKIT_SVC_SAMBA")"
        fi
        debkit_servico_habilitado "$DEBKIT_SVC_SAMBA" || debkit_verif_add samba aviso "$(t amb.servico_desabilitado "$DEBKIT_SVC_SAMBA")"
    else
        debkit_verif_add samba aviso "$(t amb.servico_nao_encontrado "smbd/smb")"
    fi

    if [ ! -f "$DEBKIT_SMB_CONF" ]; then
        debkit_verif_manual samba "$(t amb.smbconf_ausente "$DEBKIT_SMB_CONF")"
    elif ! debkit_tem_comando testparm; then
        :   # já listado como dependência faltando
    elif ! testparm -s "$DEBKIT_SMB_CONF" >/dev/null 2>&1; then
        debkit_verif_manual samba "$(t amb.smbconf_invalido "$DEBKIT_SMB_CONF")"
    else
        debkit_verif_add samba ok "$(t amb.smbconf_ok "$DEBKIT_SMB_CONF")"
        papel=$(debkit_samba_papel_efetivo)
        case "$papel" in
            "standalone server") debkit_verif_add samba ok "$(t amb.papel_ok)" ;;
            *"domain controller"*) debkit_verif_manual samba "$(t amb.papel_dc "$papel")" ;;
            *) debkit_verif_add samba aviso "$(t amb.papel_outro "$papel")" ;;
        esac
        backend=$(debkit_samba_param "passdb backend")
        if [ "$backend" == "tdbsam" ]; then
            debkit_verif_add samba ok "$(t amb.backend_ok "$backend")"
        else
            debkit_verif_manual samba "$(t amb.backend_outro "$backend")"
        fi
        if DEBKIT_SAMBA_INCLUDE_ANTIGO=$(debkit_samba_include_antigo); then
            if debkit_samba_shares_vazio "$DEBKIT_SAMBA_INCLUDE_ANTIGO"; then
                DEBKIT_SAMBA_INCLUDE_VAZIO=1
                debkit_verif_add samba aviso "$(t amb.include_antigo "$DEBKIT_SMB_CONF" "$DEBKIT_SAMBA_INCLUDE_ANTIGO")"
            else
                debkit_verif_add samba aviso "$(t amb.include_antigo_ocupado "$DEBKIT_SMB_CONF" "$DEBKIT_SAMBA_INCLUDE_ANTIGO")"
            fi
        fi
    fi
}

# ── Preparação (gancho e ações) ─────────────────────────────────────────────
debkit_samba_plano() {
    # Serviço: se o Samba vai ser instalado agora, o estado só se sabe depois
    if [[ " ${DEBKIT_PLANO[*]} " == *" pacotes "* ]] || [ -z "$DEBKIT_SVC_SAMBA" ] \
       || ! debkit_servico_ativo "$DEBKIT_SVC_SAMBA" || ! debkit_servico_habilitado "$DEBKIT_SVC_SAMBA"; then
        DEBKIT_PLANO+=(samba_servico)
    fi
    if [ "${DEBKIT_SAMBA_INCLUDE_VAZIO:-0}" -eq 1 ]; then
        DEBKIT_PLANO+=(samba_include_antigo)
    fi
    return 0
}

debkit_descrever_samba_servico() { t prep.d_samba_servico; }

debkit_acao_samba_servico() {
    if ! DEBKIT_SVC_SAMBA=$(debkit_descobrir_servico smbd smb); then
        msg_erro "$(t amb.servico_nao_encontrado "smbd/smb")"
        return 1
    fi
    if ! debkit_servico_habilitado "$DEBKIT_SVC_SAMBA"; then
        systemctl enable "$DEBKIT_SVC_SAMBA.service" >/dev/null 2>&1 || true
    fi
    if ! debkit_servico_ativo "$DEBKIT_SVC_SAMBA"; then
        systemctl start "$DEBKIT_SVC_SAMBA.service" >/dev/null 2>&1 || true
    fi
    debkit_servico_ativo "$DEBKIT_SVC_SAMBA" && debkit_servico_habilitado "$DEBKIT_SVC_SAMBA" && return 0
    msg_erro "$(t prep.servico_falhou "$DEBKIT_SVC_SAMBA" "$DEBKIT_SVC_SAMBA")"
    return 1
}

# O serviço ligado não é desligado (desligar no meio de uma falha arriscaria
# derrubar quem já usa o Samba): só informa.
debkit_desfazer_samba_servico() {
    if [ -n "$DEBKIT_SVC_SAMBA" ] && debkit_servico_ativo "$DEBKIT_SVC_SAMBA"; then
        msg_aviso "$(t prep.mantido_servico)"
    fi
}

debkit_descrever_samba_include_antigo() {
    t prep.d_samba_include_antigo "$DEBKIT_SMB_CONF" "$DEBKIT_SAMBA_INCLUDE_ANTIGO"
}

debkit_acao_samba_include_antigo() {
    local arq="$DEBKIT_SAMBA_INCLUDE_ANTIGO"
    DEBKIT_SAMBA_SHARES_BACKUP=""
    [ -n "$arq" ] && debkit_samba_shares_vazio "$arq" || return 1
    debkit_smbconf_editar debkit_samba_filtro_sem_include_antigo debkit_samba_conferir_sem_include || return 1
    if debkit_samba_shares_nosso "$arq"; then
        DEBKIT_SAMBA_SHARES_BACKUP=$(debkit_backup "$arq") || return 1
        rm -f -- "$arq" || return 1
    fi
    ! debkit_samba_include_antigo >/dev/null
}

# Volta o arquivo antigo (se foi apagado) e o smb.conf (se foi trocado)
debkit_desfazer_samba_include_antigo() {
    if [ -n "${DEBKIT_SAMBA_SHARES_BACKUP:-}" ] && [ ! -e "$DEBKIT_SAMBA_INCLUDE_ANTIGO" ]; then
        cp -- "$DEBKIT_SAMBA_SHARES_BACKUP" "$DEBKIT_SAMBA_INCLUDE_ANTIGO" && chmod 644 -- "$DEBKIT_SAMBA_INCLUDE_ANTIGO"
    fi
    DEBKIT_SAMBA_SHARES_BACKUP=""
    debkit_smbconf_restaurar
}

# ── smb.conf: backup e edição segura ────────────────────────────────────────
# Backup do smb.conf em SMB_BACKUP_DIR (smb.conf.dd-mm-aaaa-hh-mm-ss, com a
# rotação do núcleo). Imprime o caminho.
debkit_samba_backup() { debkit_backup "$DEBKIT_SMB_CONF" "$DEBKIT_SMB_BACKUP_DIR"; }

# debkit_smbconf_editar <transformar> <conferir>
# Única forma de o debkit alterar o smb.conf (decisão da seção 4):
#   1. backup em SMB_BACKUP_DIR;
#   2. arquivo novo, num temporário na mesma pasta: "<transformar>" lê o
#      smb.conf atual na entrada e escreve o novo na saída;
#   3. testparm do novo (precisa ser válido);
#   4. "<conferir> <antes> <depois>" recebe a configuração em vigor
#      (testparm -s) de antes e de depois e retorna 0 se só mudou o pretendido;
#   5. troca atômica (rename), mantendo dono e permissões;
#   6. recarrega o Samba; se falhar, restaura o backup.
# Até o passo 5 nada muda no smb.conf. Deixa DEBKIT_SMB_BACKUP (caminho do
# backup) e DEBKIT_SMB_TROCADO=1 se o arquivo foi trocado e continua trocado
# (para debkit_smbconf_restaurar desfazer depois, se preciso).
debkit_smbconf_editar() {
    local transformar="$1" conferir="$2" novo antes depois
    DEBKIT_SMB_BACKUP=""; DEBKIT_SMB_TROCADO=0
    if [ ! -f "$DEBKIT_SMB_CONF" ]; then
        msg_erro "$(t amb.smbconf_ausente "$DEBKIT_SMB_CONF")"
        return 1
    fi
    DEBKIT_SMB_BACKUP=$(debkit_samba_backup) || return 1
    antes=$(debkit_temp) && depois=$(debkit_temp) || return 1
    if ! testparm -s "$DEBKIT_SMB_CONF" >"$antes" 2>/dev/null; then
        msg_erro "$(t amb.smbconf_invalido "$DEBKIT_SMB_CONF")"
        return 1
    fi
    if ! novo=$(umask 077; mktemp -- "$(dirname -- "$DEBKIT_SMB_CONF")/.debkit-smb.conf.XXXXXX"); then
        msg_erro "$(t smb.gravar_falhou "$DEBKIT_SMB_CONF")"
        return 1
    fi
    DEBKIT_TEMPORARIOS+=("$novo")
    if ! "$transformar" <"$DEBKIT_SMB_CONF" >"$novo"; then
        rm -f -- "$novo"
        msg_erro "$(t smb.gravar_falhou "$DEBKIT_SMB_CONF")"
        return 1
    fi
    if ! testparm -s "$novo" >"$depois" 2>/dev/null; then
        rm -f -- "$novo"
        msg_erro "$(t smb.testparm "$DEBKIT_SMB_CONF")"
        return 1
    fi
    if ! "$conferir" "$antes" "$depois"; then
        rm -f -- "$novo"
        msg_erro "$(t smb.conferencia "$DEBKIT_SMB_CONF")"
        return 1
    fi
    if ! chown --reference="$DEBKIT_SMB_CONF" -- "$novo" || ! chmod --reference="$DEBKIT_SMB_CONF" -- "$novo" \
       || ! mv -f -- "$novo" "$DEBKIT_SMB_CONF"; then
        rm -f -- "$novo"
        msg_erro "$(t smb.gravar_falhou "$DEBKIT_SMB_CONF")"
        return 1
    fi
    DEBKIT_SMB_TROCADO=1
    if ! debkit_samba_recarregar; then
        msg_erro "$(t prep.recarregar_falhou)"
        debkit_smbconf_restaurar
        return 1
    fi
}

# Volta o smb.conf do backup da última edição, se ele foi trocado (também
# com troca atômica, mantendo dono/permissões do arquivo atual) e recarrega.
# Retorna 0 se não havia o que restaurar ou se restaurou.
debkit_smbconf_restaurar() {
    local novo=""
    [ "${DEBKIT_SMB_TROCADO:-0}" -eq 1 ] || return 0
    if [ -f "$DEBKIT_SMB_BACKUP" ] \
       && novo=$(umask 077; mktemp -- "$(dirname -- "$DEBKIT_SMB_CONF")/.debkit-smb.conf.XXXXXX") \
       && cp -- "$DEBKIT_SMB_BACKUP" "$novo" \
       && chown --reference="$DEBKIT_SMB_CONF" -- "$novo" && chmod --reference="$DEBKIT_SMB_CONF" -- "$novo" \
       && mv -f -- "$novo" "$DEBKIT_SMB_CONF"; then
        DEBKIT_SMB_TROCADO=0
        debkit_samba_recarregar
        msg_info "$(t smb.restaurado "$DEBKIT_SMB_CONF" "$DEBKIT_SMB_BACKUP")"
        return 0
    fi
    [ -n "$novo" ] && rm -f -- "$novo"
    msg_erro "$(t smb.restaurar_falhou "$DEBKIT_SMB_CONF" "$DEBKIT_SMB_BACKUP")"
    return 1
}

# ── Menu ────────────────────────────────────────────────────────────────────
debkit_samba_menu() {
    local opcao
    while true; do
        titulo "$(t samba.titulo)"
        echo "  $(t geral.em_construcao)"
        echo ""
        echo "  0) $(t geral.voltar)"
        echo ""
        ler_opcao opcao
        case "$opcao" in
            "") continue ;;
            0)  return 0 ;;
            *)  msg_erro "$(t geral.opcao_invalida "$opcao")"; pausar ;;
        esac
    done
}
