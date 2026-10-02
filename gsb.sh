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
#   gsb --verificar    verifica o ambiente (somente leitura; precisa ser root)
#   gsb --preparar     verifica e prepara o ambiente (pede confirmação)
#   source gsb.sh      carrega as funções sem executar nada (para testes)
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
    [menu.ambiente]="Ambiente: verificar e preparar"
    [amb.titulo]="Ambiente do servidor"
    [amb.grupo_sistema]="Sistema"
    [amb.grupo_deps]="Dependências essenciais"
    [amb.grupo_samba]="Samba"
    [amb.grupo_ssh]="SSH"
    [amb.grupo_dev]="Desenvolvimento (opcional)"
    [amb.so_desconhecido]="Sistema não identificado (%s ausente ou ilegível)"
    [amb.so_nao_debian]="Distribuição fora da família Debian: não testada; instalação automática indisponível"
    [amb.systemd_ok]="systemd em execução"
    [amb.systemd_falta]="systemd não está em execução (ex: container): o gsb precisa dele para gerenciar serviços"
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
    [amb.papel_dc]="Modo: %s - controlador de domínio NÃO é suportado pelo gsb"
    [amb.papel_outro]="Modo: %s (não testado com o gsb)"
    [amb.backend_ok]="Base de senhas: %s"
    [amb.backend_outro]="Base de senhas: %s - não suportada (o gsb usa tdbsam)"
    [amb.ssh_ausente]="Servidor SSH não instalado: proteção SSH não necessária"
    [amb.dropin_ok]="%s inclui %s (o gsb pode usar arquivo próprio)"
    [amb.dropin_falta]="%s não inclui %s: a proteção SSH automática não poderá ser aplicada"
    [amb.ssh_senha]="Login por senha ligado no SSH: a proteção dos usuários do gsb é importante"
    [amb.dropin_apos_match]="%s inclui %s só DEPOIS de um bloco Match: a proteção não valeria para todos (mova o Include para antes do primeiro Match)"
    [amb.ssh_protecao_ativa]="Proteção SSH do gsb ativa (grupo %s recusado no SSH)"
    [amb.ssh_protecao_inativa]="Proteção SSH do gsb ainda não aplicada"
    [amb.dev_ok]="%s instalado"
    [amb.dev_falta]="%s não instalado (só para desenvolvimento/testes)"
    [amb.resumo_ok]="Ambiente pronto para o gsb."
    [amb.resumo_falta]="%d item(ns) essencial(is) impedem o gsb de funcionar."
    [amb.pacotes]="Pacotes necessários: %s"
    [prep.titulo_assistente]="Preparação do servidor para o gsb"
    [prep.intro]="O gsb verificou este servidor e precisa preparar algumas coisas antes do primeiro uso."
    [prep.titulo_plano]="O gsb vai:"
    [prep.d_pacotes]="Instalar os pacotes: %s"
    [prep.d_samba_servico]="Deixar o serviço do Samba ativo e iniciando junto com o sistema"
    [prep.d_dir_conf]="Criar a pasta de configuração %s"
    [prep.d_conf]="Criar a configuração %s (com os valores padrão)"
    [prep.d_dir_backup]="Criar a pasta de backups %s (acesso só do root)"
    [prep.d_log]="Criar o log de auditoria %s"
    [prep.d_grupo]="Criar o grupo de sistema %s (usuários do gsb)"
    [prep.d_shares_conf]="Criar o arquivo de compartilhamentos do gsb %s"
    [prep.d_include]="Incluir no %s a linha \"include = %s\" (com backup e validação)"
    [prep.pergunta]="Preparar agora?"
    [prep.recusado]="Nada foi alterado. O gsb vai funcionar de forma limitada até o ambiente ser preparado (menu 9)."
    [prep.nada_a_fazer]="O ambiente já está preparado. Nada a fazer."
    [prep.concluido]="Ambiente preparado com sucesso."
    [prep.falhou]="Falhou: %s"
    [prep.desfazendo]="Desfazendo o que o gsb já tinha feito..."
    [prep.mantidos_pacotes]="Os pacotes instalados foram mantidos: %s"
    [prep.mantido_servico]="O serviço do Samba foi mantido ligado."
    [prep.impossivel_manual]="Há itens que o gsb não pode resolver sozinho (marcados com ✘). Corrija-os e execute o gsb novamente."
    [prep.impossivel_pacotes]="Instalação automática indisponível neste sistema. Instale manualmente: %s"
    [prep.apt_atualizando]="Atualizando a lista de pacotes (apt-get update)..."
    [prep.apt_update_falhou]="Não foi possível atualizar a lista de pacotes; tentando instalar mesmo assim."
    [prep.apt_instalando]="Instalando: %s (pode levar alguns minutos)..."
    [prep.apt_falhou]="A instalação falhou (sem internet? repositórios com erro?). Últimas linhas:"
    [prep.apt_conferencia]="Depois da instalação, o comando %s ainda não existe (pacote %s)."
    [prep.servico_falhou]="Não foi possível ativar o serviço %s (veja: systemctl status %s)."
    [prep.include_testparm]="O smb.conf ficou inválido com a linha do gsb (testparm)."
    [prep.recarregar_falhou]="Não foi possível recarregar o Samba."
    [prep.backup_sem_arquivo]="Backup impossível: %s não existe."
    [prep.backup_falhou]="Não foi possível fazer o backup de %s."
    [prep.d_ssh_protecao]="Bloquear o SSH para os usuários do gsb (%s com \"DenyGroups %s\"), validar e recarregar o SSH sem derrubar ninguém"
    [prep.ssh_admin_no_grupo]="Você (%s) é membro de %s: aplicar a proteção trancaria você fora do SSH. Nada foi feito."
    [prep.ssh_arquivo_alheio]="%s já existe e não foi criado pelo gsb: o gsb não vai sobrescrevê-lo."
    [prep.ssh_invalido]="A configuração do SSH ficou inválida (sshd -t); o SSH NÃO foi recarregado:"
    [prep.ssh_recarregar]="Não foi possível recarregar o SSH (%s)."
    [prep.ssh_nao_confirmada]="A regra não apareceu na configuração em vigor do SSH (sshd -T)."
    [ajuda.texto]="Uso: gsb [opção]

  (sem opção)    abre o menu interativo (precisa ser root)
  --verificar    verifica o ambiente, sem alterar nada (precisa ser root)
  --preparar     verifica e prepara o ambiente (pede confirmação)
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
    [menu.ambiente]="Environment: check and set up"
    [amb.titulo]="Server environment"
    [amb.grupo_sistema]="System"
    [amb.grupo_deps]="Essential dependencies"
    [amb.grupo_samba]="Samba"
    [amb.grupo_ssh]="SSH"
    [amb.grupo_dev]="Development (optional)"
    [amb.so_desconhecido]="Unknown system (%s missing or unreadable)"
    [amb.so_nao_debian]="Distribution outside the Debian family: untested; automatic installation unavailable"
    [amb.systemd_ok]="systemd running"
    [amb.systemd_falta]="systemd is not running (e.g. container): gsb needs it to manage services"
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
    [amb.papel_dc]="Role: %s - domain controllers are NOT supported by gsb"
    [amb.papel_outro]="Role: %s (not tested with gsb)"
    [amb.backend_ok]="Password backend: %s"
    [amb.backend_outro]="Password backend: %s - not supported (gsb uses tdbsam)"
    [amb.ssh_ausente]="SSH server not installed: SSH protection not needed"
    [amb.dropin_ok]="%s includes %s (gsb can use its own file)"
    [amb.dropin_falta]="%s does not include %s: automatic SSH protection cannot be applied"
    [amb.ssh_senha]="SSH password login is enabled: protecting gsb users matters"
    [amb.dropin_apos_match]="%s includes %s only AFTER a Match block: the protection would not apply to everyone (move the Include before the first Match)"
    [amb.ssh_protecao_ativa]="gsb SSH protection active (group %s denied on SSH)"
    [amb.ssh_protecao_inativa]="gsb SSH protection not applied yet"
    [amb.dev_ok]="%s installed"
    [amb.dev_falta]="%s not installed (development/testing only)"
    [amb.resumo_ok]="Environment ready for gsb."
    [amb.resumo_falta]="%d essential item(s) prevent gsb from working."
    [amb.pacotes]="Required packages: %s"
    [prep.titulo_assistente]="Preparing the server for gsb"
    [prep.intro]="gsb checked this server and needs to prepare a few things before first use."
    [prep.titulo_plano]="gsb will:"
    [prep.d_pacotes]="Install the packages: %s"
    [prep.d_samba_servico]="Make the Samba service active and start at boot"
    [prep.d_dir_conf]="Create the configuration folder %s"
    [prep.d_conf]="Create the configuration %s (default values)"
    [prep.d_dir_backup]="Create the backup folder %s (root only)"
    [prep.d_log]="Create the audit log %s"
    [prep.d_grupo]="Create the system group %s (gsb users)"
    [prep.d_shares_conf]="Create the gsb shares file %s"
    [prep.d_include]="Add to %s the line \"include = %s\" (with backup and validation)"
    [prep.pergunta]="Set up now?"
    [prep.recusado]="Nothing was changed. gsb will work in a limited way until the environment is set up (menu 9)."
    [prep.nada_a_fazer]="The environment is already set up. Nothing to do."
    [prep.concluido]="Environment set up successfully."
    [prep.falhou]="Failed: %s"
    [prep.desfazendo]="Undoing what gsb had already done..."
    [prep.mantidos_pacotes]="The installed packages were kept: %s"
    [prep.mantido_servico]="The Samba service was kept running."
    [prep.impossivel_manual]="Some items cannot be fixed by gsb (marked with ✘). Fix them and run gsb again."
    [prep.impossivel_pacotes]="Automatic installation is not available on this system. Install manually: %s"
    [prep.apt_atualizando]="Updating the package list (apt-get update)..."
    [prep.apt_update_falhou]="Could not update the package list; trying to install anyway."
    [prep.apt_instalando]="Installing: %s (this may take a few minutes)..."
    [prep.apt_falhou]="Installation failed (no internet? broken repositories?). Last lines:"
    [prep.apt_conferencia]="After installation, the command %s still does not exist (package %s)."
    [prep.servico_falhou]="Could not activate the service %s (see: systemctl status %s)."
    [prep.include_testparm]="smb.conf became invalid with the gsb line (testparm)."
    [prep.recarregar_falhou]="Could not reload Samba."
    [prep.backup_sem_arquivo]="Backup impossible: %s does not exist."
    [prep.backup_falhou]="Could not back up %s."
    [prep.d_ssh_protecao]="Block SSH for gsb users (%s with \"DenyGroups %s\"), validate and reload SSH without dropping anyone"
    [prep.ssh_admin_no_grupo]="You (%s) are a member of %s: applying the protection would lock you out of SSH. Nothing was done."
    [prep.ssh_arquivo_alheio]="%s already exists and was not created by gsb: gsb will not overwrite it."
    [prep.ssh_invalido]="The SSH configuration became invalid (sshd -t); SSH was NOT reloaded:"
    [prep.ssh_recarregar]="Could not reload SSH (%s)."
    [prep.ssh_nao_confirmada]="The rule did not show up in the effective SSH configuration (sshd -T)."
    [ajuda.texto]="Usage: gsb [option]

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
# 6. AMBIENTE (detecção - somente leitura)
# ════════════════════════════════════════════════════════════════════════════
# Descobre o que existe na máquina: sistema, systemd, dependências, Samba e
# SSH. Nada aqui altera o sistema. O resultado alimenta o relatório
# (gsb --verificar / menu Ambiente) e, na tarefa 0.3, a preparação.

# Arquivos do sistema consultados (variáveis para os testes poderem simular)
GSB_ARQ_OS_RELEASE="${GSB_ARQ_OS_RELEASE:-/etc/os-release}"
GSB_ARQ_SSHD_CONFIG="${GSB_ARQ_SSHD_CONFIG:-/etc/ssh/sshd_config}"
GSB_DIR_SYSTEMD="${GSB_DIR_SYSTEMD:-/run/systemd/system}"

# Tabela de dependências - ÚNICO ponto específico da distribuição.
# comando | tipo | pacote no Debian
#   essencial      : sem ele o gsb não funciona (a 0.3 oferece instalar)
#   condicional    : só necessário se existir (ex: SSH -> proteção)
#   desenvolvimento: só para quem desenvolve/testa o gsb; nunca instalado
GSB_DEPENDENCIAS=(
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
gsb_tem_comando() { command -v "$1" >/dev/null 2>&1; }

# Lê o /etc/os-release SEM executá-lo (só ID, ID_LIKE, VERSION_ID, PRETTY_NAME)
gsb_ler_os_release() {
    local linha chave valor
    GSB_SO_ID=""; GSB_SO_ID_LIKE=""; GSB_SO_VERSAO=""; GSB_SO_NOME=""
    [ -r "$GSB_ARQ_OS_RELEASE" ] || return 1
    while IFS= read -r linha || [ -n "$linha" ]; do
        [[ "$linha" =~ ^([A-Z_]+)=(.*)$ ]] || continue
        chave="${BASH_REMATCH[1]}"
        valor="${BASH_REMATCH[2]}"
        if [[ "$valor" =~ ^\"(.*)\"$ || "$valor" =~ ^\'(.*)\'$ ]]; then
            valor="${BASH_REMATCH[1]}"
        fi
        case "$chave" in
            ID)          GSB_SO_ID="$valor" ;;
            ID_LIKE)     GSB_SO_ID_LIKE="$valor" ;;
            VERSION_ID)  GSB_SO_VERSAO="$valor" ;;
            PRETTY_NAME) GSB_SO_NOME="$valor" ;;
        esac
    done < "$GSB_ARQ_OS_RELEASE"
    return 0
}

# Debian ou derivado (Ubuntu, Mint...)? Usar depois de gsb_ler_os_release.
gsb_familia_debian() {
    [ "$GSB_SO_ID" == "debian" ] || [[ " $GSB_SO_ID_LIKE " == *" debian "* ]]
}

# Serviços (systemd)
gsb_servico_existe()    { systemctl list-unit-files --no-legend "$1.service" 2>/dev/null | grep -q .; }
gsb_servico_ativo()     { systemctl is-active --quiet "$1.service" 2>/dev/null; }
gsb_servico_habilitado() { systemctl is-enabled --quiet "$1.service" 2>/dev/null; }

# Primeiro nome de serviço existente da lista (smbd no Debian, smb no RHEL...)
gsb_descobrir_servico() {
    local nome
    for nome in "$@"; do
        gsb_servico_existe "$nome" && { echo "$nome"; return 0; }
    done
    return 1
}

# O sshd_config inclui o arquivo próprio do gsb (GSB_SSH_DROPIN)?
# Lê as linhas "Include" (palavra sem diferenciar maiúsculas; caminhos
# relativos são relativos a /etc/ssh) e testa se algum padrão cobre o arquivo.
# Retorna: 0 = inclui; 1 = não inclui; 2 = inclui só DEPOIS de um bloco
# "Match" (aí a regra do gsb valeria só dentro do Match, não para todos -
# comprovado com sshd -T).
gsb_ssh_aceita_dropin() {
    local linha padrao depois_de_match=0
    local -a padroes
    [ -r "$GSB_ARQ_SSHD_CONFIG" ] || return 1
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
            if [[ "$GSB_SSH_DROPIN" == $padrao ]]; then
                [ "$depois_de_match" -eq 1 ] && return 2
                return 0
            fi
        done
    done < "$GSB_ARQ_SSHD_CONFIG"
    return 1
}

# A proteção está EFETIVA? Consulta a configuração geral em vigor (sshd -T),
# não só se o arquivo existe: o grupo precisa estar em "denygroups".
gsb_ssh_protecao_ativa() {
    sshd -T 2>/dev/null | awk -v g="$GSB_GRUPO_USUARIOS" \
        '$1 == "denygroups" { for (i = 2; i <= NF; i++) if ($i == g) achou = 1 } END { exit !achou }'
}

# Lê um parâmetro do Samba já interpretado pelo testparm (ex: "server role")
gsb_samba_param() {
    testparm -s --parameter-name="$1" "$GSB_SMB_CONF" 2>/dev/null
}

# Modo efetivo do Samba. Com "server role = auto" (padrão quando a linha não
# existe) o modo real vem do "security": AUTO/USER = servidor independente,
# ADS/DOMAIN = membro de domínio.
gsb_samba_papel_efetivo() {
    local papel seguranca
    papel=$(gsb_samba_param "server role")
    if [ "$papel" == "auto" ]; then
        seguranca=$(gsb_samba_param "security")
        case "${seguranca^^}" in
            AUTO|USER)  papel="standalone server" ;;
            ADS|DOMAIN) papel="member server" ;;
        esac
    fi
    echo "$papel"
}

# ── Resultado da verificação ────────────────────────────────────────────────
# GSB_VERIF: linhas "grupo<TAB>estado<TAB>texto"
#   estados: ok | falta (impede o uso) | aviso | info | na (não se aplica)
# GSB_PACOTES_FALTANDO: pacotes (Debian) dos itens essenciais que faltam
# GSB_BLOQUEIOS: quantos itens impedem o gsb de funcionar
gsb_verif_add() { GSB_VERIF+=("$1"$'\t'"$2"$'\t'"$3"); [ "$2" == "falta" ] && GSB_BLOQUEIOS=$((GSB_BLOQUEIOS + 1)); return 0; }

# Bloqueio que o gsb NÃO consegue resolver sozinho (exige o administrador)
gsb_verif_manual() { gsb_verif_add "$1" falta "$2"; GSB_BLOQ_MANUAL=$((GSB_BLOQ_MANUAL + 1)); }

gsb_pacote_add() {
    local p
    [ -z "$1" ] && return 0
    for p in "${GSB_PACOTES_FALTANDO[@]}"; do [ "$p" == "$1" ] && return 0; done
    GSB_PACOTES_FALTANDO+=("$1")
}

# Faz toda a verificação. Retorna 0 se nada impede o gsb de funcionar.
# Além de GSB_VERIF / GSB_PACOTES_FALTANDO / GSB_BLOQUEIOS, deixa prontos
# para a preparação (0.3) e a proteção SSH (0.4):
#   GSB_SVC_SAMBA / GSB_SVC_SSH  nome do serviço (vazio se não encontrado)
#   GSB_TEM_SSH                  1 se o servidor SSH está instalado
#   GSB_SSH_DROPIN_OK            1 se o sshd_config inclui o arquivo do gsb
#                                (e não só depois de um bloco Match)
#   GSB_SSH_PROTEGIDO            1 se a proteção SSH está efetiva (sshd -T)
#   GSB_BLOQ_MANUAL              bloqueios que exigem o administrador
#                                (os demais se resolvem instalando pacotes)
# shellcheck disable=SC2034  # variáveis de saída, usadas pelas próximas tarefas
gsb_verificar_ambiente() {
    local dep cmd tipo pacote presentes=0 total=0 papel backend senha_ssh
    GSB_VERIF=(); GSB_PACOTES_FALTANDO=(); GSB_BLOQUEIOS=0; GSB_BLOQ_MANUAL=0
    GSB_SVC_SAMBA=""; GSB_SVC_SSH=""; GSB_TEM_SSH=0; GSB_SSH_DROPIN_OK=0; GSB_SSH_PROTEGIDO=0

    # ── Sistema ──
    if gsb_ler_os_release; then
        gsb_verif_add sistema ok "${GSB_SO_NOME:-$GSB_SO_ID $GSB_SO_VERSAO}"
        gsb_familia_debian || gsb_verif_add sistema aviso "$(t amb.so_nao_debian)"
    else
        gsb_verif_add sistema aviso "$(t amb.so_desconhecido "$GSB_ARQ_OS_RELEASE")"
    fi
    gsb_verif_add sistema ok "bash $BASH_VERSION"
    if [ -d "$GSB_DIR_SYSTEMD" ]; then
        gsb_verif_add sistema ok "$(t amb.systemd_ok)"
    else
        gsb_verif_manual sistema "$(t amb.systemd_falta)"
    fi

    # ── Dependências ──
    for dep in "${GSB_DEPENDENCIAS[@]}"; do
        IFS='|' read -r cmd tipo pacote <<< "$dep"
        case "$tipo" in
            essencial)
                total=$((total + 1))
                if gsb_tem_comando "$cmd"; then
                    presentes=$((presentes + 1))
                else
                    gsb_verif_add deps falta "$(t amb.dep_falta "$cmd" "$pacote")"
                    # systemd não se resolve instalando o pacote (ex: container)
                    [ "$cmd" != "systemctl" ] && gsb_pacote_add "$pacote"
                fi ;;
            desenvolvimento)
                if gsb_tem_comando "$cmd"; then
                    gsb_verif_add dev ok "$(t amb.dev_ok "$cmd")"
                else
                    gsb_verif_add dev info "$(t amb.dev_falta "$cmd")"
                fi ;;
        esac
    done
    [ "$presentes" -eq "$total" ] && gsb_verif_add deps ok "$(t amb.deps_ok "$total")"

    # ── Samba ──
    if ! gsb_tem_comando smbd; then
        gsb_verif_add samba falta "$(t amb.samba_ausente)"
    else
        if GSB_SVC_SAMBA=$(gsb_descobrir_servico smbd smb); then
            if gsb_servico_ativo "$GSB_SVC_SAMBA"; then
                gsb_verif_add samba ok "$(t amb.servico_ativo "$GSB_SVC_SAMBA")"
            else
                gsb_verif_add samba aviso "$(t amb.servico_parado "$GSB_SVC_SAMBA")"
            fi
            gsb_servico_habilitado "$GSB_SVC_SAMBA" || gsb_verif_add samba aviso "$(t amb.servico_desabilitado "$GSB_SVC_SAMBA")"
        else
            gsb_verif_add samba aviso "$(t amb.servico_nao_encontrado "smbd/smb")"
        fi

        if [ ! -f "$GSB_SMB_CONF" ]; then
            gsb_verif_manual samba "$(t amb.smbconf_ausente "$GSB_SMB_CONF")"
        elif ! gsb_tem_comando testparm; then
            :   # já listado como dependência faltando
        elif ! testparm -s "$GSB_SMB_CONF" >/dev/null 2>&1; then
            gsb_verif_manual samba "$(t amb.smbconf_invalido "$GSB_SMB_CONF")"
        else
            gsb_verif_add samba ok "$(t amb.smbconf_ok "$GSB_SMB_CONF")"
            papel=$(gsb_samba_papel_efetivo)
            case "$papel" in
                "standalone server") gsb_verif_add samba ok "$(t amb.papel_ok)" ;;
                *"domain controller"*) gsb_verif_manual samba "$(t amb.papel_dc "$papel")" ;;
                *) gsb_verif_add samba aviso "$(t amb.papel_outro "$papel")" ;;
            esac
            backend=$(gsb_samba_param "passdb backend")
            if [ "$backend" == "tdbsam" ]; then
                gsb_verif_add samba ok "$(t amb.backend_ok "$backend")"
            else
                gsb_verif_manual samba "$(t amb.backend_outro "$backend")"
            fi
        fi
    fi

    # ── SSH (condicional) ──
    if ! gsb_tem_comando sshd; then
        gsb_verif_add ssh na "$(t amb.ssh_ausente)"
    else
        GSB_TEM_SSH=1
        if GSB_SVC_SSH=$(gsb_descobrir_servico ssh sshd); then
            if gsb_servico_ativo "$GSB_SVC_SSH"; then
                gsb_verif_add ssh ok "$(t amb.servico_ativo "$GSB_SVC_SSH")"
            else
                gsb_verif_add ssh info "$(t amb.servico_parado "$GSB_SVC_SSH")"
            fi
        fi
        gsb_ssh_aceita_dropin
        case $? in
            0) GSB_SSH_DROPIN_OK=1
               gsb_verif_add ssh ok "$(t amb.dropin_ok "$GSB_ARQ_SSHD_CONFIG" "$GSB_SSH_DROPIN")" ;;
            2) gsb_verif_add ssh aviso "$(t amb.dropin_apos_match "$GSB_ARQ_SSHD_CONFIG" "$GSB_SSH_DROPIN")" ;;
            *) gsb_verif_add ssh aviso "$(t amb.dropin_falta "$GSB_ARQ_SSHD_CONFIG" "$GSB_SSH_DROPIN")" ;;
        esac
        if gsb_ssh_protecao_ativa; then
            GSB_SSH_PROTEGIDO=1
            gsb_verif_add ssh ok "$(t amb.ssh_protecao_ativa "$GSB_GRUPO_USUARIOS")"
        elif [ "$GSB_SSH_DROPIN_OK" -eq 1 ]; then
            gsb_verif_add ssh info "$(t amb.ssh_protecao_inativa)"
        fi
        senha_ssh=$(sshd -T 2>/dev/null | awk '$1 == "passwordauthentication" {print $2}')
        [ "$senha_ssh" == "yes" ] && gsb_verif_add ssh info "$(t amb.ssh_senha)"
    fi

    [ "$GSB_BLOQUEIOS" -eq 0 ]
}

# Mostra o resultado da última verificação, por grupo
gsb_mostrar_ambiente() {
    local grupo item g estado texto icone cor
    for grupo in sistema deps samba ssh dev; do
        echo ""
        printf '  %s%s%s\n' "$C_NEGRITO" "$(t "amb.grupo_$grupo")" "$C_RESET"
        for item in "${GSB_VERIF[@]}"; do
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
    if [ "$GSB_BLOQUEIOS" -eq 0 ]; then
        msg_ok "$(t amb.resumo_ok)"
    else
        msg_erro "$(t amb.resumo_falta "$GSB_BLOQUEIOS")"
        if [ ${#GSB_PACOTES_FALTANDO[@]} -gt 0 ]; then
            msg_info "$(t amb.pacotes "${GSB_PACOTES_FALTANDO[*]}")"
        fi
    fi
}

# ════════════════════════════════════════════════════════════════════════════
# 7. PREPARAÇÃO DO AMBIENTE
# ════════════════════════════════════════════════════════════════════════════
# Resolve o que a detecção encontrou: instala pacotes (Debian), liga o
# Samba, cria a estrutura do gsb e o "include" no smb.conf. Sempre com
# plano mostrado antes e UMA confirmação. Se um passo falhar, desfaz o que
# é do gsb (arquivos, pastas, grupo, smb.conf); pacotes instalados e o
# serviço do Samba ligado NÃO são desfeitos (desinstalar no meio de uma
# falha arriscaria quebrar mais do que consertar) - e isso é informado.

GSB_APT="${GSB_APT:-apt-get}"    # variável para os testes poderem simular

# Ordem das chaves no gsb.conf gerado
GSB_CONF_ORDEM=(IDIOMA SENHA_MIN GRUPO_USUARIOS PREFIXO_GRUPO SMB_CONF SHARES_CONF SSH_DROPIN LOG BACKUP_DIR BACKUP_MANTER TRAVA)

# ── Backups ─────────────────────────────────────────────────────────────────
# Copia o arquivo para GSB_BACKUP_DIR (pasta 700, cópia 600) com data/hora
# e mantém só as GSB_BACKUP_MANTER cópias mais recentes daquele arquivo.
# Imprime o caminho do backup.
gsb_backup() {
    local arquivo="$1" nome destino
    if [ ! -f "$arquivo" ]; then
        msg_erro "$(t prep.backup_sem_arquivo "$arquivo")"
        return 1
    fi
    if ! ( umask 077; mkdir -p -- "$GSB_BACKUP_DIR" ) || ! chmod 700 -- "$GSB_BACKUP_DIR"; then
        msg_erro "$(t prep.backup_falhou "$arquivo")"
        return 1
    fi
    nome=$(basename -- "$arquivo")
    destino="$GSB_BACKUP_DIR/$nome.$(date +%Y%m%d-%H%M%S-%N)"
    if ! cp -p -- "$arquivo" "$destino" || ! chmod 600 -- "$destino"; then
        rm -f -- "$destino"
        msg_erro "$(t prep.backup_falhou "$arquivo")"
        return 1
    fi
    gsb_backup_limpar "$nome"
    echo "$destino"
}

# Apaga as cópias mais antigas de <nome>, mantendo GSB_BACKUP_MANTER
gsb_backup_limpar() {
    local nome="$1"
    find "$GSB_BACKUP_DIR" -maxdepth 1 -type f -name "$nome.[0-9]*" -printf '%f\n' 2>/dev/null \
        | sort | head -n -"$GSB_BACKUP_MANTER" \
        | while IFS= read -r velho; do rm -f -- "$GSB_BACKUP_DIR/$velho"; done
}

# ── Peças da estrutura do gsb ───────────────────────────────────────────────
gsb_dir_conf() { dirname -- "$GSB_CONF_ARQUIVO"; }

# A linha "include = <SHARES_CONF>" já está no smb.conf?
gsb_include_presente() {
    local caminho_er="${GSB_SHARES_CONF//./\\.}"
    [ -f "$GSB_SMB_CONF" ] && grep -qiE "^[[:space:]]*include[[:space:]]*=[[:space:]]*${caminho_er}[[:space:]]*$" "$GSB_SMB_CONF"
}

# Recarrega o Samba (só se o serviço estiver ativo)
gsb_samba_recarregar() {
    [ -n "$GSB_SVC_SAMBA" ] || GSB_SVC_SAMBA=$(gsb_descobrir_servico smbd smb) || return 0
    gsb_servico_ativo "$GSB_SVC_SAMBA" || return 0
    systemctl reload "$GSB_SVC_SAMBA.service"
}

# ── Plano ───────────────────────────────────────────────────────────────────
# GSB_PLANO: ids das ações, na ordem de execução.
# GSB_PLANO_IMPOSSIVEL: motivo, se algo não pode ser resolvido pelo gsb.
# Usar depois de gsb_verificar_ambiente.
gsb_montar_plano() {
    GSB_PLANO=(); GSB_PLANO_IMPOSSIVEL=""

    if [ "$GSB_BLOQ_MANUAL" -gt 0 ]; then
        GSB_PLANO_IMPOSSIVEL="$(t prep.impossivel_manual)"
        return 0
    fi
    if [ ${#GSB_PACOTES_FALTANDO[@]} -gt 0 ]; then
        if gsb_familia_debian && gsb_tem_comando "$GSB_APT"; then
            GSB_PLANO+=(pacotes)
        else
            GSB_PLANO_IMPOSSIVEL="$(t prep.impossivel_pacotes "${GSB_PACOTES_FALTANDO[*]}")"
            return 0
        fi
    fi
    # Serviço: se o Samba vai ser instalado agora, o estado só se sabe depois
    if [[ " ${GSB_PLANO[*]} " == *" pacotes "* ]] || [ -z "$GSB_SVC_SAMBA" ] \
       || ! gsb_servico_ativo "$GSB_SVC_SAMBA" || ! gsb_servico_habilitado "$GSB_SVC_SAMBA"; then
        GSB_PLANO+=(samba_servico)
    fi
    [ -d "$(gsb_dir_conf)" ]      || GSB_PLANO+=(dir_conf)
    [ -f "$GSB_CONF_ARQUIVO" ]    || GSB_PLANO+=(conf)
    [ -d "$GSB_BACKUP_DIR" ]      || GSB_PLANO+=(dir_backup)
    [ -f "$GSB_LOG" ]             || GSB_PLANO+=(log)
    getent group "$GSB_GRUPO_USUARIOS" >/dev/null 2>&1 || GSB_PLANO+=(grupo)
    [ -f "$GSB_SHARES_CONF" ]     || GSB_PLANO+=(shares_conf)
    gsb_include_presente          || GSB_PLANO+=(include)
    # Proteção SSH: só se há servidor SSH, o sshd_config aceita o arquivo do
    # gsb e a proteção ainda não está efetiva
    if [ "$GSB_TEM_SSH" -eq 1 ] && [ "$GSB_SSH_DROPIN_OK" -eq 1 ] && [ "$GSB_SSH_PROTEGIDO" -eq 0 ]; then
        GSB_PLANO+=(ssh_protecao)
    fi
    return 0
}

# Descrição de uma ação do plano (para mostrar antes de confirmar)
gsb_descrever_acao() {
    case "$1" in
        pacotes)       t prep.d_pacotes "${GSB_PACOTES_FALTANDO[*]}" ;;
        samba_servico) t prep.d_samba_servico ;;
        dir_conf)      t prep.d_dir_conf "$(gsb_dir_conf)" ;;
        conf)          t prep.d_conf "$GSB_CONF_ARQUIVO" ;;
        dir_backup)    t prep.d_dir_backup "$GSB_BACKUP_DIR" ;;
        log)           t prep.d_log "$GSB_LOG" ;;
        grupo)         t prep.d_grupo "$GSB_GRUPO_USUARIOS" ;;
        shares_conf)   t prep.d_shares_conf "$GSB_SHARES_CONF" ;;
        include)       t prep.d_include "$GSB_SMB_CONF" "$GSB_SHARES_CONF" ;;
        ssh_protecao)  t prep.d_ssh_protecao "$GSB_SSH_DROPIN" "$GSB_GRUPO_USUARIOS" ;;
    esac
}

gsb_mostrar_plano() {
    local acao
    echo ""
    printf '  %s%s%s\n' "$C_NEGRITO" "$(t prep.titulo_plano)" "$C_RESET"
    for acao in "${GSB_PLANO[@]}"; do
        printf '    • %s\n' "$(gsb_descrever_acao "$acao")"
    done
    echo ""
}

# ── Ações (cada uma retorna 0 se deu certo, conferindo o resultado) ─────────
gsb_acao_pacotes() {
    local registro cmd dep tipo pacote
    registro=$(gsb_temp) || return 1
    msg_info "$(t prep.apt_atualizando)"
    if ! DEBIAN_FRONTEND=noninteractive "$GSB_APT" -o DPkg::Lock::Timeout=120 update >"$registro" 2>&1; then
        msg_aviso "$(t prep.apt_update_falhou)"
    fi
    msg_info "$(t prep.apt_instalando "${GSB_PACOTES_FALTANDO[*]}")"
    # confdef/confold: se existir configuração antiga (ex: smb.conf de uma
    # instalação anterior), mantém a existente em vez de parar perguntando
    if ! DEBIAN_FRONTEND=noninteractive "$GSB_APT" -o DPkg::Lock::Timeout=120 \
            -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
            install -y "${GSB_PACOTES_FALTANDO[@]}" >>"$registro" 2>&1; then
        msg_erro "$(t prep.apt_falhou)"
        tail -n 8 "$registro" | sed 's/^/     /' >&2
        return 1
    fi
    # Confere: todos os comandos essenciais agora existem?
    for dep in "${GSB_DEPENDENCIAS[@]}"; do
        IFS='|' read -r cmd tipo pacote <<< "$dep"
        [ "$tipo" == "essencial" ] || continue
        if ! gsb_tem_comando "$cmd"; then
            msg_erro "$(t prep.apt_conferencia "$cmd" "$pacote")"
            return 1
        fi
    done
    GSB_PACOTES_INSTALADOS="${GSB_PACOTES_FALTANDO[*]}"
}

gsb_acao_samba_servico() {
    if ! GSB_SVC_SAMBA=$(gsb_descobrir_servico smbd smb); then
        msg_erro "$(t amb.servico_nao_encontrado "smbd/smb")"
        return 1
    fi
    if ! gsb_servico_habilitado "$GSB_SVC_SAMBA"; then
        systemctl enable "$GSB_SVC_SAMBA.service" >/dev/null 2>&1 || true
    fi
    if ! gsb_servico_ativo "$GSB_SVC_SAMBA"; then
        systemctl start "$GSB_SVC_SAMBA.service" >/dev/null 2>&1 || true
    fi
    gsb_servico_ativo "$GSB_SVC_SAMBA" && gsb_servico_habilitado "$GSB_SVC_SAMBA" && return 0
    msg_erro "$(t prep.servico_falhou "$GSB_SVC_SAMBA")"
    return 1
}

gsb_acao_dir_conf()   { ( umask 022; mkdir -p -- "$(gsb_dir_conf)" ) && chmod 755 -- "$(gsb_dir_conf)"; }
gsb_acao_dir_backup() { ( umask 077; mkdir -p -- "$GSB_BACKUP_DIR" ) && chmod 700 -- "$GSB_BACKUP_DIR"; }
gsb_acao_log()        { ( umask 027; : >> "$GSB_LOG" ) && chmod 640 -- "$GSB_LOG"; }
gsb_acao_grupo()      { groupadd --system -- "$GSB_GRUPO_USUARIOS" && getent group "$GSB_GRUPO_USUARIOS" >/dev/null; }

gsb_acao_conf() {
    local chave var
    {
        echo "# /etc/gsb/gsb.conf - gerado pelo gsb $GSB_VERSAO em $(date '+%Y-%m-%d %H:%M')"
        echo "# Descrição de cada opção: gsb.conf.exemplo (no repositório do gsb)."
        echo "# Formato CHAVE=valor; o arquivo é lido, nunca executado."
        echo ""
        for chave in "${GSB_CONF_ORDEM[@]}"; do
            var="GSB_$chave"
            printf '%s=%s\n' "$chave" "${!var}"
        done
    } > "$GSB_CONF_ARQUIVO" && chmod 644 -- "$GSB_CONF_ARQUIVO" && chown 0:0 -- "$GSB_CONF_ARQUIVO" \
        && gsb_conf_carregar "$GSB_CONF_ARQUIVO"
}

gsb_acao_shares_conf() {
    {
        echo "# Compartilhamentos gerenciados pelo gsb (Gerenciador Samba)."
        echo "# NÃO edite à mão: use o gsb. Este arquivo é incluído pelo"
        echo "# $GSB_SMB_CONF (linha \"include = $GSB_SHARES_CONF\")."
    } > "$GSB_SHARES_CONF" && chmod 644 -- "$GSB_SHARES_CONF"
}

gsb_acao_include() {
    local backup quebra=""
    if [ ! -f "$GSB_SMB_CONF" ]; then
        msg_erro "$(t amb.smbconf_ausente "$GSB_SMB_CONF")"
        return 1
    fi
    backup=$(gsb_backup "$GSB_SMB_CONF") || return 1
    GSB_BACKUP_SMBCONF="$backup"
    # Se o arquivo não termina com quebra de linha, acrescenta uma antes
    [ -n "$(tail -c 1 -- "$GSB_SMB_CONF")" ] && quebra=$'\n'
    {
        printf '%s' "$quebra"
        echo ""
        echo "# gsb - Gerenciador Samba: compartilhamentos do gsb (não remova esta linha)"
        echo "include = $GSB_SHARES_CONF"
    } >> "$GSB_SMB_CONF" || return 1
    if ! testparm -s "$GSB_SMB_CONF" >/dev/null 2>&1; then
        msg_erro "$(t prep.include_testparm)"
        return 1
    fi
    gsb_include_presente || return 1
    if ! gsb_samba_recarregar; then
        msg_erro "$(t prep.recarregar_falhou)"
        return 1
    fi
}

# ── Proteção SSH ────────────────────────────────────────────────────────────
GSB_SSH_MARCA="# gsb - Gerenciador Samba: bloqueio SSH dos usuários do servidor de arquivos"

# Recarrega o SSH, só se o serviço estiver ativo. Com ativação por socket
# (ou serviço parado) não é preciso: cada nova conexão/início lê a config.
gsb_ssh_recarregar() {
    [ -n "$GSB_SVC_SSH" ] || GSB_SVC_SSH=$(gsb_descobrir_servico ssh sshd) || return 0
    gsb_servico_ativo "$GSB_SVC_SSH" || return 0
    systemctl reload "$GSB_SVC_SSH.service"
}

# Cria o arquivo próprio do gsb com "DenyGroups <grupo>", valida a
# configuração ANTES de recarregar (recarregar o SSH com config inválida pode
# derrubar o serviço), recarrega e confere no sshd -T que vale para todos.
gsb_acao_ssh_protecao() {
    local quem erros
    # O desfazer só mexe no que esta operação realmente fez
    GSB_BACKUP_SSHDROPIN=""; GSB_SSH_ESCRITO=0; GSB_SSH_RECARREGADO=0

    # Nunca trancar fora quem está rodando o gsb (via sudo ou root direto)
    quem="${SUDO_USER:-root}"
    if id -nG "$quem" 2>/dev/null | tr ' ' '\n' | grep -qxF "$GSB_GRUPO_USUARIOS"; then
        msg_erro "$(t prep.ssh_admin_no_grupo "$quem" "$GSB_GRUPO_USUARIOS")"
        return 1
    fi
    # Não sobrescreve arquivo que não é do gsb
    if [ -f "$GSB_SSH_DROPIN" ]; then
        if ! grep -qxF "$GSB_SSH_MARCA" "$GSB_SSH_DROPIN"; then
            msg_erro "$(t prep.ssh_arquivo_alheio "$GSB_SSH_DROPIN")"
            return 1
        fi
        GSB_BACKUP_SSHDROPIN=$(gsb_backup "$GSB_SSH_DROPIN") || return 1
    fi

    {
        echo "$GSB_SSH_MARCA"
        echo "# Gerado pelo gsb em $(date '+%Y-%m-%d %H:%M'). NÃO edite à mão: use o gsb."
        echo "DenyGroups $GSB_GRUPO_USUARIOS"
    } > "$GSB_SSH_DROPIN"
    GSB_SSH_ESCRITO=1
    chmod 644 -- "$GSB_SSH_DROPIN" || return 1

    if ! erros=$(sshd -t 2>&1); then
        msg_erro "$(t prep.ssh_invalido)"
        printf '%s\n' "$erros" | head -5 | sed 's/^/     /' >&2
        return 1
    fi
    GSB_SSH_RECARREGADO=1
    if ! gsb_ssh_recarregar; then
        msg_erro "$(t prep.ssh_recarregar "$GSB_SVC_SSH")"
        return 1
    fi
    if ! gsb_ssh_protecao_ativa; then
        msg_erro "$(t prep.ssh_nao_confirmada)"
        return 1
    fi
}

# Desfaz SÓ o que a operação fez: se escreveu o arquivo, volta o anterior
# (backup) ou o remove; se recarregou o SSH, recarrega de novo - e só com a
# configuração válida. Falha antes de escrever = nada a desfazer.
gsb_ssh_desfazer() {
    [ "${GSB_SSH_ESCRITO:-0}" -eq 1 ] || return 0
    if [ -n "${GSB_BACKUP_SSHDROPIN:-}" ]; then
        cp -p -- "$GSB_BACKUP_SSHDROPIN" "$GSB_SSH_DROPIN"
    elif [ -f "$GSB_SSH_DROPIN" ] && grep -qxF "$GSB_SSH_MARCA" "$GSB_SSH_DROPIN"; then
        rm -f -- "$GSB_SSH_DROPIN"
    fi
    if [ "${GSB_SSH_RECARREGADO:-0}" -eq 1 ] && sshd -t >/dev/null 2>&1; then
        gsb_ssh_recarregar
    fi
}

# Remove a proteção (usada pela desinstalação). Retorna 0 se ao final o
# grupo não está mais em denygroups.
gsb_ssh_remover_protecao() {
    GSB_BACKUP_SSHDROPIN=""
    [ -f "$GSB_SSH_DROPIN" ] || return 0
    if ! grep -qxF "$GSB_SSH_MARCA" "$GSB_SSH_DROPIN"; then
        msg_erro "$(t prep.ssh_arquivo_alheio "$GSB_SSH_DROPIN")"
        return 1
    fi
    gsb_backup "$GSB_SSH_DROPIN" >/dev/null || return 1
    # Remover = desfazer um arquivo "escrito e em vigor"
    GSB_SSH_ESCRITO=1; GSB_SSH_RECARREGADO=1
    gsb_ssh_desfazer
    ! gsb_ssh_protecao_ativa
}

# ── Desfazer (só o que é do gsb) ────────────────────────────────────────────
gsb_desfazer() {
    case "$1" in
        dir_conf)    rmdir -- "$(gsb_dir_conf)" 2>/dev/null ;;
        conf)        rm -f -- "$GSB_CONF_ARQUIVO" ;;
        dir_backup)  rmdir -- "$GSB_BACKUP_DIR" 2>/dev/null ;;   # só se vazia
        grupo)       getent group "$GSB_GRUPO_USUARIOS" | awk -F: '$4 != "" {exit 1}' \
                         && groupdel -- "$GSB_GRUPO_USUARIOS" ;;
        shares_conf) [ "$(grep -cv '^#' "$GSB_SHARES_CONF" 2>/dev/null)" == "0" ] && rm -f -- "$GSB_SHARES_CONF" ;;
        include)     if [ -n "${GSB_BACKUP_SMBCONF:-}" ]; then
                         cp -p -- "$GSB_BACKUP_SMBCONF" "$GSB_SMB_CONF" && gsb_samba_recarregar
                     fi ;;
        ssh_protecao) gsb_ssh_desfazer ;;
        *)           return 0 ;;   # pacotes, serviço e log não são desfeitos
    esac
}

# ── Execução do plano ───────────────────────────────────────────────────────
# Executa GSB_PLANO na ordem. Se uma ação falhar, desfaz as anteriores (só o
# que é do gsb), na ordem inversa, e informa o que ficou.
gsb_executar_plano() {
    local acao i feito
    local -a feitos=()
    GSB_PACOTES_INSTALADOS=""; GSB_BACKUP_SMBCONF=""
    for acao in "${GSB_PLANO[@]}"; do
        if "gsb_acao_$acao"; then
            feitos+=("$acao")
            msg_ok "$(gsb_descrever_acao "$acao")"
            gsb_auditar preparar "acao=$acao resultado=ok"
        else
            msg_erro "$(t prep.falhou "$(gsb_descrever_acao "$acao")")"
            gsb_auditar preparar "acao=$acao resultado=falha"
            # A própria ação pode ter alterado algo antes de falhar (ex: o
            # include grava a linha e só depois valida): desfaz ela também
            gsb_desfazer "$acao"
            if [ ${#feitos[@]} -gt 0 ]; then
                msg_info "$(t prep.desfazendo)"
                for (( i=${#feitos[@]}-1; i>=0; i-- )); do
                    feito="${feitos[$i]}"
                    gsb_desfazer "$feito"
                    gsb_auditar preparar "acao=$feito resultado=desfeito"
                done
                [ -n "$GSB_PACOTES_INSTALADOS" ] && msg_aviso "$(t prep.mantidos_pacotes "$GSB_PACOTES_INSTALADOS")"
                [[ " ${feitos[*]} " == *" samba_servico "* ]] && msg_aviso "$(t prep.mantido_servico)"
            fi
            return 1
        fi
    done
    return 0
}

# Fluxo completo: verifica, mostra, oferece e prepara.
# Retorna 0 se ao final o ambiente está pronto.
gsb_preparar() {
    local plano_txt
    gsb_verificar_ambiente
    gsb_montar_plano
    if [ -n "$GSB_PLANO_IMPOSSIVEL" ]; then
        gsb_mostrar_ambiente
        msg_erro "$GSB_PLANO_IMPOSSIVEL"
        return 1
    fi
    if [ ${#GSB_PLANO[@]} -eq 0 ]; then
        msg_ok "$(t prep.nada_a_fazer)"
        return 0
    fi
    plano_txt=$(IFS=,; echo "${GSB_PLANO[*]}")
    gsb_mostrar_plano
    if ! confirmar "$(t prep.pergunta)"; then
        gsb_auditar preparar "plano=$plano_txt resposta=nao"
        msg_aviso "$(t prep.recusado)"
        return 1
    fi
    gsb_auditar preparar "plano=$plano_txt resposta=sim"
    if gsb_executar_plano; then
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
    gsb_verificar_ambiente
    gsb_mostrar_ambiente
    gsb_montar_plano
    if [ -z "$GSB_PLANO_IMPOSSIVEL" ] && [ ${#GSB_PLANO[@]} -gt 0 ]; then
        gsb_preparar
    fi
    pausar
}

# Assistente da primeira execução (e de quando algo "quebrou"): ao abrir o
# menu, se houver o que preparar, mostra o plano e pergunta. Retorna 1 se
# o gsb não puder funcionar (o menu não deve abrir).
gsb_assistente() {
    gsb_verificar_ambiente
    gsb_montar_plano
    if [ -n "$GSB_PLANO_IMPOSSIVEL" ]; then
        titulo "$(t amb.titulo)"
        gsb_mostrar_ambiente
        msg_erro "$GSB_PLANO_IMPOSSIVEL"
        return 1
    fi
    [ ${#GSB_PLANO[@]} -eq 0 ] && return 0
    titulo "$(t prep.titulo_assistente)"
    msg_info "$(t prep.intro)"
    gsb_preparar
    pausar
    return 0
}

menu_principal() {
    local opcao
    while true; do
        titulo "$(t geral.titulo)  ${C_CINZA}v${GSB_VERSAO}${C_RESET}"
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
        gsb_verificar_ambiente; local rc=$?
        gsb_mostrar_ambiente
        exit "$rc"
    fi

    trap gsb_ao_sair EXIT
    trap 'echo; msg_aviso "$(t geral.interrompido)"; GSB_MOTIVO_SAIDA="interrompida"; exit 130' INT TERM

    gsb_travar || exit 1
    gsb_auditar sessao_inicio "v$GSB_VERSAO${1:+ $1}"
    GSB_SESSAO_ATIVA=1

    # Preparação pela linha de comando
    if [ -n "${1:-}" ]; then
        gsb_preparar
        exit $?
    fi

    gsb_assistente || exit 1
    menu_principal
}

# Só executa quando chamado diretamente; com "source" apenas carrega
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
