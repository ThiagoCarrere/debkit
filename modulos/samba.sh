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
    [amb.pacotes_dominio]="Pacotes de domínio instalados sem necessidade num servidor independente: %s. O winbind faz o Linux aceitar a senha do Samba em logins como o SSH: a preparação vai removê-los"
    [prep.d_samba_pacotes_dominio]="Remover os pacotes de domínio desnecessários: %s (apt-get purge; depois confere que o PAM e o NSS não usam mais o winbind e que o Samba continua funcionando)"
    [prep.dominio_removeria_mais]="O apt removeria também outros pacotes (%s): nada foi removido."
    [prep.dominio_simulacao_falhou]="Não foi possível simular a remoção (apt-get -s). Nada foi removido."
    [prep.dominio_falhou]="A remoção falhou. Últimas linhas:"
    [prep.dominio_conferencia]="Depois da remoção: %s"
    [prep.dominio_mantidos]="Os pacotes removidos não foram reinstalados: %s"
    [samba.criar_usuario]="Criar usuário"
    [usr.titulo_criar]="Criar usuário"
    [usr.ambiente_nao_pronto]="O ambiente ainda não está preparado para criar usuários. Use \"9) Ambiente: verificar e preparar\" no menu principal."
    [usr.cancelado]="Cancelado. Nada foi feito."
    [usr.p_gecos]="Nome completo (opcional; Enter para pular): "
    [usr.p_login]="Nome de login: "
    [usr.p_login_sugestao]="Nome de login [%s]: "
    [usr.dica_login]="Login: letras minúsculas sem acento e números, começando por letra, com _ entre as partes (ex: maria_souza). Enter vazio cancela."
    [usr.nome_vazio]="Informe o nome de login."
    [usr.nome_tamanho]="O nome '%s' tem %d caractere(s): use de 2 a 32."
    [usr.nome_formato]="Nome inválido: '%s'. Use letras minúsculas sem acento e números, começando por letra, com _ entre as partes (ex: maria_souza)."
    [usr.nome_reservado]="'%s' é um nome reservado e não pode ser usado."
    [usr.nome_existe]="Já existe um usuário '%s' no servidor."
    [usr.nome_grupo_existe]="Já existe um grupo '%s' (o usuário novo ganha um grupo com o próprio nome)."
    [usr.nome_samba_existe]="Já existe uma conta Samba '%s' sem usuário no Linux."
    [usr.gecos_invalido]="Nome completo inválido: não use : , = \\ nem caracteres de controle."
    [usr.gecos_tamanho]="Nome completo muito longo (máximo %d caracteres)."
    [usr.titulo_tipo]="Tipo de conta:"
    [usr.tipo_arquivos]="Usuário de arquivos: só acessa as pastas pelo Samba (sem acesso ao servidor)"
    [usr.tipo_servidor]="Usuário com acesso ao servidor: Samba e também SSH/console"
    [usr.p_tipo]="Tipo [1]: "
    [usr.aviso_servidor]="ATENÇÃO: este usuário poderá ENTRAR NO SERVIDOR por SSH/console com a senha do Linux."
    [usr.confirma_servidor]="Confirma o acesso ao servidor para este usuário?"
    [usr.titulo_grupos]="Grupos disponíveis:"
    [usr.sem_grupos]="(nenhum grupo comum no servidor ainda)"
    [usr.p_grupos]="Grupos (números separados por vírgula ou espaço; Enter para nenhum): "
    [usr.grupos_invalido]="Escolha inválida: '%s'. Use os números da lista."
    [usr.p_senha_samba]="Senha do Samba (pastas): "
    [usr.p_senha_linux]="Senha do Linux (SSH/console): "
    [usr.p_senha_repetir]="Repita a senha: "
    [usr.senha_curta]="A senha precisa ter pelo menos %d caractere(s)."
    [usr.senha_longa]="A senha pode ter no máximo %d caracteres."
    [usr.senha_diferente]="As senhas não conferem. Tente de novo."
    [usr.senha_desistiu]="Muitas tentativas."
    [usr.p_mesma_senha]="Usar a mesma senha para entrar no servidor (Linux)?"
    [usr.titulo_resumo]="Resumo:"
    [usr.r_login]="Login: %s"
    [usr.r_gecos]="Nome completo: %s"
    [usr.r_tipo]="Tipo: %s"
    [usr.r_grupos]="Grupos: %s"
    [usr.r_nenhum]="(nenhum)"
    [usr.r_senha]="Senha: definida (não é mostrada)"
    [usr.r_senha_linux_mesma]="Senha do Linux: a mesma do Samba"
    [usr.r_senha_linux_outra]="Senha do Linux: própria (definida)"
    [usr.r_home]="Pasta pessoal: não (poderá ser criada depois)"
    [usr.p_confirmar]="Criar o usuário?"
    [usr.criando]="Criando o usuário %s..."
    [usr.criado]="Usuário %s criado."
    [usr.falhou]="Não foi possível criar o usuário %s: %s"
    [usr.desfeito]="O que já tinha sido feito foi desfeito: nada ficou pela metade."
    [usr.desfazer_falhou]="ATENÇÃO: não foi possível desfazer tudo: confira o usuário %s à mão."
    [usr.f_useradd]="o useradd falhou"
    [usr.f_uid]="o UID %s criado está fora da faixa de contas comuns"
    [usr.f_senha_linux]="não foi possível definir a senha do Linux"
    [usr.f_bloqueio]="a senha do Linux não ficou bloqueada"
    [usr.f_samba]="não foi possível criar a conta no Samba"
    [usr.f_conferencia]="a conferência final não bateu (%s)"
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
    [amb.pacotes_dominio]="Domain packages installed without need on a standalone server: %s. winbind makes Linux accept the Samba password in logins such as SSH: the setup will remove them"
    [prep.d_samba_pacotes_dominio]="Remove the unneeded domain packages: %s (apt-get purge; then checks that PAM and NSS no longer use winbind and that Samba still works)"
    [prep.dominio_removeria_mais]="apt would also remove other packages (%s): nothing was removed."
    [prep.dominio_simulacao_falhou]="Could not simulate the removal (apt-get -s). Nothing was removed."
    [prep.dominio_falhou]="The removal failed. Last lines:"
    [prep.dominio_conferencia]="After the removal: %s"
    [prep.dominio_mantidos]="The removed packages were not reinstalled: %s"
    [samba.criar_usuario]="Create user"
    [usr.titulo_criar]="Create user"
    [usr.ambiente_nao_pronto]="The environment is not set up for creating users yet. Use \"9) Environment: check and set up\" in the main menu."
    [usr.cancelado]="Cancelled. Nothing was done."
    [usr.p_gecos]="Full name (optional; Enter to skip): "
    [usr.p_login]="Login name: "
    [usr.p_login_sugestao]="Login name [%s]: "
    [usr.dica_login]="Login: lowercase letters without accents and digits, starting with a letter, with _ between parts (e.g. maria_souza). Empty Enter cancels."
    [usr.nome_vazio]="Enter the login name."
    [usr.nome_tamanho]="The name '%s' has %d character(s): use 2 to 32."
    [usr.nome_formato]="Invalid name: '%s'. Use lowercase letters without accents and digits, starting with a letter, with _ between parts (e.g. maria_souza)."
    [usr.nome_reservado]="'%s' is a reserved name and cannot be used."
    [usr.nome_existe]="A user '%s' already exists on the server."
    [usr.nome_grupo_existe]="A group '%s' already exists (the new user gets a group with its own name)."
    [usr.nome_samba_existe]="A Samba account '%s' already exists without a Linux user."
    [usr.gecos_invalido]="Invalid full name: do not use : , = \\ or control characters."
    [usr.gecos_tamanho]="Full name too long (at most %d characters)."
    [usr.titulo_tipo]="Account type:"
    [usr.tipo_arquivos]="File user: only accesses folders through Samba (no server access)"
    [usr.tipo_servidor]="User with server access: Samba and also SSH/console"
    [usr.p_tipo]="Type [1]: "
    [usr.aviso_servidor]="WARNING: this user will be able to LOG IN TO THE SERVER via SSH/console with the Linux password."
    [usr.confirma_servidor]="Confirm server access for this user?"
    [usr.titulo_grupos]="Available groups:"
    [usr.sem_grupos]="(no regular groups on the server yet)"
    [usr.p_grupos]="Groups (numbers separated by commas or spaces; Enter for none): "
    [usr.grupos_invalido]="Invalid choice: '%s'. Use the numbers from the list."
    [usr.p_senha_samba]="Samba password (folders): "
    [usr.p_senha_linux]="Linux password (SSH/console): "
    [usr.p_senha_repetir]="Repeat the password: "
    [usr.senha_curta]="The password must have at least %d character(s)."
    [usr.senha_longa]="The password can have at most %d characters."
    [usr.senha_diferente]="The passwords do not match. Try again."
    [usr.senha_desistiu]="Too many attempts."
    [usr.p_mesma_senha]="Use the same password to log in to the server (Linux)?"
    [usr.titulo_resumo]="Summary:"
    [usr.r_login]="Login: %s"
    [usr.r_gecos]="Full name: %s"
    [usr.r_tipo]="Type: %s"
    [usr.r_grupos]="Groups: %s"
    [usr.r_nenhum]="(none)"
    [usr.r_senha]="Password: set (not shown)"
    [usr.r_senha_linux_mesma]="Linux password: same as Samba"
    [usr.r_senha_linux_outra]="Linux password: its own (set)"
    [usr.r_home]="Home folder: no (can be created later)"
    [usr.p_confirmar]="Create the user?"
    [usr.criando]="Creating user %s..."
    [usr.criado]="User %s created."
    [usr.falhou]="Could not create user %s: %s"
    [usr.desfeito]="What had been done was undone: nothing was left half-done."
    [usr.desfazer_falhou]="WARNING: could not undo everything: check user %s by hand."
    [usr.f_useradd]="useradd failed"
    [usr.f_uid]="the created UID %s is outside the regular account range"
    [usr.f_senha_linux]="could not set the Linux password"
    [usr.f_bloqueio]="the Linux password was not locked"
    [usr.f_samba]="could not create the Samba account"
    [usr.f_conferencia]="the final check did not match (%s)"
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

# ── Pacotes de domínio (não usados num servidor independente) ──────────────
# Versões anteriores da preparação instalavam o samba com os "recomendados"
# do apt: vinham o samba-ad-dc (controlador de domínio) e o winbind, que se
# coloca no PAM (pam_winbind: aceita a senha do Samba na autenticação de
# logins como o SSH) e no NSS. Nada disso serve a um servidor independente.
DEBKIT_SAMBA_PACOTES_DOMINIO=(samba-ad-dc winbind libpam-winbind libnss-winbind)
DEBKIT_DIR_PAM="${DEBKIT_DIR_PAM:-/etc/pam.d}"
DEBKIT_ARQ_NSSWITCH="${DEBKIT_ARQ_NSSWITCH:-/etc/nsswitch.conf}"

# Imprime os pacotes de domínio instalados (separados por espaço)
debkit_samba_pacotes_dominio() {
    local p l=""
    debkit_tem_comando dpkg-query || return 0
    for p in "${DEBKIT_SAMBA_PACOTES_DOMINIO[@]}"; do
        debkit_pacote_instalado "$p" && l+="${l:+ }$p"
    done
    printf '%s' "$l"
}

# Imprime onde o winbind ainda aparece no PAM (common-*) e no NSS (passwd/
# group); nada se não aparece
debkit_samba_winbind_no_sistema() {
    local onde=""
    if grep -lsE '^[^#]*pam_winbind' "$DEBKIT_DIR_PAM"/common-* >/dev/null 2>&1; then onde+="PAM "; fi
    if grep -sqE '^[[:space:]]*(passwd|group):.*[[:space:]]winbind\b' "$DEBKIT_ARQ_NSSWITCH"; then onde+="NSS "; fi
    printf '%s' "${onde% }"
}

debkit_descrever_samba_pacotes_dominio() { t prep.d_samba_pacotes_dominio "$DEBKIT_SAMBA_DOMINIO"; }

# Simula a remoção e recusa se o apt quiser levar junto qualquer outro
# pacote; remove com purge (os scripts dos pacotes tiram o winbind do PAM e
# do NSS) e confere o resultado real. Pacote removido não é reinstalado se
# um passo seguinte falhar (só é informado).
debkit_acao_samba_pacotes_dominio() {
    local registro simulacao p fora="" problema=""
    local -a pacotes=()
    read -ra pacotes <<< "$DEBKIT_SAMBA_DOMINIO"
    DEBKIT_SAMBA_DOMINIO_REMOVIDOS=""
    [ ${#pacotes[@]} -gt 0 ] || return 0
    if ! simulacao=$(LC_ALL=C DEBIAN_FRONTEND=noninteractive "$DEBKIT_APT" -s purge "${pacotes[@]}" 2>&1); then
        msg_erro "$(t prep.dominio_simulacao_falhou)"
        return 1
    fi
    while read -r p; do
        [[ " ${pacotes[*]} " == *" $p "* ]] || fora+="${fora:+ }$p"
    done < <(awk '$1 == "Remv" || $1 == "Purg" {print $2}' <<< "$simulacao")
    if [ -n "$fora" ]; then
        msg_erro "$(t prep.dominio_removeria_mais "$fora")"
        return 1
    fi
    registro=$(debkit_temp) || return 1
    if ! DEBIAN_FRONTEND=noninteractive "$DEBKIT_APT" -o DPkg::Lock::Timeout=120 purge -y "${pacotes[@]}" >"$registro" 2>&1; then
        msg_erro "$(t prep.dominio_falhou)"
        tail -n 8 "$registro" | sed 's/^/     /' >&2
        DEBKIT_SAMBA_DOMINIO_REMOVIDOS="$(debkit_samba_removidos "${pacotes[@]}")"
        return 1
    fi
    DEBKIT_SAMBA_DOMINIO_REMOVIDOS="$(debkit_samba_removidos "${pacotes[@]}")"
    # Conferência: nada instalado, winbind fora do PAM/NSS, Samba de pé
    [ -z "$(debkit_samba_pacotes_dominio)" ] || problema="ainda instalados: $(debkit_samba_pacotes_dominio)"
    [ -z "$(debkit_samba_winbind_no_sistema)" ] || problema="winbind ainda no $(debkit_samba_winbind_no_sistema)"
    testparm -s "$DEBKIT_SMB_CONF" >/dev/null 2>&1 || problema="smb.conf inválido"
    if [ -n "$DEBKIT_SVC_SAMBA" ] && ! debkit_servico_ativo "$DEBKIT_SVC_SAMBA"; then problema="serviço $DEBKIT_SVC_SAMBA parado"; fi
    if [ -n "$problema" ]; then
        msg_erro "$(t prep.dominio_conferencia "$problema")"
        return 1
    fi
}

# Dos pacotes indicados, imprime os que não estão mais instalados
debkit_samba_removidos() {
    local p l=""
    for p in "$@"; do debkit_pacote_instalado "$p" || l+="${l:+ }$p"; done
    printf '%s' "$l"
}

debkit_desfazer_samba_pacotes_dominio() {
    [ -n "${DEBKIT_SAMBA_DOMINIO_REMOVIDOS:-}" ] && msg_aviso "$(t prep.dominio_mantidos "$DEBKIT_SAMBA_DOMINIO_REMOVIDOS")"
    return 0
}

# ── Verificação (gancho) ────────────────────────────────────────────────────
# Deixa prontos para a preparação:
#   DEBKIT_SVC_SAMBA             nome do serviço (vazio se não encontrado)
#   DEBKIT_SAMBA_INCLUDE_ANTIGO  arquivo do "include" antigo do debkit (ou vazio)
#   DEBKIT_SAMBA_INCLUDE_VAZIO   1 se esse arquivo não tem compartilhamentos
debkit_samba_verificar() {
    local papel backend
    DEBKIT_SVC_SAMBA=""; DEBKIT_SAMBA_INCLUDE_ANTIGO=""; DEBKIT_SAMBA_INCLUDE_VAZIO=0; DEBKIT_SAMBA_DOMINIO=""
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
            "standalone server")
                debkit_verif_add samba ok "$(t amb.papel_ok)"
                DEBKIT_SAMBA_DOMINIO=$(debkit_samba_pacotes_dominio)
                [ -n "$DEBKIT_SAMBA_DOMINIO" ] && debkit_verif_add samba aviso "$(t amb.pacotes_dominio "$DEBKIT_SAMBA_DOMINIO")" ;;
            *"domain controller"*) debkit_verif_manual samba "$(t amb.papel_dc "$papel")" ;;
            *) debkit_verif_add samba aviso "$(t amb.papel_outro "$papel")" ;;
        esac
        backend=$(debkit_samba_param "passdb backend")
        # "tdbsam" ou "tdbsam:<arquivo>" (base num caminho próprio)
        if [ "$backend" == "tdbsam" ] || [[ "$backend" == tdbsam:/* ]]; then
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
    if [ -n "${DEBKIT_SAMBA_DOMINIO:-}" ] && debkit_familia_debian && debkit_tem_comando "$DEBKIT_APT"; then
        DEBKIT_PLANO+=(samba_pacotes_dominio)
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

# ── Usuários: regras ────────────────────────────────────────────────────────
# Nome de login (decisão de 16/10/2026): letras minúsculas sem acento e
# números, começando por letra; nomes compostos com "_" entre as partes
# (nome_sobrenome), sem "_" no começo/fim nem repetido; 2 a 32 caracteres.
# Fica de fora o que já existe (usuário, grupo - o usuário novo ganha um
# grupo pessoal com o mesmo nome -, conta Samba) e os nomes reservados.
DEBKIT_USR_RESERVADOS=(root admin administrator administrador guest convidado nobody)
DEBKIT_USR_GECOS_MAX=100
DEBKIT_USR_SENHA_MAX=128
DEBKIT_USR_HOME="/nonexistent"     # sem pasta pessoal (a 1.1b cria a home)

# Comandos do Samba sempre com a configuração do debkit (SMB_CONF)
debkit_smbpasswd() { smbpasswd -c "$DEBKIT_SMB_CONF" "$@"; }
debkit_pdbedit()   { pdbedit -s "$DEBKIT_SMB_CONF" "$@"; }

# A conta existe no Samba?
debkit_samba_conta_existe() { debkit_pdbedit -u "$1" >/dev/null 2>&1; }

# Imprime o problema do nome de login (mensagem) e retorna 1; 0 = nome livre e válido
debkit_usuario_nome_problema() {
    local nome="$1" r
    if [ -z "$nome" ]; then t usr.nome_vazio; return 1; fi
    if [ "${#nome}" -lt 2 ] || [ "${#nome}" -gt 32 ]; then t usr.nome_tamanho "$nome" "${#nome}"; return 1; fi
    local l="$DEBKIT_MINUSCULAS" ld="$DEBKIT_MINUSCULAS$DEBKIT_DIGITOS"   # sem intervalos: ver núcleo
    if [[ ! "$nome" =~ ^[$l][$ld]*(_[$ld]+)*$ ]]; then t usr.nome_formato "$nome"; return 1; fi
    for r in "${DEBKIT_USR_RESERVADOS[@]}"; do
        if [ "$nome" == "$r" ]; then t usr.nome_reservado "$nome"; return 1; fi
    done
    if getent passwd "$nome" >/dev/null 2>&1; then t usr.nome_existe "$nome"; return 1; fi
    if getent group "$nome" >/dev/null 2>&1; then t usr.nome_grupo_existe "$nome"; return 1; fi
    if debkit_samba_conta_existe "$nome"; then t usr.nome_samba_existe "$nome"; return 1; fi
    return 0
}

# Nome completo (campo GECOS do Linux): opcional; sem ":" "," "=" "\" (separam
# campos no /etc/passwd e no chfn) nem caracteres de controle
debkit_usuario_gecos_problema() {
    local gecos="$1"
    if [[ "$gecos" == *[:,=\\]* || "$gecos" =~ [[:cntrl:]] ]]; then t usr.gecos_invalido; return 1; fi
    if [ "${#gecos}" -gt "$DEBKIT_USR_GECOS_MAX" ]; then t usr.gecos_tamanho "$DEBKIT_USR_GECOS_MAX"; return 1; fi
    return 0
}

# Sugere um login a partir do nome completo: parte antes de " - ", sem
# acentos, minúsculas, primeiro e último nome com "_" (ex: "Maria Conceição
# Ávila - Financeiro" -> maria_avila). Não imprime nada se não der um nome
# válido e livre.
debkit_usuario_sugerir() {
    local base sugestao
    local -a partes
    base="${1%% - *}"
    base=$(printf '%s' "$base" | LC_ALL=C.UTF-8 iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null) || return 0
    base="${base,,}"
    base="${base//\'/}"                                  # O'Connor -> oconnor
    base="${base//[^$DEBKIT_MINUSCULAS$DEBKIT_DIGITOS]/ }"
    read -ra partes <<< "$base"
    [ ${#partes[@]} -gt 0 ] || return 0
    sugestao="${partes[0]}"
    [ ${#partes[@]} -gt 1 ] && sugestao+="_${partes[-1]}"
    debkit_usuario_nome_problema "$sugestao" >/dev/null && printf '%s' "$sugestao"
    return 0
}

# Grupos comuns que podem receber usuários (um por linha, em ordem): GID na
# faixa do login.defs, sem os grupos pessoais (mesmo nome de um usuário
# que o tem como grupo principal) e sem o grupo de proteção do debkit
debkit_samba_grupos_comuns() {
    local nome gid
    local -A pessoal=()
    while IFS=: read -r nome _ _ gid _; do
        pessoal["$nome:$gid"]=1
    done < <(getent passwd)
    while IFS=: read -r nome _ gid _; do
        debkit_gid_comum "$gid" || continue
        [ -n "${pessoal["$nome:$gid"]+x}" ] && continue
        [ "$nome" == "$DEBKIT_GRUPO_USUARIOS" ] && continue
        echo "$nome"
    done < <(getent group) | sort -u
}

# Shell sem login (Debian: /usr/sbin/nologin)
debkit_shell_nologin() {
    local s
    for s in /usr/sbin/nologin /sbin/nologin; do
        [ -x "$s" ] && { echo "$s"; return 0; }
    done
    echo /usr/sbin/nologin
}

# O ambiente está pronto para criar usuários? (nada a preparar: grupo de
# proteção, proteção SSH, Samba...)
debkit_samba_ambiente_pronto() {
    debkit_verificar_ambiente >/dev/null 2>&1
    debkit_montar_plano
    [ -z "$DEBKIT_PLANO_IMPOSSIVEL" ] && [ ${#DEBKIT_PLANO[@]} -eq 0 ]
}

# ── Usuários: criar ─────────────────────────────────────────────────────────
# Entrada (variáveis, para a senha nunca ir para a linha de comando):
#   DEBKIT_U_NOME, DEBKIT_U_GECOS, DEBKIT_U_TIPO (arquivos | servidor),
#   DEBKIT_U_GRUPOS (array), DEBKIT_U_SENHA (Samba),
#   DEBKIT_U_SENHA_LINUX (só tipo servidor)
# Tudo ou nada: cria o usuário Linux (grupo pessoal, sem home; tipo
# arquivos: shell nologin, senha Linux bloqueada e grupo de proteção SSH;
# tipo servidor: /bin/bash e senha Linux própria), a conta Samba, confere
# tudo e, se algo falhar, desfaz o que fez. Senhas só pela entrada padrão.
debkit_usuario_criar() {
    local nome="$DEBKIT_U_NOME" shell grupos estado uid gid g motivo=""
    local -a membros=()
    DEBKIT_U_FEITO_LINUX=0; DEBKIT_U_FEITO_SAMBA=0
    if ! debkit_usuario_nome_problema "$nome" >/dev/null || ! debkit_usuario_gecos_problema "$DEBKIT_U_GECOS" >/dev/null; then
        motivo=$(debkit_usuario_nome_problema "$nome"; debkit_usuario_gecos_problema "$DEBKIT_U_GECOS")
        msg_erro "$(t usr.falhou "$nome" "$motivo")"
        return 1
    fi
    membros=("${DEBKIT_U_GRUPOS[@]}")
    case "$DEBKIT_U_TIPO" in
        arquivos) shell=$(debkit_shell_nologin); membros+=("$DEBKIT_GRUPO_USUARIOS") ;;
        servidor) shell="/bin/bash" ;;
        *)        return 1 ;;
    esac
    grupos=$(IFS=,; echo "${membros[*]}")

    msg_info "$(t usr.criando "$nome")"
    # 1. Usuário Linux (useradd já deixa a senha bloqueada: "!")
    if ! useradd -M -d "$DEBKIT_USR_HOME" -s "$shell" -U -c "$DEBKIT_U_GECOS" ${grupos:+-G "$grupos"} -- "$nome" >/dev/null 2>&1; then
        debkit_usuario_falhou "$(t usr.f_useradd)"
        return 1
    fi
    DEBKIT_U_FEITO_LINUX=1
    IFS=: read -r _ _ uid gid _ < <(getent passwd "$nome")
    if ! debkit_uid_comum "$uid"; then
        debkit_usuario_falhou "$(t usr.f_uid "$uid")"
        return 1
    fi
    # 2. Senha do Linux
    if [ "$DEBKIT_U_TIPO" == "servidor" ]; then
        if ! printf '%s:%s\n' "$nome" "$DEBKIT_U_SENHA_LINUX" | chpasswd >/dev/null 2>&1 \
           || [ "$(passwd -S -- "$nome" 2>/dev/null | awk '{print $2}')" != "P" ]; then
            debkit_usuario_falhou "$(t usr.f_senha_linux)"
            return 1
        fi
    elif [ "$(passwd -S -- "$nome" 2>/dev/null | awk '{print $2}')" != "L" ]; then
        debkit_usuario_falhou "$(t usr.f_bloqueio)"
        return 1
    fi
    # 3. Conta Samba (o smbpasswd lê a senha duas vezes da entrada padrão)
    if ! printf '%s\n%s\n' "$DEBKIT_U_SENHA" "$DEBKIT_U_SENHA" | debkit_smbpasswd -s -a -- "$nome" >/dev/null 2>&1; then
        debkit_usuario_falhou "$(t usr.f_samba)"
        return 1
    fi
    DEBKIT_U_FEITO_SAMBA=1
    # 4. Conferência final (resultado real, não só o código de saída)
    estado=$(getent passwd "$nome" | cut -d: -f6,7)
    [ "$estado" == "$DEBKIT_USR_HOME:$shell" ] || motivo="home/shell"
    [ "$(getent group "$nome" | cut -d: -f3)" == "$gid" ] || motivo="grupo pessoal"
    for g in "${membros[@]}"; do
        id -nG -- "$nome" 2>/dev/null | tr ' ' '\n' | grep -qxF "$g" || motivo="grupo $g"
    done
    if [ "$DEBKIT_U_TIPO" == "servidor" ] && id -nG -- "$nome" | tr ' ' '\n' | grep -qxF "$DEBKIT_GRUPO_USUARIOS"; then
        motivo="grupo $DEBKIT_GRUPO_USUARIOS"
    fi
    # O Samba não pode ter mexido na senha do Linux (ex: "unix password sync")
    if [ "$DEBKIT_U_TIPO" == "arquivos" ] && [ "$(passwd -S -- "$nome" 2>/dev/null | awk '{print $2}')" != "L" ]; then
        motivo="senha do Linux não bloqueada"
    fi
    debkit_samba_conta_existe "$nome" || motivo="Samba"
    if [ -d "$DEBKIT_USR_HOME" ]; then motivo="$DEBKIT_USR_HOME existe"; fi
    if [ -n "$motivo" ]; then
        debkit_usuario_falhou "$(t usr.f_conferencia "$motivo")"
        return 1
    fi
    debkit_auditar usuario_criar "nome=$nome tipo=$DEBKIT_U_TIPO uid=$uid grupos=$(IFS=,; echo "${DEBKIT_U_GRUPOS[*]}") resultado=ok"
    msg_ok "$(t usr.criado "$nome")"
}

# Falha no meio da criação: informa, desfaz o que foi feito e audita
debkit_usuario_falhou() {
    local nome="$DEBKIT_U_NOME"
    msg_erro "$(t usr.falhou "$nome" "$1")"
    debkit_auditar usuario_criar "nome=$nome tipo=$DEBKIT_U_TIPO resultado=falha motivo=$1"
    local havia=$((DEBKIT_U_FEITO_LINUX + DEBKIT_U_FEITO_SAMBA))
    if debkit_usuario_desfazer; then
        [ "$havia" -eq 0 ] || msg_info "$(t usr.desfeito)"
        debkit_auditar usuario_criar "nome=$nome resultado=desfeito"
    else
        msg_erro "$(t usr.desfazer_falhou "$nome")"
    fi
}

# Desfaz só o que a criação fez (conta Samba, usuário Linux e o grupo
# pessoal criado junto). NUNCA usa "userdel -r". Retorna 0 se nada sobrou.
debkit_usuario_desfazer() {
    local nome="$DEBKIT_U_NOME"
    if [ "$DEBKIT_U_FEITO_SAMBA" -eq 1 ] || { [ "$DEBKIT_U_FEITO_LINUX" -eq 1 ] && debkit_samba_conta_existe "$nome"; }; then
        debkit_smbpasswd -x -- "$nome" >/dev/null 2>&1
    fi
    if [ "$DEBKIT_U_FEITO_LINUX" -eq 1 ]; then
        userdel -- "$nome" >/dev/null 2>&1
        # O userdel tira o grupo pessoal (USERGROUPS_ENAB); se sobrou e está vazio, tira
        if getent group "$nome" | awk -F: '$4 == "" {ok = 1} END {exit !ok}'; then
            groupdel -- "$nome" >/dev/null 2>&1
        fi
        if getent passwd "$nome" >/dev/null || getent group "$nome" >/dev/null; then return 1; fi
    fi
    if [ $((DEBKIT_U_FEITO_LINUX + DEBKIT_U_FEITO_SAMBA)) -gt 0 ] && debkit_samba_conta_existe "$nome"; then return 1; fi
    DEBKIT_U_FEITO_LINUX=0; DEBKIT_U_FEITO_SAMBA=0
    return 0
}

# ── Usuários: tela ──────────────────────────────────────────────────────────
# Lê uma linha para a variável indicada; fim da entrada = cancelar (retorna 1)
debkit_ler() {
    local -n _dest="$1"
    read -rp "$2" _dest || { echo ""; return 1; }
}

# Lê uma senha sem eco, duas vezes, com SENHA_MIN e o máximo. Até 3
# tentativas. Retorna 1 se desistir ou fim da entrada.
debkit_ler_senha() {
    local -n _senha="$1"
    local prompt="$2" s1 s2 _tentativa
    for _tentativa in 1 2 3; do
        read -rsp "$prompt" s1 || { echo ""; return 1; }
        echo ""
        if [ "${#s1}" -lt "$DEBKIT_SENHA_MIN" ]; then
            msg_erro "$(t usr.senha_curta "$DEBKIT_SENHA_MIN")"; continue
        fi
        if [ "${#s1}" -gt "$DEBKIT_USR_SENHA_MAX" ]; then
            msg_erro "$(t usr.senha_longa "$DEBKIT_USR_SENHA_MAX")"; continue
        fi
        read -rsp "$(t usr.p_senha_repetir)" s2 || { echo ""; return 1; }
        echo ""
        if [ "$s1" != "$s2" ]; then
            msg_erro "$(t usr.senha_diferente)"; continue
        fi
        _senha="$s1"
        return 0
    done
    msg_erro "$(t usr.senha_desistiu)"
    return 1
}

# Pergunta tudo, mostra o resumo, pede UMA confirmação e cria
debkit_samba_tela_criar_usuario() {
    local gecos nome sugestao problema tipo resp escolha n i mesma=1
    local -a lista=() escolhidos=()
    titulo "$(t usr.titulo_criar)"
    if ! debkit_samba_ambiente_pronto; then
        msg_erro "$(t usr.ambiente_nao_pronto)"
        pausar; return 1
    fi
    # Nome completo e login
    while true; do
        debkit_ler gecos "$(t usr.p_gecos)" || { msg_aviso "$(t usr.cancelado)"; return 1; }
        problema=$(debkit_usuario_gecos_problema "$gecos") && break
        msg_erro "$problema"
    done
    sugestao=$(debkit_usuario_sugerir "$gecos")
    msg_info "$(t usr.dica_login)"
    while true; do
        if [ -n "$sugestao" ]; then
            debkit_ler nome "$(t usr.p_login_sugestao "$sugestao")" || { msg_aviso "$(t usr.cancelado)"; return 1; }
            [ -z "$nome" ] && nome="$sugestao"
        else
            debkit_ler nome "$(t usr.p_login)" || { msg_aviso "$(t usr.cancelado)"; return 1; }
            [ -z "$nome" ] && { msg_aviso "$(t usr.cancelado)"; return 1; }
        fi
        problema=$(debkit_usuario_nome_problema "$nome") && break
        msg_erro "$problema"
    done
    # Tipo de conta
    echo ""
    echo "  $(t usr.titulo_tipo)"
    echo "    1) $(t usr.tipo_arquivos)"
    echo "    2) $(t usr.tipo_servidor)"
    while true; do
        debkit_ler resp "$(t usr.p_tipo)" || { msg_aviso "$(t usr.cancelado)"; return 1; }
        case "$resp" in
            ""|1) tipo=arquivos; break ;;
            2)    msg_aviso "$(t usr.aviso_servidor)"
                  if confirmar "$(t usr.confirma_servidor)"; then tipo=servidor; break; fi ;;
            *)    msg_erro "$(t geral.opcao_invalida "$resp")" ;;
        esac
    done
    # Grupos
    mapfile -t lista < <(debkit_samba_grupos_comuns)
    echo ""
    echo "  $(t usr.titulo_grupos)"
    if [ ${#lista[@]} -eq 0 ]; then
        echo "    $(t usr.sem_grupos)"
    else
        for i in "${!lista[@]}"; do echo "    $((i + 1))) ${lista[$i]}"; done
        while true; do
            debkit_ler escolha "$(t usr.p_grupos)" || { msg_aviso "$(t usr.cancelado)"; return 1; }
            escolhidos=(); problema=""
            for n in ${escolha//,/ }; do
                if [[ "$n" =~ ^[0-9]+$ ]] && [ "$((10#$n))" -ge 1 ] && [ "$((10#$n))" -le ${#lista[@]} ]; then
                    [[ " ${escolhidos[*]} " == *" ${lista[$((10#$n - 1))]} "* ]] || escolhidos+=("${lista[$((10#$n - 1))]}")
                else
                    problema="$n"; break
                fi
            done
            [ -z "$problema" ] && break
            msg_erro "$(t usr.grupos_invalido "$problema")"
        done
    fi
    # Senhas
    echo ""
    DEBKIT_U_SENHA=""; DEBKIT_U_SENHA_LINUX=""
    debkit_ler_senha DEBKIT_U_SENHA "$(t usr.p_senha_samba)" || { msg_aviso "$(t usr.cancelado)"; return 1; }
    if [ "$tipo" == "servidor" ]; then
        if confirmar "$(t usr.p_mesma_senha)"; then
            DEBKIT_U_SENHA_LINUX="$DEBKIT_U_SENHA"
        else
            mesma=0
            debkit_ler_senha DEBKIT_U_SENHA_LINUX "$(t usr.p_senha_linux)" || { DEBKIT_U_SENHA=""; msg_aviso "$(t usr.cancelado)"; return 1; }
        fi
    fi
    # Resumo e UMA confirmação
    echo ""
    echo "  $(t usr.titulo_resumo)"
    echo "    $(t usr.r_login "$nome")"
    [ -n "$gecos" ] && echo "    $(t usr.r_gecos "$gecos")"
    if [ "$tipo" == "servidor" ]; then echo "    $(t usr.r_tipo "$(t usr.tipo_servidor)")"; else echo "    $(t usr.r_tipo "$(t usr.tipo_arquivos)")"; fi
    if [ ${#escolhidos[@]} -gt 0 ]; then
        local juntos; juntos=$(printf '%s, ' "${escolhidos[@]}")
        echo "    $(t usr.r_grupos "${juntos%, }")"
    else
        echo "    $(t usr.r_grupos "$(t usr.r_nenhum)")"
    fi
    echo "    $(t usr.r_senha)"
    if [ "$tipo" == "servidor" ]; then
        if [ "$mesma" -eq 1 ]; then echo "    $(t usr.r_senha_linux_mesma)"; else echo "    $(t usr.r_senha_linux_outra)"; fi
    fi
    echo "    $(t usr.r_home)"
    echo ""
    if ! confirmar "$(t usr.p_confirmar)"; then
        DEBKIT_U_SENHA=""; DEBKIT_U_SENHA_LINUX=""
        msg_aviso "$(t usr.cancelado)"
        pausar; return 1
    fi
    DEBKIT_U_NOME="$nome"; DEBKIT_U_GECOS="$gecos"; DEBKIT_U_TIPO="$tipo"; DEBKIT_U_GRUPOS=("${escolhidos[@]}")
    debkit_usuario_criar; local rc=$?
    DEBKIT_U_SENHA=""; DEBKIT_U_SENHA_LINUX=""
    pausar
    return "$rc"
}

# ── Menu ────────────────────────────────────────────────────────────────────
debkit_samba_menu() {
    local opcao
    while true; do
        titulo "$(t samba.titulo)"
        echo "  1) $(t samba.criar_usuario)"
        echo ""
        echo "  0) $(t geral.voltar)"
        echo ""
        ler_opcao opcao
        case "$opcao" in
            "") continue ;;
            1)  debkit_samba_tela_criar_usuario ;;
            0)  return 0 ;;
            *)  msg_erro "$(t geral.opcao_invalida "$opcao")"; pausar ;;
        esac
    done
}
