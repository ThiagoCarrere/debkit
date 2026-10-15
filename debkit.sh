#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  debkit - Gerenciador Samba                                              ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# Gerenciador de servidor de arquivos Samba, com foco em segurança.
# Gerencia os usuários, grupos e compartilhamentos comuns do servidor
# (nunca os de sistema). Ver docs/PLANEJAMENTO.md.
#
# Copyright (c) 2026 Thiago Carrere - Licença MIT (ver LICENSE)
# Desenvolvido por Thiago Carrere em parceria com Claude (Anthropic).
#
# Uso:
#   debkit                abre o menu (precisa ser root)
#   debkit --ajuda        mostra a ajuda
#   debkit --versao       mostra a versão
#   debkit --verificar    verifica o ambiente (somente leitura; precisa ser root)
#   debkit --preparar     verifica e prepara o ambiente (pede confirmação)
#   source debkit.sh      carrega as funções sem executar nada (para testes)
#
# Códigos de saída:
#   0 sucesso | 1 erro (no --verificar: falta algo essencial)
#   2 uso incorreto | 130 interrompido (Ctrl+C)
#
# Seções do arquivo:
#   1. Versão e verificação do bash
#   2. Configuração
#   3. Mensagens (catálogo pt_BR / en)
#   4. Cores e saída
#   5. Utilitários
#   6. Ambiente (detecção)
#   7. Preparação do ambiente
#   8. Funções
#   9. Menus
#  10. Linha de comando e início

# ════════════════════════════════════════════════════════════════════════════
# 1. VERSÃO E VERIFICAÇÃO DO BASH
# ════════════════════════════════════════════════════════════════════════════
# Esta verificação usa só sintaxe POSIX, para funcionar mesmo se o arquivo
# for executado por outro shell (ex: "sh debkit.sh").
if [ -z "${BASH_VERSINFO:-}" ]; then
    echo "debkit: este programa precisa do bash (execute: bash debkit.sh)" >&2
    exit 1
fi
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 4 ]; }; then
    echo "debkit: é necessário bash 4.4 ou mais novo (atual: ${BASH_VERSION})" >&2
    exit 1
fi

DEBKIT_VERSAO="0.1.0-dev"

# ════════════════════════════════════════════════════════════════════════════
# 2. CONFIGURAÇÃO
# ════════════════════════════════════════════════════════════════════════════
# Padrões; podem ser alterados em /etc/debkit/debkit.conf (ver debkit.conf.exemplo).
# O arquivo NÃO é executado: é lido linha a linha (CHAVE=valor), só chaves
# conhecidas são aceitas e cada valor é validado.

DEBKIT_CONF_ARQUIVO="${DEBKIT_CONF_ARQUIVO:-/etc/debkit/debkit.conf}"

# Chave -> valor padrão
declare -A DEBKIT_CONF_PADRAO=(
    [IDIOMA]="pt_BR"
    [SENHA_MIN]="4"
    [GRUPO_USUARIOS]="debkit_usuarios"
    [PREFIXO_GRUPO]="debkit_"
    [SMB_CONF]="/etc/samba/smb.conf"
    [SHARES_CONF]="/etc/samba/debkit-shares.conf"
    [SSH_DROPIN]="/etc/ssh/sshd_config.d/debkit.conf"
    [LOG]="/var/log/debkit.log"
    [BACKUP_DIR]="/var/backups/debkit"
    [BACKUP_MANTER]="30"
    [TRAVA]="/run/debkit.lock"
)

# Chave -> tipo de validação
declare -A DEBKIT_CONF_TIPO=(
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
debkit_conf_valor_valido() {
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

# Aplica os padrões nas variáveis DEBKIT_<CHAVE>
debkit_conf_padroes() {
    local chave
    for chave in "${!DEBKIT_CONF_PADRAO[@]}"; do
        printf -v "DEBKIT_${chave}" '%s' "${DEBKIT_CONF_PADRAO[$chave]}"
    done
}

# Lê o arquivo de configuração (se existir) por cima dos padrões.
# Erros vão para DEBKIT_CONF_ERROS (um por linha); retorna 1 se houver erro.
# Chaves desconhecidas vão para DEBKIT_CONF_AVISOS (não impedem o uso).
debkit_conf_carregar() {
    local arquivo="${1:-$DEBKIT_CONF_ARQUIVO}" linha n=0 chave valor dono perm
    DEBKIT_CONF_ERROS=""
    DEBKIT_CONF_AVISOS=""
    debkit_conf_padroes
    [ -e "$arquivo" ] || return 0

    if [ ! -f "$arquivo" ] || [ ! -r "$arquivo" ]; then
        DEBKIT_CONF_ERROS="$arquivo: não é um arquivo legível"
        return 1
    fi
    # Segurança: só root pode poder alterar o arquivo
    dono=$(stat -c '%u' -- "$arquivo")
    perm=$(stat -c '%a' -- "$arquivo")
    if [ "$dono" != "0" ] || (( 8#$perm & 8#022 )); then
        DEBKIT_CONF_ERROS="$arquivo: precisa pertencer ao root e não ter escrita para grupo/outros (atual: dono UID $dono, permissão $perm)"
        return 1
    fi

    while IFS= read -r linha || [ -n "$linha" ]; do
        n=$((n + 1))
        linha="${linha%$'\r'}"
        [[ "$linha" =~ ^[[:space:]]*(#.*)?$ ]] && continue
        if [[ ! "$linha" =~ ^[[:space:]]*([A-Z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            DEBKIT_CONF_ERROS+="linha $n: formato inválido (use CHAVE=valor)"$'\n'
            continue
        fi
        chave="${BASH_REMATCH[1]}"
        valor="${BASH_REMATCH[2]}"
        valor="${valor%"${valor##*[![:space:]]}"}"        # tira espaços do fim
        if [[ "$valor" =~ ^\"(.*)\"$ || "$valor" =~ ^\'(.*)\'$ ]]; then
            valor="${BASH_REMATCH[1]}"                    # tira aspas
        fi
        if [ -z "${DEBKIT_CONF_TIPO[$chave]+x}" ]; then
            DEBKIT_CONF_AVISOS+="linha $n: chave desconhecida '$chave' (ignorada)"$'\n'
            continue
        fi
        if ! debkit_conf_valor_valido "${DEBKIT_CONF_TIPO[$chave]}" "$valor"; then
            DEBKIT_CONF_ERROS+="linha $n: valor inválido para $chave: '$valor'"$'\n'
            continue
        fi
        printf -v "DEBKIT_${chave}" '%s' "$valor"
    done < "$arquivo"

    DEBKIT_CONF_ERROS="${DEBKIT_CONF_ERROS%$'\n'}"
    DEBKIT_CONF_AVISOS="${DEBKIT_CONF_AVISOS%$'\n'}"
    [ -z "$DEBKIT_CONF_ERROS" ]
}

# ════════════════════════════════════════════════════════════════════════════
# 3. MENSAGENS (catálogo)
# ════════════════════════════════════════════════════════════════════════════
# Todo texto visível sai daqui. Uso: t <chave> [argumentos do printf]
# Chave que faltar no idioma escolhido cai no pt_BR; se faltar nos dois,
# aparece a própria chave (facilita achar o que falta).

declare -A MSG_pt_BR=(
    [geral.titulo]="debkit - Gerenciador Samba"
    [geral.versao]="debkit %s"
    [geral.sim_nao]="(s/n)"
    [geral.escolha]="Escolha uma opção: "
    [geral.enter_voltar]="Pressione Enter para voltar..."
    [geral.opcao_invalida]="Opção inválida: '%s'"
    [geral.sair]="Sair"
    [geral.em_construcao]="(as funções serão adicionadas nas próximas etapas)"
    [geral.interrompido]="Interrompido. Nada mais foi feito."
    [erro.root]="Este comando precisa ser executado como root (ex: sudo debkit)."
    [erro.uso]="Opção desconhecida: '%s'. Veja: debkit --ajuda"
    [erro.conf]="Configuração inválida em %s:"
    [aviso.conf]="Avisos da configuração %s:"
    [erro.trava]="O debkit já está em uso por outra sessão (PID %s). Tente novamente quando ela terminar."
    [erro.trava_abrir]="Não foi possível criar o arquivo de trava %s."
    [menu.ambiente]="Ambiente: verificar e preparar"
    [amb.titulo]="Ambiente do servidor"
    [amb.grupo_sistema]="Sistema"
    [amb.grupo_deps]="Dependências essenciais"
    [amb.grupo_samba]="Samba"
    [amb.grupo_ssh]="SSH"
    [amb.grupo_dev]="Desenvolvimento (opcional)"
    [amb.grupo_firewall]="Firewall"
    [amb.so_desconhecido]="Sistema não identificado (%s ausente ou ilegível)"
    [amb.so_nao_debian]="Distribuição fora da família Debian: não testada; instalação automática indisponível"
    [amb.systemd_ok]="systemd em execução"
    [amb.systemd_falta]="systemd não está em execução (ex: container): o debkit precisa dele para gerenciar serviços"
    [amb.deps_ok]="Todas as %d dependências essenciais presentes"
    [amb.dep_falta]="Falta o comando %s (pacote %s)"
    [amb.samba_ausente]="Samba não instalado"
    [amb.servico_ativo]="Serviço %s ativo"
    [amb.servico_parado]="Serviço %s parado"
    [amb.servico_desabilitado]="Serviço %s não inicia junto com o sistema"
    [amb.servico_nao_encontrado]="Serviço do Samba (%s) não encontrado no systemd"
    [amb.smbconf_ausente]="%s não existe"
    [amb.smbconf_invalido]="%s com erro (veja: testparm)"
    [amb.smbconf_ok]="%s válido"
    [amb.papel_ok]="Modo: servidor de arquivos independente (standalone)"
    [amb.papel_dc]="Modo: %s - controlador de domínio NÃO é suportado pelo debkit"
    [amb.papel_outro]="Modo: %s (não testado com o debkit)"
    [amb.backend_ok]="Base de senhas: %s"
    [amb.backend_outro]="Base de senhas: %s - não suportada (o debkit usa tdbsam)"
    [amb.ssh_ausente]="Servidor SSH não instalado: proteção SSH não necessária"
    [amb.dropin_ok]="%s inclui %s (o debkit pode usar arquivo próprio)"
    [amb.dropin_falta]="%s não inclui %s: a proteção SSH automática não poderá ser aplicada"
    [amb.ssh_senha]="Login por senha ligado no SSH: a proteção dos usuários do debkit é importante"
    [amb.dropin_apos_match]="%s inclui %s só DEPOIS de um bloco Match: a proteção não valeria para todos (mova o Include para antes do primeiro Match)"
    [amb.ssh_protecao_ativa]="Proteção SSH do debkit ativa (grupo %s recusado no SSH)"
    [amb.ssh_protecao_inativa]="Proteção SSH do debkit ainda não aplicada"
    [amb.fw_nenhum]="Nenhum firewall ativo (ufw/firewalld): nada bloqueia o Samba"
    [amb.fw_libera]="%s ativo e libera o Samba (porta %s)"
    [amb.fw_bloqueia]="%s ativo e NÃO libera o Samba (porta %s): os computadores não conseguirão acessar"
    [amb.fw_cru]="Regras próprias de nftables/iptables detectadas: confira se a porta %s/tcp está liberada para a rede local"
    [amb.dev_ok]="%s instalado"
    [amb.dev_falta]="%s não instalado (só para desenvolvimento/testes)"
    [amb.resumo_ok]="Ambiente pronto para o debkit."
    [amb.resumo_falta]="%d item(ns) essencial(is) impedem o debkit de funcionar."
    [amb.pacotes]="Pacotes necessários: %s"
    [prep.titulo_assistente]="Preparação do servidor para o debkit"
    [prep.intro]="O debkit verificou este servidor e precisa preparar algumas coisas antes do primeiro uso."
    [prep.titulo_plano]="O debkit vai:"
    [prep.d_pacotes]="Instalar os pacotes: %s"
    [prep.d_samba_servico]="Deixar o serviço do Samba ativo e iniciando junto com o sistema"
    [prep.d_dir_conf]="Criar a pasta de configuração %s"
    [prep.d_conf]="Criar a configuração %s (com os valores padrão)"
    [prep.d_dir_backup]="Criar a pasta de backups %s (acesso só do root)"
    [prep.d_log]="Criar o log de auditoria %s"
    [prep.d_grupo]="Criar o grupo de sistema %s (usuários do debkit)"
    [prep.d_shares_conf]="Criar o arquivo de compartilhamentos do debkit %s"
    [prep.d_include]="Incluir no %s a linha \"include = %s\" (com backup e validação)"
    [prep.pergunta]="Preparar agora?"
    [prep.recusado]="Nada foi alterado. O debkit vai funcionar de forma limitada até o ambiente ser preparado (menu 9)."
    [prep.nada_a_fazer]="O ambiente já está preparado. Nada a fazer."
    [prep.concluido]="Ambiente preparado com sucesso."
    [prep.falhou]="Falhou: %s"
    [prep.desfazendo]="Desfazendo o que o debkit já tinha feito..."
    [prep.mantidos_pacotes]="Os pacotes instalados foram mantidos: %s"
    [prep.mantido_servico]="O serviço do Samba foi mantido ligado."
    [prep.impossivel_manual]="Há itens que o debkit não pode resolver sozinho (marcados com ✘). Corrija-os e execute o debkit novamente."
    [prep.impossivel_pacotes]="Instalação automática indisponível neste sistema. Instale manualmente: %s"
    [prep.apt_atualizando]="Atualizando a lista de pacotes (apt-get update)..."
    [prep.apt_update_falhou]="Não foi possível atualizar a lista de pacotes; tentando instalar mesmo assim."
    [prep.apt_instalando]="Instalando: %s (pode levar alguns minutos)..."
    [prep.apt_falhou]="A instalação falhou (sem internet? repositórios com erro?). Últimas linhas:"
    [prep.apt_conferencia]="Depois da instalação, o comando %s ainda não existe (pacote %s)."
    [prep.servico_falhou]="Não foi possível ativar o serviço %s (veja: systemctl status %s)."
    [prep.include_testparm]="O smb.conf ficou inválido com a linha do debkit (testparm)."
    [prep.recarregar_falhou]="Não foi possível recarregar o Samba."
    [prep.backup_sem_arquivo]="Backup impossível: %s não existe."
    [prep.backup_falhou]="Não foi possível fazer o backup de %s."
    [prep.d_ssh_protecao]="Bloquear o SSH para os usuários do debkit (%s com \"DenyGroups %s\"), validar e recarregar o SSH sem derrubar ninguém"
    [prep.ssh_admin_no_grupo]="Você (%s) é membro de %s: aplicar a proteção trancaria você fora do SSH. Nada foi feito."
    [prep.ssh_arquivo_alheio]="%s já existe e não foi criado pelo debkit: o debkit não vai sobrescrevê-lo."
    [prep.ssh_invalido]="A configuração do SSH ficou inválida (sshd -t); o SSH NÃO foi recarregado:"
    [prep.ssh_recarregar]="Não foi possível recarregar o SSH (%s)."
    [prep.ssh_nao_confirmada]="A regra não apareceu na configuração em vigor do SSH (sshd -T)."
    [prep.d_firewall]="Liberar o Samba (porta %s/tcp) no %s só para as redes locais: %s"
    [prep.fw_sem_redes]="Nenhuma rede local encontrada para liberar o Samba no firewall."
    [prep.fw_falhou]="Não foi possível criar a regra no %s (%s)."
    [prep.fw_nao_confirmada]="A liberação do Samba não foi confirmada no firewall."
    [ajuda.texto]="Uso: debkit [opção]

  (sem opção)    abre o menu interativo (precisa ser root)
  --verificar    verifica o ambiente, sem alterar nada (precisa ser root)
  --preparar     verifica e prepara o ambiente (pede confirmação)
  -h, --ajuda    mostra esta ajuda
  -v, --versao   mostra a versão

Configuração: %s
Documentação: docs/PLANEJAMENTO.md"
)

declare -A MSG_en=(
    [geral.titulo]="debkit - Samba Manager"
    [geral.versao]="debkit %s"
    [geral.sim_nao]="(y/n)"
    [geral.escolha]="Choose an option: "
    [geral.enter_voltar]="Press Enter to go back..."
    [geral.opcao_invalida]="Invalid option: '%s'"
    [geral.sair]="Exit"
    [geral.em_construcao]="(features will be added in the next steps)"
    [geral.interrompido]="Interrupted. Nothing else was done."
    [erro.root]="This command must be run as root (e.g. sudo debkit)."
    [erro.uso]="Unknown option: '%s'. See: debkit --help"
    [erro.conf]="Invalid configuration in %s:"
    [aviso.conf]="Configuration warnings in %s:"
    [erro.trava]="debkit is already in use by another session (PID %s). Try again when it finishes."
    [erro.trava_abrir]="Could not create the lock file %s."
    [menu.ambiente]="Environment: check and set up"
    [amb.titulo]="Server environment"
    [amb.grupo_sistema]="System"
    [amb.grupo_deps]="Essential dependencies"
    [amb.grupo_samba]="Samba"
    [amb.grupo_ssh]="SSH"
    [amb.grupo_dev]="Development (optional)"
    [amb.grupo_firewall]="Firewall"
    [amb.so_desconhecido]="Unknown system (%s missing or unreadable)"
    [amb.so_nao_debian]="Distribution outside the Debian family: untested; automatic installation unavailable"
    [amb.systemd_ok]="systemd running"
    [amb.systemd_falta]="systemd is not running (e.g. container): debkit needs it to manage services"
    [amb.deps_ok]="All %d essential dependencies present"
    [amb.dep_falta]="Missing command %s (package %s)"
    [amb.samba_ausente]="Samba is not installed"
    [amb.servico_ativo]="Service %s active"
    [amb.servico_parado]="Service %s stopped"
    [amb.servico_desabilitado]="Service %s does not start at boot"
    [amb.servico_nao_encontrado]="Samba service (%s) not found in systemd"
    [amb.smbconf_ausente]="%s does not exist"
    [amb.smbconf_invalido]="%s has errors (see: testparm)"
    [amb.smbconf_ok]="%s is valid"
    [amb.papel_ok]="Role: standalone file server"
    [amb.papel_dc]="Role: %s - domain controllers are NOT supported by debkit"
    [amb.papel_outro]="Role: %s (not tested with debkit)"
    [amb.backend_ok]="Password backend: %s"
    [amb.backend_outro]="Password backend: %s - not supported (debkit uses tdbsam)"
    [amb.ssh_ausente]="SSH server not installed: SSH protection not needed"
    [amb.dropin_ok]="%s includes %s (debkit can use its own file)"
    [amb.dropin_falta]="%s does not include %s: automatic SSH protection cannot be applied"
    [amb.ssh_senha]="SSH password login is enabled: protecting debkit users matters"
    [amb.dropin_apos_match]="%s includes %s only AFTER a Match block: the protection would not apply to everyone (move the Include before the first Match)"
    [amb.ssh_protecao_ativa]="debkit SSH protection active (group %s denied on SSH)"
    [amb.ssh_protecao_inativa]="debkit SSH protection not applied yet"
    [amb.fw_nenhum]="No active firewall (ufw/firewalld): nothing blocks Samba"
    [amb.fw_libera]="%s active and allows Samba (port %s)"
    [amb.fw_bloqueia]="%s active and does NOT allow Samba (port %s): computers will not be able to connect"
    [amb.fw_cru]="Custom nftables/iptables rules detected: check that port %s/tcp is open to the local network"
    [amb.dev_ok]="%s installed"
    [amb.dev_falta]="%s not installed (development/testing only)"
    [amb.resumo_ok]="Environment ready for debkit."
    [amb.resumo_falta]="%d essential item(s) prevent debkit from working."
    [amb.pacotes]="Required packages: %s"
    [prep.titulo_assistente]="Preparing the server for debkit"
    [prep.intro]="debkit checked this server and needs to prepare a few things before first use."
    [prep.titulo_plano]="debkit will:"
    [prep.d_pacotes]="Install the packages: %s"
    [prep.d_samba_servico]="Make the Samba service active and start at boot"
    [prep.d_dir_conf]="Create the configuration folder %s"
    [prep.d_conf]="Create the configuration %s (default values)"
    [prep.d_dir_backup]="Create the backup folder %s (root only)"
    [prep.d_log]="Create the audit log %s"
    [prep.d_grupo]="Create the system group %s (debkit users)"
    [prep.d_shares_conf]="Create the debkit shares file %s"
    [prep.d_include]="Add to %s the line \"include = %s\" (with backup and validation)"
    [prep.pergunta]="Set up now?"
    [prep.recusado]="Nothing was changed. debkit will work in a limited way until the environment is set up (menu 9)."
    [prep.nada_a_fazer]="The environment is already set up. Nothing to do."
    [prep.concluido]="Environment set up successfully."
    [prep.falhou]="Failed: %s"
    [prep.desfazendo]="Undoing what debkit had already done..."
    [prep.mantidos_pacotes]="The installed packages were kept: %s"
    [prep.mantido_servico]="The Samba service was kept running."
    [prep.impossivel_manual]="Some items cannot be fixed by debkit (marked with ✘). Fix them and run debkit again."
    [prep.impossivel_pacotes]="Automatic installation is not available on this system. Install manually: %s"
    [prep.apt_atualizando]="Updating the package list (apt-get update)..."
    [prep.apt_update_falhou]="Could not update the package list; trying to install anyway."
    [prep.apt_instalando]="Installing: %s (this may take a few minutes)..."
    [prep.apt_falhou]="Installation failed (no internet? broken repositories?). Last lines:"
    [prep.apt_conferencia]="After installation, the command %s still does not exist (package %s)."
    [prep.servico_falhou]="Could not activate the service %s (see: systemctl status %s)."
    [prep.include_testparm]="smb.conf became invalid with the debkit line (testparm)."
    [prep.recarregar_falhou]="Could not reload Samba."
    [prep.backup_sem_arquivo]="Backup impossible: %s does not exist."
    [prep.backup_falhou]="Could not back up %s."
    [prep.d_ssh_protecao]="Block SSH for debkit users (%s with \"DenyGroups %s\"), validate and reload SSH without dropping anyone"
    [prep.ssh_admin_no_grupo]="You (%s) are a member of %s: applying the protection would lock you out of SSH. Nothing was done."
    [prep.ssh_arquivo_alheio]="%s already exists and was not created by debkit: debkit will not overwrite it."
    [prep.ssh_invalido]="The SSH configuration became invalid (sshd -t); SSH was NOT reloaded:"
    [prep.ssh_recarregar]="Could not reload SSH (%s)."
    [prep.ssh_nao_confirmada]="The rule did not show up in the effective SSH configuration (sshd -T)."
    [prep.d_firewall]="Allow Samba (port %s/tcp) on %s only for the local networks: %s"
    [prep.fw_sem_redes]="No local network found to allow Samba in the firewall."
    [prep.fw_falhou]="Could not create the rule on %s (%s)."
    [prep.fw_nao_confirmada]="The Samba rule could not be confirmed in the firewall."
    [ajuda.texto]="Usage: debkit [option]

  (no option)    opens the interactive menu (requires root)
  --check        checks the environment without changing anything (requires root)
  --setup        checks and sets up the environment (asks for confirmation)
  -h, --help     shows this help
  -v, --version  shows the version

Configuration: %s
Documentation: docs/PLANEJAMENTO.md"
)

# Imprime a mensagem <chave> formatada com os argumentos (sem quebra de linha)
t() {
    local chave="$1" formato
    shift
    if [ "${DEBKIT_IDIOMA:-pt_BR}" == "en" ] && [ -n "${MSG_en[$chave]+x}" ]; then
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
debkit_cores() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
        C_VERDE=$'\033[0;32m'; C_AMARELO=$'\033[1;33m'; C_VERMELHO=$'\033[0;31m'
        C_CIANO=$'\033[0;36m'; C_CINZA=$'\033[0;90m'; C_NEGRITO=$'\033[1m'; C_RESET=$'\033[0m'
    else
        C_VERDE=""; C_AMARELO=""; C_VERMELHO=""; C_CIANO=""; C_CINZA=""; C_NEGRITO=""; C_RESET=""
    fi
}
debkit_cores

DEBKIT_LINHA="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

msg_ok()    { printf '%s>> [OK]%s %s\n' "$C_VERDE" "$C_RESET" "$*"; }
msg_info()  { printf '%s>>%s %s\n' "$C_CIANO" "$C_RESET" "$*"; }
msg_aviso() { printf '%s>> [!]%s %s\n' "$C_AMARELO" "$C_RESET" "$*"; }
msg_erro()  { printf '%s>> [X]%s %s\n' "$C_VERMELHO" "$C_RESET" "$*" >&2; }

# Título de tela: limpa a tela (se for terminal) e mostra o título
titulo() {
    [ -t 1 ] && clear
    printf '%s%s%s\n' "$C_CIANO" "$DEBKIT_LINHA" "$C_RESET"
    printf '%s  %s%s\n' "$C_NEGRITO" "$*" "$C_RESET"
    printf '%s%s%s\n' "$C_CIANO" "$DEBKIT_LINHA" "$C_RESET"
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
# encerra o debkit, em vez de repetir o menu para sempre.
ler_opcao() {
    local -n _destino="$1"
    if ! read -rp "$(t geral.escolha)" _destino; then
        echo ""
        DEBKIT_MOTIVO_SAIDA="fim_da_entrada"
        exit 0
    fi
}

# ── Arquivos temporários (apagados ao sair, mesmo com Ctrl+C) ───────────────
DEBKIT_TEMPORARIOS=()

# Cria um arquivo temporário protegido (600) e imprime o caminho
debkit_temp() {
    local arq
    arq=$(umask 077; mktemp "${TMPDIR:-/tmp}/debkit.XXXXXX") || return 1
    DEBKIT_TEMPORARIOS+=("$arq")
    echo "$arq"
}

debkit_limpar() {
    local arq
    for arq in "${DEBKIT_TEMPORARIOS[@]}"; do
        [ -n "$arq" ] && rm -f -- "$arq"
    done
    DEBKIT_TEMPORARIOS=()
}

# ── Saída: roda SEMPRE (trap EXIT), seja qual for o jeito de sair ───────────
# Apaga temporários e, se havia sessão aberta, registra no log como ela
# terminou (normal, interrompida, fim_da_entrada). Assim a auditoria nunca
# fica com um "início" sem "fim".
DEBKIT_SESSAO_ATIVA=0
DEBKIT_MOTIVO_SAIDA="normal"

debkit_ao_sair() {
    debkit_limpar
    if [ "$DEBKIT_SESSAO_ATIVA" -eq 1 ]; then
        debkit_auditar sessao_fim "motivo=$DEBKIT_MOTIVO_SAIDA"
        DEBKIT_SESSAO_ATIVA=0
    fi
}

# ── Trava: uma execução do debkit por vez ──────────────────────────────────────
# Mantém o descritor aberto até o fim do processo (o sistema libera sozinho).
debkit_travar() {
    local pid
    if ! { exec {DEBKIT_FD_TRAVA}>>"$DEBKIT_TRAVA"; } 2>/dev/null; then
        msg_erro "$(t erro.trava_abrir "$DEBKIT_TRAVA")"
        return 1
    fi
    if ! flock -n "$DEBKIT_FD_TRAVA"; then
        pid=$(head -c 20 -- "$DEBKIT_TRAVA" 2>/dev/null | tr -cd '0-9')
        msg_erro "$(t erro.trava "${pid:-?}")"
        return 1
    fi
    : > "$DEBKIT_TRAVA"
    echo "$$" > "$DEBKIT_TRAVA"
}

# ── Log de auditoria ────────────────────────────────────────────────────────
# Registra: data/hora, quem (usuário real, mesmo via sudo), PID, ação e
# detalhes. NUNCA passar senhas. Quebras de linha viram espaço (impede
# forjar linhas falsas no log). Retorna 1 se não conseguir gravar.
debkit_auditar() {
    local acao="$1" quem detalhes
    shift
    quem="${SUDO_USER:-$(logname 2>/dev/null || id -un)}"
    detalhes="$*"
    detalhes="${detalhes//$'\n'/ }"
    detalhes="${detalhes//$'\r'/ }"
    acao="${acao//[$'\n\r ']/_}"
    ( umask 027; printf '%s %s[%s] %s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$quem" "$$" "$acao" "$detalhes" >> "$DEBKIT_LOG" ) 2>/dev/null
}

# ════════════════════════════════════════════════════════════════════════════
# 6. AMBIENTE (detecção - somente leitura)
# ════════════════════════════════════════════════════════════════════════════
# Descobre o que existe na máquina: sistema, systemd, dependências, Samba e
# SSH. Nada aqui altera o sistema. O resultado alimenta o relatório
# (debkit --verificar / menu Ambiente) e, na tarefa 0.3, a preparação.

# Arquivos do sistema consultados (variáveis para os testes poderem simular)
DEBKIT_ARQ_OS_RELEASE="${DEBKIT_ARQ_OS_RELEASE:-/etc/os-release}"
DEBKIT_ARQ_SSHD_CONFIG="${DEBKIT_ARQ_SSHD_CONFIG:-/etc/ssh/sshd_config}"
DEBKIT_DIR_SYSTEMD="${DEBKIT_DIR_SYSTEMD:-/run/systemd/system}"

# Tabela de dependências - ÚNICO ponto específico da distribuição.
# comando | tipo | pacote no Debian
#   essencial      : sem ele o debkit não funciona (a 0.3 oferece instalar)
#   condicional    : só necessário se existir (ex: SSH -> proteção)
#   desenvolvimento: só para quem desenvolve/testa o debkit; nunca instalado
DEBKIT_DEPENDENCIAS=(
    "smbd|essencial|samba"
    "pdbedit|essencial|samba"
    "smbstatus|essencial|samba"
    "testparm|essencial|samba-common-bin"
    "smbpasswd|essencial|samba-common-bin"
    "smbcontrol|essencial|samba-common-bin"
    "useradd|essencial|passwd"
    "usermod|essencial|passwd"
    "userdel|essencial|passwd"
    "groupadd|essencial|passwd"
    "groupdel|essencial|passwd"
    "gpasswd|essencial|passwd"
    "chpasswd|essencial|passwd"
    "flock|essencial|util-linux"
    "getent|essencial|libc-bin"
    "awk|essencial|mawk"
    "sed|essencial|sed"
    "grep|essencial|grep"
    "stat|essencial|coreutils"
    "mktemp|essencial|coreutils"
    "realpath|essencial|coreutils"
    "systemctl|essencial|systemd"
    "sshd|condicional|openssh-server"
    "shellcheck|desenvolvimento|shellcheck"
    "smbclient|desenvolvimento|smbclient"
)

# Verifica se um comando existe (função separada para os testes simularem)
debkit_tem_comando() { command -v "$1" >/dev/null 2>&1; }

# Lê o /etc/os-release SEM executá-lo (só ID, ID_LIKE, VERSION_ID, PRETTY_NAME)
debkit_ler_os_release() {
    local linha chave valor
    DEBKIT_SO_ID=""; DEBKIT_SO_ID_LIKE=""; DEBKIT_SO_VERSAO=""; DEBKIT_SO_NOME=""
    [ -r "$DEBKIT_ARQ_OS_RELEASE" ] || return 1
    while IFS= read -r linha || [ -n "$linha" ]; do
        [[ "$linha" =~ ^([A-Z_]+)=(.*)$ ]] || continue
        chave="${BASH_REMATCH[1]}"
        valor="${BASH_REMATCH[2]}"
        if [[ "$valor" =~ ^\"(.*)\"$ || "$valor" =~ ^\'(.*)\'$ ]]; then
            valor="${BASH_REMATCH[1]}"
        fi
        case "$chave" in
            ID)          DEBKIT_SO_ID="$valor" ;;
            ID_LIKE)     DEBKIT_SO_ID_LIKE="$valor" ;;
            VERSION_ID)  DEBKIT_SO_VERSAO="$valor" ;;
            PRETTY_NAME) DEBKIT_SO_NOME="$valor" ;;
        esac
    done < "$DEBKIT_ARQ_OS_RELEASE"
    return 0
}

# Debian ou derivado (Ubuntu, Mint...)? Usar depois de debkit_ler_os_release.
debkit_familia_debian() {
    [ "$DEBKIT_SO_ID" == "debian" ] || [[ " $DEBKIT_SO_ID_LIKE " == *" debian "* ]]
}

# Serviços (systemd)
debkit_servico_existe()    { systemctl list-unit-files --no-legend "$1.service" 2>/dev/null | grep -q .; }
debkit_servico_ativo()     { systemctl is-active --quiet "$1.service" 2>/dev/null; }
debkit_servico_habilitado() { systemctl is-enabled --quiet "$1.service" 2>/dev/null; }

# Primeiro nome de serviço existente da lista (smbd no Debian, smb no RHEL...)
debkit_descobrir_servico() {
    local nome
    for nome in "$@"; do
        debkit_servico_existe "$nome" && { echo "$nome"; return 0; }
    done
    return 1
}

# O sshd_config inclui o arquivo próprio do debkit (DEBKIT_SSH_DROPIN)?
# Lê as linhas "Include" (palavra sem diferenciar maiúsculas; caminhos
# relativos são relativos a /etc/ssh) e testa se algum padrão cobre o arquivo.
# Retorna: 0 = inclui; 1 = não inclui; 2 = inclui só DEPOIS de um bloco
# "Match" (aí a regra do debkit valeria só dentro do Match, não para todos -
# comprovado com sshd -T).
debkit_ssh_aceita_dropin() {
    local linha padrao depois_de_match=0
    local -a padroes
    [ -r "$DEBKIT_ARQ_SSHD_CONFIG" ] || return 1
    while IFS= read -r linha || [ -n "$linha" ]; do
        if [[ "$linha" =~ ^[[:space:]]*[Mm][Aa][Tt][Cc][Hh][[:space:]] ]]; then
            depois_de_match=1
            continue
        fi
        [[ "$linha" =~ ^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]]+(.+)$ ]] || continue
        read -ra padroes <<< "${BASH_REMATCH[1]}"
        for padrao in "${padroes[@]}"; do
            [[ "$padrao" == /* ]] || padrao="/etc/ssh/$padrao"
            # shellcheck disable=SC2053  # comparação com padrão (glob) proposital
            if [[ "$DEBKIT_SSH_DROPIN" == $padrao ]]; then
                [ "$depois_de_match" -eq 1 ] && return 2
                return 0
            fi
        done
    done < "$DEBKIT_ARQ_SSHD_CONFIG"
    return 1
}

# A proteção está EFETIVA? Consulta a configuração geral em vigor (sshd -T),
# não só se o arquivo existe: o grupo precisa estar em "denygroups".
debkit_ssh_protecao_ativa() {
    sshd -T 2>/dev/null | awk -v g="$DEBKIT_GRUPO_USUARIOS" \
        '$1 == "denygroups" { for (i = 2; i <= NF; i++) if ($i == g) achou = 1 } END { exit !achou }'
}

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

# ── Firewall ────────────────────────────────────────────────────────────────
# O debkit só libera a porta 445/tcp (SMB moderno; NetBIOS 137-139 fica fechado)
# e só para as redes locais do servidor - nunca para qualquer origem.
DEBKIT_FW_PORTA=445
DEBKIT_FW_COMENTARIO="debkit: Samba"

# Redes IPv4 ligadas diretamente às interfaces (rotas "scope link"), sem
# loopback, bridges de container/VM e link-local. Uma por linha.
# (Não filtra por "proto kernel": rede vinda do DHCP também conta.)
debkit_redes_locais() {
    ip -4 -o route show scope link 2>/dev/null | awk '
        { rede = $1; dev = ""
          for (i = 2; i <= NF; i++) if ($i == "dev") dev = $(i + 1)
          if (rede !~ /\//) next                                  # rota de host
          if (rede ~ /^169\.254\./) next                          # link-local
          if (dev ~ /^(lo|docker|br-|veth|virbr|lxc|cni|flannel)/) next
          print rede }' | sort -u
}

# ufw sempre em inglês (a saída é interpretada)
debkit_ufw() { LC_ALL=C ufw "$@"; }

debkit_fw_ufw_ativo() { debkit_tem_comando ufw && debkit_ufw status 2>/dev/null | grep -q '^Status: active'; }

# O ufw libera o Samba? Política padrão de entrada "allow" (só aparece com o
# ufw ativo) ou alguma regra ALLOW para a porta 445 / perfil Samba (lida do
# "ufw show added", que funciona com o ufw ativo ou não).
debkit_fw_ufw_libera() {
    debkit_ufw status verbose 2>/dev/null | grep -qE '^Default: allow \(incoming\)' && return 0
    # 445 sozinha, em lista (22,445/tcp) ou como "port 445"; nunca 4450/1445
    debkit_ufw show added 2>/dev/null | grep -E '^ufw allow' \
        | grep -qE "(port |^ufw allow |,)$DEBKIT_FW_PORTA(,[0-9,]*)?(/tcp)?( |$)|[ ,]$DEBKIT_FW_PORTA(/tcp)?( |$)|Samba"
}

debkit_fw_firewalld_ativo() { debkit_tem_comando firewall-cmd && firewall-cmd --state >/dev/null 2>&1; }

debkit_fw_firewalld_zona() { firewall-cmd --get-default-zone 2>/dev/null; }

# O firewalld (zona padrão) libera o Samba? Serviço samba, porta 445/tcp,
# regra rich para a porta 445 ou zona que aceita tudo.
debkit_fw_firewalld_libera() {
    local zona
    zona=$(debkit_fw_firewalld_zona) || return 1
    firewall-cmd --zone="$zona" --query-service=samba >/dev/null 2>&1 && return 0
    firewall-cmd --zone="$zona" --query-port="$DEBKIT_FW_PORTA/tcp" >/dev/null 2>&1 && return 0
    firewall-cmd --zone="$zona" --list-rich-rules 2>/dev/null | grep -q "port=\"$DEBKIT_FW_PORTA\"" && return 0
    [ "$(firewall-cmd --permanent --zone="$zona" --get-target 2>/dev/null)" == "ACCEPT" ]
}

# Regras nftables/iptables próprias que podem bloquear entrada (só quando não
# há ufw/firewalld: as regras desses dois também aparecem no nft/iptables)
debkit_fw_regras_cruas() {
    if debkit_tem_comando nft && nft list ruleset 2>/dev/null | grep -qE 'hook input.*policy drop|^[[:space:]]*(drop|reject)|[[:space:]](drop|reject)$'; then
        return 0
    fi
    debkit_tem_comando iptables && iptables -S INPUT 2>/dev/null | grep -qE '^-P INPUT DROP|-j (DROP|REJECT)'
}

# ── Resultado da verificação ────────────────────────────────────────────────
# DEBKIT_VERIF: linhas "grupo<TAB>estado<TAB>texto"
#   estados: ok | falta (impede o uso) | aviso | info | na (não se aplica)
# DEBKIT_PACOTES_FALTANDO: pacotes (Debian) dos itens essenciais que faltam
# DEBKIT_BLOQUEIOS: quantos itens impedem o debkit de funcionar
debkit_verif_add() { DEBKIT_VERIF+=("$1"$'\t'"$2"$'\t'"$3"); [ "$2" == "falta" ] && DEBKIT_BLOQUEIOS=$((DEBKIT_BLOQUEIOS + 1)); return 0; }

# Bloqueio que o debkit NÃO consegue resolver sozinho (exige o administrador)
debkit_verif_manual() { debkit_verif_add "$1" falta "$2"; DEBKIT_BLOQ_MANUAL=$((DEBKIT_BLOQ_MANUAL + 1)); }

debkit_pacote_add() {
    local p
    [ -z "$1" ] && return 0
    for p in "${DEBKIT_PACOTES_FALTANDO[@]}"; do [ "$p" == "$1" ] && return 0; done
    DEBKIT_PACOTES_FALTANDO+=("$1")
}

# Faz toda a verificação. Retorna 0 se nada impede o debkit de funcionar.
# Além de DEBKIT_VERIF / DEBKIT_PACOTES_FALTANDO / DEBKIT_BLOQUEIOS, deixa prontos
# para a preparação (0.3) e a proteção SSH (0.4):
#   DEBKIT_SVC_SAMBA / DEBKIT_SVC_SSH  nome do serviço (vazio se não encontrado)
#   DEBKIT_TEM_SSH                  1 se o servidor SSH está instalado
#   DEBKIT_SSH_DROPIN_OK            1 se o sshd_config inclui o arquivo do debkit
#                                (e não só depois de um bloco Match)
#   DEBKIT_SSH_PROTEGIDO            1 se a proteção SSH está efetiva (sshd -T)
#   DEBKIT_FW_TIPO                  ufw | firewalld | "" (nenhum gerenciável ativo)
#   DEBKIT_FW_LIBERA                1 se esse firewall já libera o Samba
#   DEBKIT_BLOQ_MANUAL              bloqueios que exigem o administrador
#                                (os demais se resolvem instalando pacotes)
# shellcheck disable=SC2034  # variáveis de saída, usadas pelas próximas tarefas
debkit_verificar_ambiente() {
    local dep cmd tipo pacote presentes=0 total=0 papel backend senha_ssh
    DEBKIT_VERIF=(); DEBKIT_PACOTES_FALTANDO=(); DEBKIT_BLOQUEIOS=0; DEBKIT_BLOQ_MANUAL=0
    DEBKIT_SVC_SAMBA=""; DEBKIT_SVC_SSH=""; DEBKIT_TEM_SSH=0; DEBKIT_SSH_DROPIN_OK=0; DEBKIT_SSH_PROTEGIDO=0
    DEBKIT_FW_TIPO=""; DEBKIT_FW_LIBERA=0

    # ── Sistema ──
    if debkit_ler_os_release; then
        debkit_verif_add sistema ok "${DEBKIT_SO_NOME:-$DEBKIT_SO_ID $DEBKIT_SO_VERSAO}"
        debkit_familia_debian || debkit_verif_add sistema aviso "$(t amb.so_nao_debian)"
    else
        debkit_verif_add sistema aviso "$(t amb.so_desconhecido "$DEBKIT_ARQ_OS_RELEASE")"
    fi
    debkit_verif_add sistema ok "bash $BASH_VERSION"
    if [ -d "$DEBKIT_DIR_SYSTEMD" ]; then
        debkit_verif_add sistema ok "$(t amb.systemd_ok)"
    else
        debkit_verif_manual sistema "$(t amb.systemd_falta)"
    fi

    # ── Dependências ──
    for dep in "${DEBKIT_DEPENDENCIAS[@]}"; do
        IFS='|' read -r cmd tipo pacote <<< "$dep"
        case "$tipo" in
            essencial)
                total=$((total + 1))
                if debkit_tem_comando "$cmd"; then
                    presentes=$((presentes + 1))
                else
                    debkit_verif_add deps falta "$(t amb.dep_falta "$cmd" "$pacote")"
                    # systemd não se resolve instalando o pacote (ex: container)
                    [ "$cmd" != "systemctl" ] && debkit_pacote_add "$pacote"
                fi ;;
            desenvolvimento)
                if debkit_tem_comando "$cmd"; then
                    debkit_verif_add dev ok "$(t amb.dev_ok "$cmd")"
                else
                    debkit_verif_add dev info "$(t amb.dev_falta "$cmd")"
                fi ;;
        esac
    done
    [ "$presentes" -eq "$total" ] && debkit_verif_add deps ok "$(t amb.deps_ok "$total")"

    # ── Samba ──
    if ! debkit_tem_comando smbd; then
        debkit_verif_add samba falta "$(t amb.samba_ausente)"
    else
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
        fi
    fi

    # ── SSH (condicional) ──
    if ! debkit_tem_comando sshd; then
        debkit_verif_add ssh na "$(t amb.ssh_ausente)"
    else
        DEBKIT_TEM_SSH=1
        if DEBKIT_SVC_SSH=$(debkit_descobrir_servico ssh sshd); then
            if debkit_servico_ativo "$DEBKIT_SVC_SSH"; then
                debkit_verif_add ssh ok "$(t amb.servico_ativo "$DEBKIT_SVC_SSH")"
            else
                debkit_verif_add ssh info "$(t amb.servico_parado "$DEBKIT_SVC_SSH")"
            fi
        fi
        debkit_ssh_aceita_dropin
        case $? in
            0) DEBKIT_SSH_DROPIN_OK=1
               debkit_verif_add ssh ok "$(t amb.dropin_ok "$DEBKIT_ARQ_SSHD_CONFIG" "$DEBKIT_SSH_DROPIN")" ;;
            2) debkit_verif_add ssh aviso "$(t amb.dropin_apos_match "$DEBKIT_ARQ_SSHD_CONFIG" "$DEBKIT_SSH_DROPIN")" ;;
            *) debkit_verif_add ssh aviso "$(t amb.dropin_falta "$DEBKIT_ARQ_SSHD_CONFIG" "$DEBKIT_SSH_DROPIN")" ;;
        esac
        if debkit_ssh_protecao_ativa; then
            DEBKIT_SSH_PROTEGIDO=1
            debkit_verif_add ssh ok "$(t amb.ssh_protecao_ativa "$DEBKIT_GRUPO_USUARIOS")"
        elif [ "$DEBKIT_SSH_DROPIN_OK" -eq 1 ]; then
            debkit_verif_add ssh info "$(t amb.ssh_protecao_inativa)"
        fi
        senha_ssh=$(sshd -T 2>/dev/null | awk '$1 == "passwordauthentication" {print $2}')
        [ "$senha_ssh" == "yes" ] && debkit_verif_add ssh info "$(t amb.ssh_senha)"
    fi

    # ── Firewall ──
    if debkit_fw_ufw_ativo; then
        DEBKIT_FW_TIPO="ufw"
    elif debkit_fw_firewalld_ativo; then
        DEBKIT_FW_TIPO="firewalld"
    fi
    case "$DEBKIT_FW_TIPO" in
        ufw|firewalld)
            if "debkit_fw_${DEBKIT_FW_TIPO}_libera"; then
                DEBKIT_FW_LIBERA=1
                debkit_verif_add firewall ok "$(t amb.fw_libera "$DEBKIT_FW_TIPO" "$DEBKIT_FW_PORTA")"
            else
                debkit_verif_add firewall aviso "$(t amb.fw_bloqueia "$DEBKIT_FW_TIPO" "$DEBKIT_FW_PORTA")"
            fi ;;
        *)
            if debkit_fw_regras_cruas; then
                debkit_verif_add firewall aviso "$(t amb.fw_cru "$DEBKIT_FW_PORTA")"
            else
                debkit_verif_add firewall ok "$(t amb.fw_nenhum)"
            fi ;;
    esac

    [ "$DEBKIT_BLOQUEIOS" -eq 0 ]
}

# Mostra o resultado da última verificação, por grupo
debkit_mostrar_ambiente() {
    local grupo item g estado texto icone cor
    for grupo in sistema deps samba ssh firewall dev; do
        echo ""
        printf '  %s%s%s\n' "$C_NEGRITO" "$(t "amb.grupo_$grupo")" "$C_RESET"
        for item in "${DEBKIT_VERIF[@]}"; do
            IFS=$'\t' read -r g estado texto <<< "$item"
            [ "$g" == "$grupo" ] || continue
            case "$estado" in
                ok)    icone="✔"; cor="$C_VERDE" ;;
                falta) icone="✘"; cor="$C_VERMELHO" ;;
                aviso) icone="!"; cor="$C_AMARELO" ;;
                info)  icone="·"; cor="$C_CIANO" ;;
                *)     icone="–"; cor="$C_CINZA" ;;
            esac
            printf '    %s%s%s %s\n' "$cor" "$icone" "$C_RESET" "$texto"
        done
    done
    echo ""
    if [ "$DEBKIT_BLOQUEIOS" -eq 0 ]; then
        msg_ok "$(t amb.resumo_ok)"
    else
        msg_erro "$(t amb.resumo_falta "$DEBKIT_BLOQUEIOS")"
        if [ ${#DEBKIT_PACOTES_FALTANDO[@]} -gt 0 ]; then
            msg_info "$(t amb.pacotes "${DEBKIT_PACOTES_FALTANDO[*]}")"
        fi
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# 7. PREPARAÇÃO DO AMBIENTE
# ════════════════════════════════════════════════════════════════════════════
# Resolve o que a detecção encontrou: instala pacotes (Debian), liga o
# Samba, cria a estrutura do debkit e o "include" no smb.conf. Sempre com
# plano mostrado antes e UMA confirmação. Se um passo falhar, desfaz o que
# é do debkit (arquivos, pastas, grupo, smb.conf); pacotes instalados e o
# serviço do Samba ligado NÃO são desfeitos (desinstalar no meio de uma
# falha arriscaria quebrar mais do que consertar) - e isso é informado.

DEBKIT_APT="${DEBKIT_APT:-apt-get}"    # variável para os testes poderem simular

# Ordem das chaves no debkit.conf gerado
DEBKIT_CONF_ORDEM=(IDIOMA SENHA_MIN GRUPO_USUARIOS PREFIXO_GRUPO SMB_CONF SHARES_CONF SSH_DROPIN LOG BACKUP_DIR BACKUP_MANTER TRAVA)

# ── Backups ─────────────────────────────────────────────────────────────────
# Copia o arquivo para DEBKIT_BACKUP_DIR (pasta 700, cópia 600) com data/hora
# e mantém só as DEBKIT_BACKUP_MANTER cópias mais recentes daquele arquivo.
# Imprime o caminho do backup.
debkit_backup() {
    local arquivo="$1" nome destino
    if [ ! -f "$arquivo" ]; then
        msg_erro "$(t prep.backup_sem_arquivo "$arquivo")"
        return 1
    fi
    if ! ( umask 077; mkdir -p -- "$DEBKIT_BACKUP_DIR" ) || ! chmod 700 -- "$DEBKIT_BACKUP_DIR"; then
        msg_erro "$(t prep.backup_falhou "$arquivo")"
        return 1
    fi
    nome=$(basename -- "$arquivo")
    destino="$DEBKIT_BACKUP_DIR/$nome.$(date +%Y%m%d-%H%M%S-%N)"
    if ! cp -p -- "$arquivo" "$destino" || ! chmod 600 -- "$destino"; then
        rm -f -- "$destino"
        msg_erro "$(t prep.backup_falhou "$arquivo")"
        return 1
    fi
    debkit_backup_limpar "$nome"
    echo "$destino"
}

# Apaga as cópias mais antigas de <nome>, mantendo DEBKIT_BACKUP_MANTER
debkit_backup_limpar() {
    local nome="$1"
    find "$DEBKIT_BACKUP_DIR" -maxdepth 1 -type f -name "$nome.[0-9]*" -printf '%f\n' 2>/dev/null \
        | sort | head -n -"$DEBKIT_BACKUP_MANTER" \
        | while IFS= read -r velho; do rm -f -- "$DEBKIT_BACKUP_DIR/$velho"; done
}

# ── Peças da estrutura do debkit ───────────────────────────────────────────────
debkit_dir_conf() { dirname -- "$DEBKIT_CONF_ARQUIVO"; }

# A linha "include = <SHARES_CONF>" já está no smb.conf?
debkit_include_presente() {
    local caminho_er="${DEBKIT_SHARES_CONF//./\\.}"
    [ -f "$DEBKIT_SMB_CONF" ] && grep -qiE "^[[:space:]]*include[[:space:]]*=[[:space:]]*${caminho_er}[[:space:]]*$" "$DEBKIT_SMB_CONF"
}

# Recarrega o Samba (só se o serviço estiver ativo)
debkit_samba_recarregar() {
    [ -n "$DEBKIT_SVC_SAMBA" ] || DEBKIT_SVC_SAMBA=$(debkit_descobrir_servico smbd smb) || return 0
    debkit_servico_ativo "$DEBKIT_SVC_SAMBA" || return 0
    systemctl reload "$DEBKIT_SVC_SAMBA.service"
}

# ── Plano ───────────────────────────────────────────────────────────────────
# DEBKIT_PLANO: ids das ações, na ordem de execução.
# DEBKIT_PLANO_IMPOSSIVEL: motivo, se algo não pode ser resolvido pelo debkit.
# Usar depois de debkit_verificar_ambiente.
debkit_montar_plano() {
    DEBKIT_PLANO=(); DEBKIT_PLANO_IMPOSSIVEL=""

    if [ "$DEBKIT_BLOQ_MANUAL" -gt 0 ]; then
        DEBKIT_PLANO_IMPOSSIVEL="$(t prep.impossivel_manual)"
        return 0
    fi
    if [ ${#DEBKIT_PACOTES_FALTANDO[@]} -gt 0 ]; then
        if debkit_familia_debian && debkit_tem_comando "$DEBKIT_APT"; then
            DEBKIT_PLANO+=(pacotes)
        else
            DEBKIT_PLANO_IMPOSSIVEL="$(t prep.impossivel_pacotes "${DEBKIT_PACOTES_FALTANDO[*]}")"
            return 0
        fi
    fi
    # Serviço: se o Samba vai ser instalado agora, o estado só se sabe depois
    if [[ " ${DEBKIT_PLANO[*]} " == *" pacotes "* ]] || [ -z "$DEBKIT_SVC_SAMBA" ] \
       || ! debkit_servico_ativo "$DEBKIT_SVC_SAMBA" || ! debkit_servico_habilitado "$DEBKIT_SVC_SAMBA"; then
        DEBKIT_PLANO+=(samba_servico)
    fi
    [ -d "$(debkit_dir_conf)" ]      || DEBKIT_PLANO+=(dir_conf)
    [ -f "$DEBKIT_CONF_ARQUIVO" ]    || DEBKIT_PLANO+=(conf)
    [ -d "$DEBKIT_BACKUP_DIR" ]      || DEBKIT_PLANO+=(dir_backup)
    [ -f "$DEBKIT_LOG" ]             || DEBKIT_PLANO+=(log)
    getent group "$DEBKIT_GRUPO_USUARIOS" >/dev/null 2>&1 || DEBKIT_PLANO+=(grupo)
    [ -f "$DEBKIT_SHARES_CONF" ]     || DEBKIT_PLANO+=(shares_conf)
    debkit_include_presente          || DEBKIT_PLANO+=(include)
    # Proteção SSH: só se há servidor SSH, o sshd_config aceita o arquivo do
    # debkit e a proteção ainda não está efetiva
    if [ "$DEBKIT_TEM_SSH" -eq 1 ] && [ "$DEBKIT_SSH_DROPIN_OK" -eq 1 ] && [ "$DEBKIT_SSH_PROTEGIDO" -eq 0 ]; then
        DEBKIT_PLANO+=(ssh_protecao)
    fi
    # Firewall: ufw/firewalld ativo que ainda não libera o Samba
    if [ -n "$DEBKIT_FW_TIPO" ] && [ "$DEBKIT_FW_LIBERA" -eq 0 ]; then
        DEBKIT_PLANO+=(firewall)
    fi
    return 0
}

# Descrição de uma ação do plano (para mostrar antes de confirmar)
debkit_descrever_acao() {
    case "$1" in
        pacotes)       t prep.d_pacotes "${DEBKIT_PACOTES_FALTANDO[*]}" ;;
        samba_servico) t prep.d_samba_servico ;;
        dir_conf)      t prep.d_dir_conf "$(debkit_dir_conf)" ;;
        conf)          t prep.d_conf "$DEBKIT_CONF_ARQUIVO" ;;
        dir_backup)    t prep.d_dir_backup "$DEBKIT_BACKUP_DIR" ;;
        log)           t prep.d_log "$DEBKIT_LOG" ;;
        grupo)         t prep.d_grupo "$DEBKIT_GRUPO_USUARIOS" ;;
        shares_conf)   t prep.d_shares_conf "$DEBKIT_SHARES_CONF" ;;
        include)       t prep.d_include "$DEBKIT_SMB_CONF" "$DEBKIT_SHARES_CONF" ;;
        ssh_protecao)  t prep.d_ssh_protecao "$DEBKIT_SSH_DROPIN" "$DEBKIT_GRUPO_USUARIOS" ;;
        firewall)      t prep.d_firewall "$DEBKIT_FW_PORTA" "$DEBKIT_FW_TIPO" "$(debkit_redes_locais | paste -sd, - | sed 's/,/, /g')" ;;
    esac
}

debkit_mostrar_plano() {
    local acao
    echo ""
    printf '  %s%s%s\n' "$C_NEGRITO" "$(t prep.titulo_plano)" "$C_RESET"
    for acao in "${DEBKIT_PLANO[@]}"; do
        printf '    • %s\n' "$(debkit_descrever_acao "$acao")"
    done
    echo ""
}

# ── Ações (cada uma retorna 0 se deu certo, conferindo o resultado) ─────────
debkit_acao_pacotes() {
    local registro cmd dep tipo pacote
    registro=$(debkit_temp) || return 1
    msg_info "$(t prep.apt_atualizando)"
    if ! DEBIAN_FRONTEND=noninteractive "$DEBKIT_APT" -o DPkg::Lock::Timeout=120 update >"$registro" 2>&1; then
        msg_aviso "$(t prep.apt_update_falhou)"
    fi
    msg_info "$(t prep.apt_instalando "${DEBKIT_PACOTES_FALTANDO[*]}")"
    # confdef/confold: se existir configuração antiga (ex: smb.conf de uma
    # instalação anterior), mantém a existente em vez de parar perguntando
    if ! DEBIAN_FRONTEND=noninteractive "$DEBKIT_APT" -o DPkg::Lock::Timeout=120 \
            -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
            install -y "${DEBKIT_PACOTES_FALTANDO[@]}" >>"$registro" 2>&1; then
        msg_erro "$(t prep.apt_falhou)"
        tail -n 8 "$registro" | sed 's/^/     /' >&2
        return 1
    fi
    # Confere: todos os comandos essenciais agora existem?
    for dep in "${DEBKIT_DEPENDENCIAS[@]}"; do
        IFS='|' read -r cmd tipo pacote <<< "$dep"
        [ "$tipo" == "essencial" ] || continue
        if ! debkit_tem_comando "$cmd"; then
            msg_erro "$(t prep.apt_conferencia "$cmd" "$pacote")"
            return 1
        fi
    done
    DEBKIT_PACOTES_INSTALADOS="${DEBKIT_PACOTES_FALTANDO[*]}"
}

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
    msg_erro "$(t prep.servico_falhou "$DEBKIT_SVC_SAMBA")"
    return 1
}

debkit_acao_dir_conf()   { ( umask 022; mkdir -p -- "$(debkit_dir_conf)" ) && chmod 755 -- "$(debkit_dir_conf)"; }
debkit_acao_dir_backup() { ( umask 077; mkdir -p -- "$DEBKIT_BACKUP_DIR" ) && chmod 700 -- "$DEBKIT_BACKUP_DIR"; }
debkit_acao_log()        { ( umask 027; : >> "$DEBKIT_LOG" ) && chmod 640 -- "$DEBKIT_LOG"; }
debkit_acao_grupo()      { groupadd --system -- "$DEBKIT_GRUPO_USUARIOS" && getent group "$DEBKIT_GRUPO_USUARIOS" >/dev/null; }

debkit_acao_conf() {
    local chave var
    {
        echo "# /etc/debkit/debkit.conf - gerado pelo debkit $DEBKIT_VERSAO em $(date '+%Y-%m-%d %H:%M')"
        echo "# Descrição de cada opção: debkit.conf.exemplo (no repositório do debkit)."
        echo "# Formato CHAVE=valor; o arquivo é lido, nunca executado."
        echo ""
        for chave in "${DEBKIT_CONF_ORDEM[@]}"; do
            var="DEBKIT_$chave"
            printf '%s=%s\n' "$chave" "${!var}"
        done
    } > "$DEBKIT_CONF_ARQUIVO" && chmod 644 -- "$DEBKIT_CONF_ARQUIVO" && chown 0:0 -- "$DEBKIT_CONF_ARQUIVO" \
        && debkit_conf_carregar "$DEBKIT_CONF_ARQUIVO"
}

debkit_acao_shares_conf() {
    {
        echo "# Compartilhamentos gerenciados pelo debkit (Gerenciador Samba)."
        echo "# NÃO edite à mão: use o debkit. Este arquivo é incluído pelo"
        echo "# $DEBKIT_SMB_CONF (linha \"include = $DEBKIT_SHARES_CONF\")."
    } > "$DEBKIT_SHARES_CONF" && chmod 644 -- "$DEBKIT_SHARES_CONF"
}

debkit_acao_include() {
    local backup quebra=""
    if [ ! -f "$DEBKIT_SMB_CONF" ]; then
        msg_erro "$(t amb.smbconf_ausente "$DEBKIT_SMB_CONF")"
        return 1
    fi
    backup=$(debkit_backup "$DEBKIT_SMB_CONF") || return 1
    DEBKIT_BACKUP_SMBCONF="$backup"
    # Se o arquivo não termina com quebra de linha, acrescenta uma antes
    [ -n "$(tail -c 1 -- "$DEBKIT_SMB_CONF")" ] && quebra=$'\n'
    {
        printf '%s' "$quebra"
        echo ""
        echo "# debkit - Gerenciador Samba: compartilhamentos do debkit (não remova esta linha)"
        echo "include = $DEBKIT_SHARES_CONF"
    } >> "$DEBKIT_SMB_CONF" || return 1
    if ! testparm -s "$DEBKIT_SMB_CONF" >/dev/null 2>&1; then
        msg_erro "$(t prep.include_testparm)"
        return 1
    fi
    debkit_include_presente || return 1
    if ! debkit_samba_recarregar; then
        msg_erro "$(t prep.recarregar_falhou)"
        return 1
    fi
}

# ── Proteção SSH ────────────────────────────────────────────────────────────
DEBKIT_SSH_MARCA="# debkit - Gerenciador Samba: bloqueio SSH dos usuários do servidor de arquivos"

# Recarrega o SSH, só se o serviço estiver ativo. Com ativação por socket
# (ou serviço parado) não é preciso: cada nova conexão/início lê a config.
debkit_ssh_recarregar() {
    [ -n "$DEBKIT_SVC_SSH" ] || DEBKIT_SVC_SSH=$(debkit_descobrir_servico ssh sshd) || return 0
    debkit_servico_ativo "$DEBKIT_SVC_SSH" || return 0
    systemctl reload "$DEBKIT_SVC_SSH.service"
}

# Cria o arquivo próprio do debkit com "DenyGroups <grupo>", valida a
# configuração ANTES de recarregar (recarregar o SSH com config inválida pode
# derrubar o serviço), recarrega e confere no sshd -T que vale para todos.
debkit_acao_ssh_protecao() {
    local quem erros
    # O desfazer só mexe no que esta operação realmente fez
    DEBKIT_BACKUP_SSHDROPIN=""; DEBKIT_SSH_ESCRITO=0; DEBKIT_SSH_RECARREGADO=0

    # Nunca trancar fora quem está rodando o debkit (via sudo ou root direto)
    quem="${SUDO_USER:-root}"
    if id -nG "$quem" 2>/dev/null | tr ' ' '\n' | grep -qxF "$DEBKIT_GRUPO_USUARIOS"; then
        msg_erro "$(t prep.ssh_admin_no_grupo "$quem" "$DEBKIT_GRUPO_USUARIOS")"
        return 1
    fi
    # Não sobrescreve arquivo que não é do debkit
    if [ -f "$DEBKIT_SSH_DROPIN" ]; then
        if ! grep -qxF "$DEBKIT_SSH_MARCA" "$DEBKIT_SSH_DROPIN"; then
            msg_erro "$(t prep.ssh_arquivo_alheio "$DEBKIT_SSH_DROPIN")"
            return 1
        fi
        DEBKIT_BACKUP_SSHDROPIN=$(debkit_backup "$DEBKIT_SSH_DROPIN") || return 1
    fi

    {
        echo "$DEBKIT_SSH_MARCA"
        echo "# Gerado pelo debkit em $(date '+%Y-%m-%d %H:%M'). NÃO edite à mão: use o debkit."
        echo "DenyGroups $DEBKIT_GRUPO_USUARIOS"
    } > "$DEBKIT_SSH_DROPIN"
    DEBKIT_SSH_ESCRITO=1
    chmod 644 -- "$DEBKIT_SSH_DROPIN" || return 1

    if ! erros=$(sshd -t 2>&1); then
        msg_erro "$(t prep.ssh_invalido)"
        printf '%s\n' "$erros" | head -5 | sed 's/^/     /' >&2
        return 1
    fi
    DEBKIT_SSH_RECARREGADO=1
    if ! debkit_ssh_recarregar; then
        msg_erro "$(t prep.ssh_recarregar "$DEBKIT_SVC_SSH")"
        return 1
    fi
    if ! debkit_ssh_protecao_ativa; then
        msg_erro "$(t prep.ssh_nao_confirmada)"
        return 1
    fi
}

# Desfaz SÓ o que a operação fez: se escreveu o arquivo, volta o anterior
# (backup) ou o remove; se recarregou o SSH, recarrega de novo - e só com a
# configuração válida. Falha antes de escrever = nada a desfazer.
debkit_ssh_desfazer() {
    [ "${DEBKIT_SSH_ESCRITO:-0}" -eq 1 ] || return 0
    if [ -n "${DEBKIT_BACKUP_SSHDROPIN:-}" ]; then
        cp -p -- "$DEBKIT_BACKUP_SSHDROPIN" "$DEBKIT_SSH_DROPIN"
    elif [ -f "$DEBKIT_SSH_DROPIN" ] && grep -qxF "$DEBKIT_SSH_MARCA" "$DEBKIT_SSH_DROPIN"; then
        rm -f -- "$DEBKIT_SSH_DROPIN"
    fi
    if [ "${DEBKIT_SSH_RECARREGADO:-0}" -eq 1 ] && sshd -t >/dev/null 2>&1; then
        debkit_ssh_recarregar
    fi
}

# Remove a proteção (usada pela desinstalação). Retorna 0 se ao final o
# grupo não está mais em denygroups.
debkit_ssh_remover_protecao() {
    DEBKIT_BACKUP_SSHDROPIN=""
    [ -f "$DEBKIT_SSH_DROPIN" ] || return 0
    if ! grep -qxF "$DEBKIT_SSH_MARCA" "$DEBKIT_SSH_DROPIN"; then
        msg_erro "$(t prep.ssh_arquivo_alheio "$DEBKIT_SSH_DROPIN")"
        return 1
    fi
    debkit_backup "$DEBKIT_SSH_DROPIN" >/dev/null || return 1
    # Remover = desfazer um arquivo "escrito e em vigor"
    DEBKIT_SSH_ESCRITO=1; DEBKIT_SSH_RECARREGADO=1
    debkit_ssh_desfazer
    ! debkit_ssh_protecao_ativa
}

# ── Firewall ────────────────────────────────────────────────────────────────
# Libera a porta 445/tcp no firewall ativo (DEBKIT_FW_TIPO), uma regra por rede
# local, com comentário "debkit: Samba". Guarda as redes liberadas em
# DEBKIT_FW_CRIADAS para o desfazer remover exatamente essas regras.
debkit_acao_firewall() {
    local rede zona
    local -a redes=()
    DEBKIT_FW_CRIADAS=()
    mapfile -t redes < <(debkit_redes_locais)
    if [ ${#redes[@]} -eq 0 ]; then
        msg_erro "$(t prep.fw_sem_redes)"
        return 1
    fi
    case "$DEBKIT_FW_TIPO" in
        ufw)
            for rede in "${redes[@]}"; do
                if ! debkit_ufw allow from "$rede" to any port "$DEBKIT_FW_PORTA" proto tcp comment "$DEBKIT_FW_COMENTARIO" >/dev/null 2>&1; then
                    msg_erro "$(t prep.fw_falhou "ufw" "$rede")"
                    return 1
                fi
                DEBKIT_FW_CRIADAS+=("$rede")
            done ;;
        firewalld)
            zona=$(debkit_fw_firewalld_zona) || { msg_erro "$(t prep.fw_falhou "firewalld" "?")"; return 1; }
            for rede in "${redes[@]}"; do
                if ! firewall-cmd --permanent --zone="$zona" --add-rich-rule="$(debkit_fw_regra_rich "$rede")" >/dev/null 2>&1; then
                    msg_erro "$(t prep.fw_falhou "firewalld" "$rede")"
                    return 1
                fi
                DEBKIT_FW_CRIADAS+=("$rede")
            done
            firewall-cmd --reload >/dev/null 2>&1 || { msg_erro "$(t prep.fw_falhou "firewalld" "reload")"; return 1; } ;;
        *)
            return 1 ;;
    esac
    if ! "debkit_fw_${DEBKIT_FW_TIPO}_libera"; then
        msg_erro "$(t prep.fw_nao_confirmada)"
        return 1
    fi
}

# Regra "rich" do firewalld para uma rede
debkit_fw_regra_rich() {
    printf 'rule family="ipv4" source address="%s" port port="%s" protocol="tcp" accept' "$1" "$DEBKIT_FW_PORTA"
}

# Remove só as regras que a ação criou
debkit_fw_desfazer() {
    local rede zona
    case "$DEBKIT_FW_TIPO" in
        ufw)
            for rede in "${DEBKIT_FW_CRIADAS[@]}"; do
                debkit_ufw delete allow from "$rede" to any port "$DEBKIT_FW_PORTA" proto tcp >/dev/null 2>&1
            done ;;
        firewalld)
            zona=$(debkit_fw_firewalld_zona) || return 0
            for rede in "${DEBKIT_FW_CRIADAS[@]}"; do
                firewall-cmd --permanent --zone="$zona" --remove-rich-rule="$(debkit_fw_regra_rich "$rede")" >/dev/null 2>&1
            done
            [ ${#DEBKIT_FW_CRIADAS[@]} -gt 0 ] && firewall-cmd --reload >/dev/null 2>&1 ;;
    esac
    DEBKIT_FW_CRIADAS=()
    return 0
}

# ── Desfazer (só o que é do debkit) ────────────────────────────────────────────
debkit_desfazer() {
    case "$1" in
        dir_conf)    rmdir -- "$(debkit_dir_conf)" 2>/dev/null ;;
        conf)        rm -f -- "$DEBKIT_CONF_ARQUIVO" ;;
        dir_backup)  rmdir -- "$DEBKIT_BACKUP_DIR" 2>/dev/null ;;   # só se vazia
        grupo)       getent group "$DEBKIT_GRUPO_USUARIOS" | awk -F: '$4 != "" {exit 1}' \
                         && groupdel -- "$DEBKIT_GRUPO_USUARIOS" ;;
        shares_conf) [ "$(grep -cv '^#' "$DEBKIT_SHARES_CONF" 2>/dev/null)" == "0" ] && rm -f -- "$DEBKIT_SHARES_CONF" ;;
        include)     if [ -n "${DEBKIT_BACKUP_SMBCONF:-}" ]; then
                         cp -p -- "$DEBKIT_BACKUP_SMBCONF" "$DEBKIT_SMB_CONF" && debkit_samba_recarregar
                     fi ;;
        ssh_protecao) debkit_ssh_desfazer ;;
        firewall)    debkit_fw_desfazer ;;
        *)           return 0 ;;   # pacotes, serviço e log não são desfeitos
    esac
}

# ── Execução do plano ───────────────────────────────────────────────────────
# Executa DEBKIT_PLANO na ordem. Se uma ação falhar, desfaz as anteriores (só o
# que é do debkit), na ordem inversa, e informa o que ficou.
debkit_executar_plano() {
    local acao i feito
    local -a feitos=()
    DEBKIT_PACOTES_INSTALADOS=""; DEBKIT_BACKUP_SMBCONF=""
    for acao in "${DEBKIT_PLANO[@]}"; do
        if "debkit_acao_$acao"; then
            feitos+=("$acao")
            msg_ok "$(debkit_descrever_acao "$acao")"
            debkit_auditar preparar "acao=$acao resultado=ok"
        else
            msg_erro "$(t prep.falhou "$(debkit_descrever_acao "$acao")")"
            debkit_auditar preparar "acao=$acao resultado=falha"
            # A própria ação pode ter alterado algo antes de falhar (ex: o
            # include grava a linha e só depois valida): desfaz ela também
            debkit_desfazer "$acao"
            if [ ${#feitos[@]} -gt 0 ]; then
                msg_info "$(t prep.desfazendo)"
                for (( i=${#feitos[@]}-1; i>=0; i-- )); do
                    feito="${feitos[$i]}"
                    debkit_desfazer "$feito"
                    debkit_auditar preparar "acao=$feito resultado=desfeito"
                done
                [ -n "$DEBKIT_PACOTES_INSTALADOS" ] && msg_aviso "$(t prep.mantidos_pacotes "$DEBKIT_PACOTES_INSTALADOS")"
                [[ " ${feitos[*]} " == *" samba_servico "* ]] && msg_aviso "$(t prep.mantido_servico)"
            fi
            return 1
        fi
    done
    return 0
}

# Fluxo completo: verifica, mostra, oferece e prepara.
# Retorna 0 se ao final o ambiente está pronto.
debkit_preparar() {
    local plano_txt
    debkit_verificar_ambiente
    debkit_montar_plano
    if [ -n "$DEBKIT_PLANO_IMPOSSIVEL" ]; then
        debkit_mostrar_ambiente
        msg_erro "$DEBKIT_PLANO_IMPOSSIVEL"
        return 1
    fi
    if [ ${#DEBKIT_PLANO[@]} -eq 0 ]; then
        msg_ok "$(t prep.nada_a_fazer)"
        return 0
    fi
    plano_txt=$(IFS=,; echo "${DEBKIT_PLANO[*]}")
    debkit_mostrar_plano
    if ! confirmar "$(t prep.pergunta)"; then
        debkit_auditar preparar "plano=$plano_txt resposta=nao"
        msg_aviso "$(t prep.recusado)"
        return 1
    fi
    debkit_auditar preparar "plano=$plano_txt resposta=sim"
    if debkit_executar_plano; then
        echo ""
        msg_ok "$(t prep.concluido)"
        return 0
    fi
    return 1
}

# ════════════════════════════════════════════════════════════════════════════
# 8. FUNÇÕES
# ════════════════════════════════════════════════════════════════════════════
# (adicionadas nas próximas etapas)

# ════════════════════════════════════════════════════════════════════════════
# 9. MENUS
# ════════════════════════════════════════════════════════════════════════════

# Tela "Ambiente": relatório completo e, se houver o que preparar, oferece
menu_ambiente() {
    titulo "$(t amb.titulo)"
    debkit_verificar_ambiente
    debkit_mostrar_ambiente
    debkit_montar_plano
    if [ -z "$DEBKIT_PLANO_IMPOSSIVEL" ] && [ ${#DEBKIT_PLANO[@]} -gt 0 ]; then
        debkit_preparar
    fi
    pausar
}

# Assistente da primeira execução (e de quando algo "quebrou"): ao abrir o
# menu, se houver o que preparar, mostra o plano e pergunta. Retorna 1 se
# o debkit não puder funcionar (o menu não deve abrir).
debkit_assistente() {
    debkit_verificar_ambiente
    debkit_montar_plano
    if [ -n "$DEBKIT_PLANO_IMPOSSIVEL" ]; then
        titulo "$(t amb.titulo)"
        debkit_mostrar_ambiente
        msg_erro "$DEBKIT_PLANO_IMPOSSIVEL"
        return 1
    fi
    [ ${#DEBKIT_PLANO[@]} -eq 0 ] && return 0
    titulo "$(t prep.titulo_assistente)"
    msg_info "$(t prep.intro)"
    debkit_preparar
    pausar
    return 0
}

menu_principal() {
    local opcao
    while true; do
        titulo "$(t geral.titulo)  ${C_CINZA}v${DEBKIT_VERSAO}${C_RESET}"
        echo "  $(t geral.em_construcao)"
        echo ""
        echo "  9) $(t menu.ambiente)"
        echo "  0) $(t geral.sair)"
        echo ""
        ler_opcao opcao
        case "$opcao" in
            "") continue ;;
            9) menu_ambiente ;;
            0) [ -t 1 ] && clear; return 0 ;;
            *) msg_erro "$(t geral.opcao_invalida "$opcao")"; pausar ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════════════════════
# 10. LINHA DE COMANDO E INÍCIO
# ════════════════════════════════════════════════════════════════════════════

# Carrega a configuração mostrando avisos/erros. Retorna 1 se inválida.
debkit_iniciar_conf() {
    if ! debkit_conf_carregar "$DEBKIT_CONF_ARQUIVO"; then
        msg_erro "$(t erro.conf "$DEBKIT_CONF_ARQUIVO")"
        printf '%s\n' "$DEBKIT_CONF_ERROS" | sed 's/^/     /' >&2
        return 1
    fi
    if [ -n "$DEBKIT_CONF_AVISOS" ]; then
        msg_aviso "$(t aviso.conf "$DEBKIT_CONF_ARQUIVO")"
        printf '%s\n' "$DEBKIT_CONF_AVISOS" | sed 's/^/     /'
    fi
}

main() {
    # Idioma por variável de ambiente tem prioridade (útil em testes)
    local idioma_env="${DEBKIT_IDIOMA:-}"

    # Ajuda e versão funcionam mesmo com a configuração com erro (é
    # justamente quando o administrador mais precisa delas)
    case "${1:-}" in
        -h|--ajuda|--help|-v|--versao|--version)
            debkit_conf_carregar "$DEBKIT_CONF_ARQUIVO" || debkit_conf_padroes
            if [ -n "$idioma_env" ] && debkit_conf_valor_valido idioma "$idioma_env"; then
                DEBKIT_IDIOMA="$idioma_env"
            fi
            case "$1" in
                -h|--ajuda|--help) t ajuda.texto "$DEBKIT_CONF_ARQUIVO"; echo ;;
                *)                 t geral.versao "$DEBKIT_VERSAO"; echo ;;
            esac
            exit 0 ;;
    esac

    debkit_iniciar_conf || exit 1
    if [ -n "$idioma_env" ] && debkit_conf_valor_valido idioma "$idioma_env"; then
        DEBKIT_IDIOMA="$idioma_env"
    fi

    case "${1:-}" in
        ""|--verificar|--check|--preparar|--setup) ;;
        *) msg_erro "$(t erro.uso "$1")"; exit 2 ;;
    esac

    if [ "$EUID" -ne 0 ]; then
        msg_erro "$(t erro.root)"
        exit 1
    fi

    # Verificação do ambiente (somente leitura: sem trava nem auditoria)
    if [ "${1:-}" == "--verificar" ] || [ "${1:-}" == "--check" ]; then
        debkit_verificar_ambiente; local rc=$?
        debkit_mostrar_ambiente
        exit "$rc"
    fi

    trap debkit_ao_sair EXIT
    trap 'echo; msg_aviso "$(t geral.interrompido)"; DEBKIT_MOTIVO_SAIDA="interrompida"; exit 130' INT TERM

    debkit_travar || exit 1
    debkit_auditar sessao_inicio "v$DEBKIT_VERSAO${1:+ $1}"
    DEBKIT_SESSAO_ATIVA=1

    # Preparação pela linha de comando
    if [ -n "${1:-}" ]; then
        debkit_preparar
        exit $?
    fi

    debkit_assistente || exit 1
    menu_principal
}

# Só executa quando chamado diretamente; com "source" apenas carrega
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
