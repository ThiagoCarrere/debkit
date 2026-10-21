# shellcheck shell=bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  debkit - núcleo                                                         ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# Parte comum a todos os módulos: configuração, mensagens, saída, trava,
# auditoria, backups, detecção e preparação do ambiente (dependências,
# proteção SSH, firewall), faixas de contas do login.defs, registro dos
# módulos, menus e linha de comando. Carregado pelo programa "debkit"
# (que antes confere o bash e a segurança dos arquivos); não é executado
# sozinho. Ver docs/PLANEJAMENTO.md.
#
# Copyright (c) 2026 Thiago Carrere - Licença MIT (ver LICENSE)
# Desenvolvido por Thiago Carrere em parceria com Claude (Anthropic).
#
# Seções do arquivo:
#   1. Versão
#   2. Configuração
#   3. Mensagens (catálogo pt_BR / en)
#   4. Cores e saída
#   5. Utilitários
#   6. Ambiente (detecção)
#   7. Preparação do ambiente
#   8. Módulos
#   9. Menus
#  10. Linha de comando

# ════════════════════════════════════════════════════════════════════════════
# 1. VERSÃO
# ════════════════════════════════════════════════════════════════════════════
DEBKIT_VERSAO="1.0.0"

# ════════════════════════════════════════════════════════════════════════════
# 2. CONFIGURAÇÃO
# ════════════════════════════════════════════════════════════════════════════
# Padrões; podem ser alterados em /etc/debkit/debkit.conf (ver debkit.conf.exemplo).
# O arquivo NÃO é executado: é lido linha a linha (CHAVE=valor), só chaves
# conhecidas são aceitas e cada valor é validado. Cada módulo acrescenta as
# suas chaves nestas tabelas (e em DEBKIT_CONF_ORDEM) ao ser carregado.

DEBKIT_CONF_ARQUIVO="${DEBKIT_CONF_ARQUIVO:-/etc/debkit/debkit.conf}"

# Chave -> valor padrão
declare -A DEBKIT_CONF_PADRAO=(
    [IDIOMA]="auto"
    [SENHA_MIN]="4"
    [GRUPO_USUARIOS]="debkit_usuarios"
    [SSH_DROPIN]="/etc/ssh/sshd_config.d/debkit.conf"
    [LOG]="/var/log/debkit.log"
    [LOG_LOGROTATE]="/etc/logrotate.d/debkit"
    [BACKUP_DIR]="/var/backups/debkit"
    [BACKUP_MANTER]="30"
    [TRAVA]="/run/debkit.lock"
)

# Chave -> tipo de validação
declare -A DEBKIT_CONF_TIPO=(
    [IDIOMA]="idioma"
    [SENHA_MIN]="inteiro_1_128"
    [GRUPO_USUARIOS]="nome"
    [SSH_DROPIN]="caminho"
    [LOG]="caminho"
    [LOG_LOGROTATE]="caminho"
    [BACKUP_DIR]="caminho"
    [BACKUP_MANTER]="inteiro_1_9999"
    [TRAVA]="caminho"
)

# Ordem das chaves no debkit.conf gerado pela preparação
DEBKIT_CONF_ORDEM=(IDIOMA SENHA_MIN GRUPO_USUARIOS SSH_DROPIN LOG LOG_LOGROTATE BACKUP_DIR BACKUP_MANTER TRAVA)

# Chaves de versões anteriores, que não são mais usadas: são ignoradas com
# um aviso próprio (e não como "desconhecida"), para o administrador saber
# que pode apagar a linha. Chave -> mensagem com o porquê saiu.
declare -A DEBKIT_CONF_OBSOLETA=(
    [SHARES_CONF]="conf.obs_shares_conf"
    [PREFIXO_GRUPO]="conf.obs_prefixo_grupo"
)

# Classes de caracteres SEM intervalos: num idioma como pt_BR, [a-z] no
# bash também aceita letras acentuadas (ã, é...). Usar sempre estas.
DEBKIT_MINUSCULAS="abcdefghijklmnopqrstuvwxyz"
DEBKIT_MAIUSCULAS="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
DEBKIT_DIGITOS="0123456789"

# Valida um valor conforme o tipo. Retorna 0 se válido.
debkit_conf_valor_valido() {
    local tipo="$1" valor="$2"
    case "$tipo" in
        idioma)         [[ "$valor" == "auto" || "$valor" == "pt_BR" || "$valor" == "en" ]] ;;
        inteiro_1_128)  [[ "$valor" =~ ^[0-9]{1,3}$ ]] && [ "$valor" -ge 1 ] && [ "$valor" -le 128 ] ;;
        inteiro_1_9999) [[ "$valor" =~ ^[0-9]{1,4}$ ]] && [ "$valor" -ge 1 ] ;;
        nome)           [[ "$valor" =~ ^[${DEBKIT_MINUSCULAS}_][${DEBKIT_MINUSCULAS}${DEBKIT_DIGITOS}_-]{0,31}$ ]] ;;
        caminho)        [[ "$valor" == /* && "$valor" != *..* && "$valor" =~ ^[${DEBKIT_MINUSCULAS}${DEBKIT_MAIUSCULAS}${DEBKIT_DIGITOS}/._-]+$ ]] ;;
        caminho_opcional) [ -z "$valor" ] || debkit_conf_valor_valido caminho "$valor" ;;
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
        DEBKIT_CONF_ERROS="$(t conf.e_ilegivel "$arquivo")"
        return 1
    fi
    # Segurança: só root pode poder alterar o arquivo
    dono=$(stat -c '%u' -- "$arquivo")
    perm=$(stat -c '%a' -- "$arquivo")
    if [ "$dono" != "0" ] || (( 8#$perm & 8#022 )); then
        DEBKIT_CONF_ERROS="$(t conf.e_inseguro "$arquivo" "$dono" "$perm")"
        return 1
    fi

    while IFS= read -r linha || [ -n "$linha" ]; do
        n=$((n + 1))
        linha="${linha%$'\r'}"
        [[ "$linha" =~ ^[[:space:]]*(#.*)?$ ]] && continue
        if [[ ! "$linha" =~ ^[[:space:]]*([A-Z_]+)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            DEBKIT_CONF_ERROS+="$(t conf.e_formato "$n")"$'\n'
            continue
        fi
        chave="${BASH_REMATCH[1]}"
        valor="${BASH_REMATCH[2]}"
        valor="${valor%"${valor##*[![:space:]]}"}"        # tira espaços do fim
        if [[ "$valor" =~ ^\"(.*)\"$ || "$valor" =~ ^\'(.*)\'$ ]]; then
            valor="${BASH_REMATCH[1]}"                    # tira aspas
        fi
        if [ -n "${DEBKIT_CONF_OBSOLETA[$chave]+x}" ]; then
            DEBKIT_CONF_AVISOS+="$(t conf.a_obsoleta "$n" "$chave" "$(t "${DEBKIT_CONF_OBSOLETA[$chave]}")")"$'\n'
            continue
        fi
        if [ -z "${DEBKIT_CONF_TIPO[$chave]+x}" ]; then
            DEBKIT_CONF_AVISOS+="$(t conf.a_desconhecida "$n" "$chave")"$'\n'
            continue
        fi
        if ! debkit_conf_valor_valido "${DEBKIT_CONF_TIPO[$chave]}" "$valor"; then
            DEBKIT_CONF_ERROS+="$(t conf.e_valor "$n" "$chave" "$valor")"$'\n'
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
    [geral.titulo]="debkit - administração de servidores Debian"
    [geral.versao]="debkit %s"
    [geral.sim_nao]="(s/n)"
    [geral.escolha]="Escolha uma opção: "
    [geral.enter_voltar]="Pressione Enter para voltar..."
    [geral.opcao_invalida]="Opção inválida: '%s'"
    [geral.sair]="Sair"
    [geral.voltar]="Voltar"
    [geral.em_construcao]="(as funções serão adicionadas nas próximas etapas)"
    [geral.interrompido]="Interrompido. Nada mais foi feito."
    [erro.root]="Este comando precisa ser executado como root (ex: sudo debkit)."
    [erro.uso]="Opção desconhecida: '%s'. Veja: debkit --ajuda"
    [cli.sim_resposta]="s (--sim)"
    [conf.e_ilegivel]="%s: não é um arquivo legível"
    [conf.e_inseguro]="%s: precisa pertencer ao root e não ter escrita para grupo/outros (atual: dono UID %s, permissão %s)"
    [conf.e_formato]="linha %d: formato inválido (use CHAVE=valor)"
    [conf.e_valor]="linha %d: valor inválido para %s: '%s'"
    [conf.a_obsoleta]="linha %d: a chave '%s' não é mais usada (%s): ignorada; pode apagar a linha"
    [conf.a_desconhecida]="linha %d: chave desconhecida '%s' (ignorada)"
    [conf.obs_shares_conf]="o debkit edita o smb.conf diretamente"
    [conf.obs_prefixo_grupo]="o debkit gerencia todos os grupos comuns"
    [conf.cabecalho]="%s - gerado pelo debkit %s em %s"
    [conf.cabecalho_exemplo]="Descrição de cada opção: debkit.conf.exemplo (em /opt/debkit ou no repositório do debkit)."
    [conf.cabecalho_formato]="Formato CHAVE=valor; o arquivo é lido, nunca executado."
    [amb.c_ausente]="arquivo ausente ou ilegível"
    [amb.c_invalido]="%s inválido ('%s')"
    [amb.c_invertida]="%s_MIN maior que %s_MAX"
    [desi.titulo]="debkit - desinstalação"
    [desi.vai]="A desinstalação vai remover:"
    [desi.fica]="Fica no servidor:"
    [desi.r_link]="O comando %s"
    [desi.r_programa]="O programa em %s (instalado pelo install.sh)"
    [desi.r_protecao]="A proteção SSH (%s) e o grupo %s, que está vazio (nenhum usuário de arquivos)"
    [desi.r_conf]="A configuração %s"
    [desi.r_log]="O log de auditoria %s (e os girados) e a regra da rotação dele (%s)"
    [desi.r_backups]="Os backups do debkit em %s e os do smb.conf em %s"
    [desi.f_repositorio]="O programa em %s: é um repositório (não foi copiado pelo install.sh); apague-o à mão se quiser"
    [desi.f_protecao]="A proteção SSH (%s) e o grupo %s: há %d usuário(s) de arquivos; sem ela eles poderiam entrar por SSH"
    [desi.f_dados]="A configuração (%s), o log de auditoria (%s) e os backups (%s, %s): use --tudo para remover também"
    [desi.f_usuarios]="Os usuários, grupos e compartilhamentos e o smb.conf (o servidor de arquivos continua funcionando)"
    [desi.f_firewall]="As regras \"debkit: Samba\" do firewall (se houver): sem elas o Samba seria bloqueado"
    [desi.pergunta]="Desinstalar?"
    [desi.cancelado]="Cancelado. Nada foi feito."
    [desi.nada]="Nada do debkit para remover."
    [desi.feito]="Removido: %s"
    [desi.falhou]="Não foi possível remover: %s"
    [desi.concluido]="debkit desinstalado."
    [desi.incompleto]="Desinstalação incompleta (veja acima)."
    [desi.tudo_onde]="--tudo só vale com --desinstalar"
    [inst.titulo]="debkit %s - instalação"
    [inst.ajuda]="Uso: sudo ./install.sh [--sim] [--simular]

Instala (ou atualiza) o debkit em %s, com o comando %s.
  --sim        responde \"s\" às perguntas (instala e prepara o servidor)
  --simular    mostra o que faria, sem fazer nada
  -h, --ajuda  mostra esta ajuda

A configuração (/etc/debkit), o log e os backups não são tocados.
Para desinstalar: debkit --desinstalar"
    [inst.opcao]="Opção desconhecida: '%s' (veja: ./install.sh --ajuda)"
    [inst.destino_invalido]="Pasta de instalação inválida: '%s' (caminho completo, sem espaços nem ..)"
    [inst.dentro]="A pasta de instalação %s e a pasta de onde se instala %s não podem estar uma dentro da outra."
    [inst.destino_git]="%s é um repositório git do debkit: atualize com \"git -C %s pull\" e rode o install.sh de lá."
    [inst.destino_alheio]="%s já existe e não é uma instalação do debkit: nada foi feito."
    [inst.link_alheio]="%s já existe e não aponta para %s: nada foi feito."
    [inst.plano]="O instalador vai:"
    [inst.p_novo]="Copiar o debkit %s para %s (só o programa: dono root, sem escrita para grupo/outros)"
    [inst.p_atualizar]="Atualizar %s (de %s para %s); a configuração em %s não muda"
    [inst.p_no_lugar]="Usar o debkit que já está em %s (conferir que tudo é do root e sem escrita para grupo/outros)"
    [inst.p_link]="Criar o comando %s (link para %s)"
    [inst.link_ok]="O comando %s já aponta para esta instalação."
    [inst.pergunta]="Instalar agora?"
    [inst.cancelado]="Cancelado. Nada foi feito."
    [inst.simulacao]="(simulação: nada foi feito)"
    [inst.falhou]="A instalação falhou: %s. %s ficou como estava."
    [inst.f_copiar]="não foi possível copiar os arquivos"
    [inst.f_conferir]="a cópia não funciona (debkit --versao)"
    [inst.f_trocar]="não foi possível pôr a cópia nova no lugar"
    [inst.f_permissoes]="não foi possível ajustar dono e permissões"
    [inst.f_link]="não foi possível criar o comando %s"
    [inst.ok]="debkit %s instalado em %s. Comando: %s"
    [inst.p_preparar]="Preparar o servidor agora (debkit --preparar)?"
    [inst.depois]="Quando quiser: sudo debkit --preparar (ou abra o menu: sudo debkit)"
    [cli.uso]="Uso incorreto: %s. Veja: %s"
    [cli.sim_onde]="--sim só vale para --preparar e para os comandos dos módulos"
    [erro.conf]="Configuração inválida em %s:"
    [aviso.conf]="Avisos da configuração %s:"
    [erro.trava]="O debkit já está em uso por outra sessão (PID %s). Tente novamente quando ela terminar."
    [erro.trava_abrir]="Não foi possível criar o arquivo de trava %s."
    [menu.ambiente]="Ambiente: verificar e preparar"
    [amb.titulo]="Ambiente do servidor"
    [amb.grupo_sistema]="Sistema"
    [amb.grupo_deps]="Dependências essenciais"
    [amb.grupo_ssh]="SSH"
    [amb.grupo_dev]="Desenvolvimento (opcional)"
    [amb.grupo_firewall]="Firewall"
    [amb.so_desconhecido]="Sistema não identificado (%s ausente ou ilegível)"
    [amb.so_nao_debian]="Distribuição fora da família Debian: não testada; instalação automática indisponível"
    [amb.systemd_ok]="systemd em execução"
    [amb.systemd_falta]="systemd não está em execução (ex: container): o debkit precisa dele para gerenciar serviços"
    [amb.contas_ok]="Contas comuns (%s): usuários UID %s-%s, grupos GID %s-%s"
    [amb.contas_padrao]="%s: %s - usando o padrão do Debian (UID/GID 1000-60000) para as contas comuns"
    [amb.deps_ok]="Todas as %d dependências essenciais presentes"
    [amb.dep_falta]="Falta o comando %s (pacote %s)"
    [amb.servico_ativo]="Serviço %s ativo"
    [amb.servico_parado]="Serviço %s parado"
    [amb.servico_desabilitado]="Serviço %s não inicia junto com o sistema"
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
    [prep.d_dir_conf]="Criar a pasta de configuração %s"
    [prep.d_conf]="Criar a configuração %s (com os valores padrão)"
    [prep.d_conf_obsoletas]="Remover do %s as chaves que não são mais usadas: %s (com backup; o resto do arquivo fica igual)"
    [prep.conf_obsoletas_conferencia]="Depois de tirar as chaves antigas, a configuração mudaria em outros valores. Nada foi alterado."
    [prep.conf_gravar_falhou]="Não foi possível gravar o %s. Nada foi alterado."
    [prep.d_dir_backup]="Criar a pasta de backups %s (acesso só do root)"
    [prep.d_log]="Criar o log de auditoria %s"
    [prep.d_log_rotacao]="Girar o log de auditoria %s todo mês, guardando 24 meses compactados (regra %s)"
    [prep.d_grupo]="Criar o grupo de sistema %s (usuários do debkit)"
    [prep.pergunta]="Preparar agora?"
    [prep.recusado]="Nada foi alterado. O debkit vai funcionar de forma limitada até o ambiente ser preparado (menu 9)."
    [prep.nada_a_fazer]="O ambiente já está preparado. Nada a fazer."
    [prep.concluido]="Ambiente preparado com sucesso."
    [prep.mais_itens]="Com os pacotes instalados, o debkit verificou de novo e falta mais isto:"
    [prep.falhou]="Falhou: %s"
    [prep.desfazendo]="Desfazendo o que o debkit já tinha feito..."
    [prep.mantidos_pacotes]="Os pacotes instalados foram mantidos: %s"
    [prep.impossivel_manual]="Há itens que o debkit não pode resolver sozinho (marcados com ✘). Corrija-os e execute o debkit novamente."
    [prep.impossivel_pacotes]="Instalação automática indisponível neste sistema. Instale manualmente: %s"
    [prep.apt_atualizando]="Atualizando a lista de pacotes (apt-get update)..."
    [prep.apt_update_falhou]="Não foi possível atualizar a lista de pacotes; tentando instalar mesmo assim."
    [prep.apt_instalando]="Instalando: %s (pode levar alguns minutos)..."
    [prep.apt_falhou]="A instalação falhou (sem internet? repositórios com erro?). Últimas linhas:"
    [prep.apt_conferencia]="Depois da instalação, o comando %s ainda não existe (pacote %s)."
    [prep.servico_falhou]="Não foi possível ativar o serviço %s (veja: systemctl status %s)."
    [prep.backup_sem_arquivo]="Backup impossível: %s não existe."
    [prep.backup_falhou]="Não foi possível fazer o backup de %s."
    [prep.backup_conferencia]="O backup de %s não ficou igual ao original."
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
       debkit <módulo> <comando> [argumentos] [--sim]

  (sem opção)    abre o menu interativo (precisa ser root)
  --verificar    verifica o ambiente, sem alterar nada (precisa ser root)
  --preparar     verifica e prepara o ambiente (pede confirmação)
  --desinstalar  remove o programa e o comando (com --tudo: também a
                 configuração, o log e os backups); usuários e
                 compartilhamentos ficam
  -h, --ajuda    mostra esta ajuda
  -v, --versao   mostra a versão

Comandos diretos (as mesmas ações do menu, para scripts e cron):
  debkit samba --ajuda    lista os comandos do módulo samba
  --sim                   responde \"s\" às confirmações (ex: em scripts)

Configuração: %s
Documentação: https://github.com/ThiagoCarrere/debkit"
)

declare -A MSG_en=(
    [geral.titulo]="debkit - Debian server administration"
    [geral.versao]="debkit %s"
    [geral.sim_nao]="(y/n)"
    [geral.escolha]="Choose an option: "
    [geral.enter_voltar]="Press Enter to go back..."
    [geral.opcao_invalida]="Invalid option: '%s'"
    [geral.sair]="Exit"
    [geral.voltar]="Back"
    [geral.em_construcao]="(features will be added in the next steps)"
    [geral.interrompido]="Interrupted. Nothing else was done."
    [erro.root]="This command must be run as root (e.g. sudo debkit)."
    [erro.uso]="Unknown option: '%s'. See: debkit --help"
    [cli.sim_resposta]="y (--yes)"
    [conf.e_ilegivel]="%s: not a readable file"
    [conf.e_inseguro]="%s: must belong to root, with no write for group/others (now: owner UID %s, permissions %s)"
    [conf.e_formato]="line %d: invalid format (use KEY=value)"
    [conf.e_valor]="line %d: invalid value for %s: '%s'"
    [conf.a_obsoleta]="line %d: the key '%s' is no longer used (%s): ignored; the line can be deleted"
    [conf.a_desconhecida]="line %d: unknown key '%s' (ignored)"
    [conf.obs_shares_conf]="debkit edits smb.conf directly"
    [conf.obs_prefixo_grupo]="debkit manages all regular groups"
    [conf.cabecalho]="%s - generated by debkit %s on %s"
    [conf.cabecalho_exemplo]="Description of each option: debkit.conf.exemplo (in /opt/debkit or in the debkit repository)."
    [conf.cabecalho_formato]="KEY=value format; the file is read, never executed."
    [amb.c_ausente]="missing or unreadable file"
    [amb.c_invalido]="invalid %s ('%s')"
    [amb.c_invertida]="%s_MIN greater than %s_MAX"
    [desi.titulo]="debkit - uninstall"
    [desi.vai]="The uninstall will remove:"
    [desi.fica]="Stays on the server:"
    [desi.r_link]="The command %s"
    [desi.r_programa]="The program in %s (installed by install.sh)"
    [desi.r_protecao]="The SSH protection (%s) and the group %s, which is empty (no file users)"
    [desi.r_conf]="The configuration %s"
    [desi.r_log]="The audit log %s (and the rotated ones) and its rotation rule (%s)"
    [desi.r_backups]="The debkit backups in %s and the smb.conf ones in %s"
    [desi.f_repositorio]="The program in %s: it is a repository (not copied by install.sh); delete it by hand if you want"
    [desi.f_protecao]="The SSH protection (%s) and the group %s: there are %d file user(s); without it they could log in over SSH"
    [desi.f_dados]="The configuration (%s), the audit log (%s) and the backups (%s, %s): use --all to remove them too"
    [desi.f_usuarios]="The users, groups and shares and smb.conf (the file server keeps working)"
    [desi.f_firewall]="The \"debkit: Samba\" firewall rules (if any): without them Samba would be blocked"
    [desi.pergunta]="Uninstall?"
    [desi.cancelado]="Cancelled. Nothing was done."
    [desi.nada]="Nothing from debkit to remove."
    [desi.feito]="Removed: %s"
    [desi.falhou]="Could not remove: %s"
    [desi.concluido]="debkit uninstalled."
    [desi.incompleto]="Incomplete uninstall (see above)."
    [desi.tudo_onde]="--all only applies with --uninstall"
    [inst.titulo]="debkit %s - installation"
    [inst.ajuda]="Usage: sudo ./install.sh [--yes] [--dry-run]

Installs (or updates) debkit in %s, with the command %s.
  --yes        answers \"y\" to the questions (installs and sets up the server)
  --dry-run    shows what it would do, without doing anything
  -h, --help   shows this help

The configuration (/etc/debkit), the log and the backups are not touched.
To uninstall: debkit --uninstall"
    [inst.opcao]="Unknown option: '%s' (see: ./install.sh --help)"
    [inst.destino_invalido]="Invalid installation folder: '%s' (full path, no spaces or ..)"
    [inst.dentro]="The installation folder %s and the folder being installed from %s cannot be one inside the other."
    [inst.destino_git]="%s is a debkit git repository: update it with \"git -C %s pull\" and run install.sh from there."
    [inst.destino_alheio]="%s already exists and is not a debkit installation: nothing was done."
    [inst.link_alheio]="%s already exists and does not point to %s: nothing was done."
    [inst.plano]="The installer will:"
    [inst.p_novo]="Copy debkit %s to %s (the program only: owned by root, no write for group/others)"
    [inst.p_atualizar]="Update %s (from %s to %s); the configuration in %s does not change"
    [inst.p_no_lugar]="Use the debkit already in %s (check that everything belongs to root, with no write for group/others)"
    [inst.p_link]="Create the command %s (link to %s)"
    [inst.link_ok]="The command %s already points to this installation."
    [inst.pergunta]="Install now?"
    [inst.cancelado]="Cancelled. Nothing was done."
    [inst.simulacao]="(dry run: nothing was done)"
    [inst.falhou]="The installation failed: %s. %s was left as it was."
    [inst.f_copiar]="could not copy the files"
    [inst.f_conferir]="the copy does not work (debkit --version)"
    [inst.f_trocar]="could not put the new copy in place"
    [inst.f_permissoes]="could not adjust owner and permissions"
    [inst.f_link]="could not create the command %s"
    [inst.ok]="debkit %s installed in %s. Command: %s"
    [inst.p_preparar]="Set up the server now (debkit --setup)?"
    [inst.depois]="Whenever you want: sudo debkit --setup (or open the menu: sudo debkit)"
    [cli.uso]="Incorrect usage: %s. See: %s"
    [cli.sim_onde]="--yes only applies to --setup and to module commands"
    [erro.conf]="Invalid configuration in %s:"
    [aviso.conf]="Configuration warnings in %s:"
    [erro.trava]="debkit is already in use by another session (PID %s). Try again when it finishes."
    [erro.trava_abrir]="Could not create the lock file %s."
    [menu.ambiente]="Environment: check and set up"
    [amb.titulo]="Server environment"
    [amb.grupo_sistema]="System"
    [amb.grupo_deps]="Essential dependencies"
    [amb.grupo_ssh]="SSH"
    [amb.grupo_dev]="Development (optional)"
    [amb.grupo_firewall]="Firewall"
    [amb.so_desconhecido]="Unknown system (%s missing or unreadable)"
    [amb.so_nao_debian]="Distribution outside the Debian family: untested; automatic installation unavailable"
    [amb.systemd_ok]="systemd running"
    [amb.systemd_falta]="systemd is not running (e.g. container): debkit needs it to manage services"
    [amb.contas_ok]="Regular accounts (%s): users UID %s-%s, groups GID %s-%s"
    [amb.contas_padrao]="%s: %s - using the Debian default (UID/GID 1000-60000) for regular accounts"
    [amb.deps_ok]="All %d essential dependencies present"
    [amb.dep_falta]="Missing command %s (package %s)"
    [amb.servico_ativo]="Service %s active"
    [amb.servico_parado]="Service %s stopped"
    [amb.servico_desabilitado]="Service %s does not start at boot"
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
    [prep.d_dir_conf]="Create the configuration folder %s"
    [prep.d_conf]="Create the configuration %s (default values)"
    [prep.d_conf_obsoletas]="Remove from %s the keys that are no longer used: %s (with backup; the rest of the file stays the same)"
    [prep.conf_obsoletas_conferencia]="After removing the old keys, other configuration values would change. Nothing was changed."
    [prep.conf_gravar_falhou]="Could not write %s. Nothing was changed."
    [prep.d_dir_backup]="Create the backup folder %s (root only)"
    [prep.d_log]="Create the audit log %s"
    [prep.d_log_rotacao]="Rotate the audit log %s monthly, keeping 24 compressed months (rule %s)"
    [prep.d_grupo]="Create the system group %s (debkit users)"
    [prep.pergunta]="Set up now?"
    [prep.recusado]="Nothing was changed. debkit will work in a limited way until the environment is set up (menu 9)."
    [prep.nada_a_fazer]="The environment is already set up. Nothing to do."
    [prep.concluido]="Environment set up successfully."
    [prep.mais_itens]="With the packages installed, debkit checked again and this is still missing:"
    [prep.falhou]="Failed: %s"
    [prep.desfazendo]="Undoing what debkit had already done..."
    [prep.mantidos_pacotes]="The installed packages were kept: %s"
    [prep.impossivel_manual]="Some items cannot be fixed by debkit (marked with ✘). Fix them and run debkit again."
    [prep.impossivel_pacotes]="Automatic installation is not available on this system. Install manually: %s"
    [prep.apt_atualizando]="Updating the package list (apt-get update)..."
    [prep.apt_update_falhou]="Could not update the package list; trying to install anyway."
    [prep.apt_instalando]="Installing: %s (this may take a few minutes)..."
    [prep.apt_falhou]="Installation failed (no internet? broken repositories?). Last lines:"
    [prep.apt_conferencia]="After installation, the command %s still does not exist (package %s)."
    [prep.servico_falhou]="Could not activate the service %s (see: systemctl status %s)."
    [prep.backup_sem_arquivo]="Backup impossible: %s does not exist."
    [prep.backup_falhou]="Could not back up %s."
    [prep.backup_conferencia]="The backup of %s does not match the original."
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
       debkit <module> <command> [arguments] [--yes]

  (no option)    opens the interactive menu (requires root)
  --check        checks the environment without changing anything (requires root)
  --setup        checks and sets up the environment (asks for confirmation)
  --uninstall    removes the program and the command (with --all: also the
                 configuration, the log and the backups); users and shares
                 stay
  -h, --help     shows this help
  -v, --version  shows the version

Direct commands (the same actions as the menu, for scripts and cron):
  debkit samba --help     lists the commands of the samba module
  --yes                   answers \"y\" to the confirmations (e.g. in scripts)

Configuration: %s
Documentation: https://github.com/ThiagoCarrere/debkit"
)

# Idioma "auto" (o padrão): o do sistema, na ordem do gettext - LANGUAGE
# (se o idioma não for C/POSIX), LC_ALL, LC_MESSAGES, LANG: português
# (pt...) ou, qualquer outro, inglês. O sudo do Debian mantém essas
# variáveis. Deixa o resultado em DEBKIT_IDIOMA_EF (sem subshell: o t() é
# chamado o tempo todo).
debkit_idioma_efetivo() {
    local loc="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" l
    case "${DEBKIT_IDIOMA:-auto}" in
        pt_BR|en) DEBKIT_IDIOMA_EF="$DEBKIT_IDIOMA"; return ;;
    esac
    l="$loc"
    if [ -n "${LANGUAGE:-}" ] && [ "$loc" != "C" ] && [ "$loc" != "POSIX" ]; then l="${LANGUAGE%%:*}"; fi
    if [[ "$l" == pt* ]]; then DEBKIT_IDIOMA_EF=pt_BR; else DEBKIT_IDIOMA_EF=en; fi
}

# Imprime a mensagem <chave> formatada com os argumentos (sem quebra de linha)
t() {
    local chave="$1" formato idioma
    shift
    debkit_idioma_efetivo; idioma="$DEBKIT_IDIOMA_EF"
    if [ "$idioma" == "en" ] && [ -n "${MSG_en[$chave]+x}" ]; then
        formato="${MSG_en[$chave]}"
    elif [ -n "${MSG_pt_BR[$chave]+x}" ]; then
        formato="${MSG_pt_BR[$chave]}"
    else
        formato="$chave"
    fi
    # Argumentos a mais que os "%" do formato fariam o printf repetir a frase
    # inteira (em outro idioma a frase pode usar menos): sobram, são ignorados
    local so="${formato//%%/}"
    so="${so//[^%]/}"
    [ $# -gt "${#so}" ] && set -- "${@:1:${#so}}"
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

# Título de tela: limpa a tela (se for terminal) e mostra o título. Nos
# comandos diretos (DEBKIT_CLI=1) não há tela: só o título, sem limpar.
titulo() {
    if [ "${DEBKIT_CLI:-0}" -eq 1 ]; then printf '%s%s%s\n\n' "$C_NEGRITO" "$*" "$C_RESET"; return 0; fi
    [ -t 1 ] && clear
    printf '%s%s%s\n' "$C_CIANO" "$DEBKIT_LINHA" "$C_RESET"
    printf '%s  %s%s\n' "$C_NEGRITO" "$*" "$C_RESET"
    printf '%s%s%s\n' "$C_CIANO" "$DEBKIT_LINHA" "$C_RESET"
}

# ════════════════════════════════════════════════════════════════════════════
# 5. UTILITÁRIOS
# ════════════════════════════════════════════════════════════════════════════

# Espera Enter antes de voltar ao menu (nos comandos diretos não há menu)
pausar() {
    [ "${DEBKIT_CLI:-0}" -eq 1 ] && return 0
    echo ""
    read -rp "$(t geral.enter_voltar)" _ || true
}

# Pergunta sim/não. Retorna 0 só para s/S/y/Y (fim da entrada = não).
# Com --sim nos comandos diretos (DEBKIT_SIM=1) a resposta é "s" (e aparece).
confirmar() {
    local resp
    if [ "${DEBKIT_SIM:-0}" -eq 1 ]; then printf '%s %s: %s\n' "$1" "$(t geral.sim_nao)" "$(t cli.sim_resposta)"; return 0; fi
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
# Descobre o que existe na máquina: sistema, systemd, dependências, SSH,
# firewall e o que cada módulo verifica (ex: Samba). Nada aqui altera o
# sistema. O resultado alimenta o relatório (debkit --verificar / menu
# Ambiente) e a preparação.

# Arquivos do sistema consultados (variáveis para os testes poderem simular)
DEBKIT_ARQ_OS_RELEASE="${DEBKIT_ARQ_OS_RELEASE:-/etc/os-release}"
DEBKIT_ARQ_SSHD_CONFIG="${DEBKIT_ARQ_SSHD_CONFIG:-/etc/ssh/sshd_config}"
DEBKIT_ARQ_LOGIN_DEFS="${DEBKIT_ARQ_LOGIN_DEFS:-/etc/login.defs}"
DEBKIT_DIR_SYSTEMD="${DEBKIT_DIR_SYSTEMD:-/run/systemd/system}"

# Tabela de dependências - ÚNICO ponto específico da distribuição (os
# módulos acrescentam as suas ao serem carregados).
# comando | tipo | pacote no Debian
#   essencial      : sem ele o debkit não funciona (a preparação oferece instalar)
#   condicional    : só necessário se existir (ex: SSH -> proteção)
#   desenvolvimento: só para quem desenvolve/testa o debkit; nunca instalado
DEBKIT_DEPENDENCIAS=(
    "useradd|essencial|passwd"
    "usermod|essencial|passwd"
    "userdel|essencial|passwd"
    "groupadd|essencial|passwd"
    "groupdel|essencial|passwd"
    "gpasswd|essencial|passwd"
    "chpasswd|essencial|passwd"
    "flock|essencial|util-linux"
    "unshare|essencial|util-linux"
    "getent|essencial|libc-bin"
    "awk|essencial|mawk"
    "sed|essencial|sed"
    "grep|essencial|grep"
    "stat|essencial|coreutils"
    "mktemp|essencial|coreutils"
    "realpath|essencial|coreutils"
    "logrotate|essencial|logrotate"
    "systemctl|essencial|systemd"
    "sshd|condicional|openssh-server"
    "shellcheck|desenvolvimento|shellcheck"
)

# Verifica se um comando existe (função separada para os testes simularem)
debkit_tem_comando() { command -v "$1" >/dev/null 2>&1; }

# O pacote (Debian) está instalado? (função separada para os testes
# simularem; DEBKIT_DPKG_ADMIN = base do dpkg, para o sandbox)
DEBKIT_DPKG_ADMIN="${DEBKIT_DPKG_ADMIN:-/var/lib/dpkg}"
debkit_pacote_instalado() { dpkg-query --admindir="$DEBKIT_DPKG_ADMIN" -W -f='${db:Status-Abbrev}' -- "$1" 2>/dev/null | grep -q '^ii'; }

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

# sshd -t / -T. Eles exigem a pasta de separação de privilégios
# (/run/sshd), que o systemd só cria com o serviço do SSH no ar: com o SSH
# parado (ou desligado no boot) falham com "Missing privilege separation
# directory" - e a configuração pareceria inválida. Nesse caso o sshd roda
# num espaço de montagem só dele, com um /run vazio (tmpfs) e a pasta: nada
# muda no sistema. Sem como fazer isso (ex: container sem permissão), roda
# direto.
DEBKIT_SSHD_PRIVSEP="${DEBKIT_SSHD_PRIVSEP:-/run/sshd}"
debkit_sshd() {
    local rc
    if [ ! -d "$DEBKIT_SSHD_PRIVSEP" ] && [ "$(type -t sshd)" == "file" ] && debkit_tem_comando unshare \
       && unshare -m --propagation private -- true 2>/dev/null; then
        # 254 = não deu para montar (o sshd só sai com 0 ou 255)
        # shellcheck disable=SC2016  # expandido pelo sh de dentro
        unshare -m --propagation private -- sh -c \
            'mount -t tmpfs -o mode=755 debkit "$1" 2>/dev/null && mkdir -m 755 -p "$2" || exit 254; shift 2; exec sshd "$@"' \
            sh "$(dirname -- "$DEBKIT_SSHD_PRIVSEP")" "$DEBKIT_SSHD_PRIVSEP" "$@"
        rc=$?
        [ "$rc" -ne 254 ] && return "$rc"
    fi
    sshd "$@"
}

# A proteção está EFETIVA? Consulta a configuração geral em vigor (sshd -T),
# não só se o arquivo existe: o grupo precisa estar em "denygroups".
debkit_ssh_protecao_ativa() {
    debkit_sshd -T 2>/dev/null | awk -v g="$DEBKIT_GRUPO_USUARIOS" \
        '$1 == "denygroups" { for (i = 2; i <= NF; i++) if ($i == g) achou = 1 } END { exit !achou }'
}

# ── Contas comuns (faixas do /etc/login.defs) ───────────────────────────────
# O debkit gerencia só usuários e grupos comuns: UID entre UID_MIN e UID_MAX,
# GID entre GID_MIN e GID_MAX. Os de sistema (root, www-data, nobody...)
# ficam de fora. O arquivo é lido sem ser executado; só números decimais são
# aceitos (sem zero à esquerda: o login.defs aceitaria octal/hexadecimal, e
# interpretar diferente dele seria pior do que usar o padrão). Se algo
# estiver ausente ou inválido, vale o padrão do Debian (1000-60000) e o
# motivo fica em DEBKIT_CONTAS_ERRO. Nunca considera o UID/GID 0 comum.
DEBKIT_CONTAS_PADRAO_MIN=1000
DEBKIT_CONTAS_PADRAO_MAX=60000

# shellcheck disable=SC2034  # DEBKIT_UID_*/DEBKIT_GID_* via printf -v e usados pelos módulos
debkit_ler_login_defs() {
    local chave valor resto tipo min max
    local -A lido=()
    DEBKIT_UID_MIN=$DEBKIT_CONTAS_PADRAO_MIN; DEBKIT_UID_MAX=$DEBKIT_CONTAS_PADRAO_MAX
    DEBKIT_GID_MIN=$DEBKIT_CONTAS_PADRAO_MIN; DEBKIT_GID_MAX=$DEBKIT_CONTAS_PADRAO_MAX
    DEBKIT_CONTAS_ERRO=""
    if [ ! -r "$DEBKIT_ARQ_LOGIN_DEFS" ]; then
        DEBKIT_CONTAS_ERRO="$(t amb.c_ausente)"
        return 1
    fi
    # Como no login.defs, a última ocorrência de uma chave é a que vale
    while read -r chave valor resto || [ -n "$chave" ]; do
        case "$chave" in
            UID_MIN|UID_MAX|GID_MIN|GID_MAX) ;;
            *) continue ;;
        esac
        valor="${valor%$'\r'}"
        if [[ "$valor" =~ ^\"(.*)\"$ ]]; then valor="${BASH_REMATCH[1]}"; fi
        lido[$chave]="$valor"
    done < "$DEBKIT_ARQ_LOGIN_DEFS"
    for chave in UID_MIN UID_MAX GID_MIN GID_MAX; do
        [ -n "${lido[$chave]+x}" ] || continue
        valor="${lido[$chave]}"
        if [[ "$valor" =~ ^[1-9][0-9]{0,9}$ ]]; then
            printf -v "DEBKIT_$chave" '%s' "$valor"
        else
            DEBKIT_CONTAS_ERRO+="${DEBKIT_CONTAS_ERRO:+; }$(t amb.c_invalido "$chave" "$valor")"
        fi
    done
    # Faixa invertida: volta ao padrão só daquele tipo
    for tipo in UID GID; do
        min="DEBKIT_${tipo}_MIN"; max="DEBKIT_${tipo}_MAX"
        if [ "${!min}" -gt "${!max}" ]; then
            DEBKIT_CONTAS_ERRO+="${DEBKIT_CONTAS_ERRO:+; }$(t amb.c_invertida "$tipo" "$tipo")"
            printf -v "$min" '%s' "$DEBKIT_CONTAS_PADRAO_MIN"
            printf -v "$max" '%s' "$DEBKIT_CONTAS_PADRAO_MAX"
        fi
    done
    [ -z "$DEBKIT_CONTAS_ERRO" ]
}

# UID/GID dentro da faixa das contas comuns? (usar depois de debkit_ler_login_defs)
debkit_uid_comum() { [[ "$1" =~ ^[0-9]{1,10}$ ]] && (( 10#$1 != 0 && 10#$1 >= DEBKIT_UID_MIN && 10#$1 <= DEBKIT_UID_MAX )); }
debkit_gid_comum() { [[ "$1" =~ ^[0-9]{1,10}$ ]] && (( 10#$1 != 0 && 10#$1 >= DEBKIT_GID_MIN && 10#$1 <= DEBKIT_GID_MAX )); }

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
# Os itens de cada módulo vêm do gancho "verificar" (grupo com o nome do
# módulo), logo depois das dependências.
# Além de DEBKIT_VERIF / DEBKIT_PACOTES_FALTANDO / DEBKIT_BLOQUEIOS, deixa prontos
# para a preparação e a proteção SSH:
#   DEBKIT_UID_* / DEBKIT_GID_*     faixas das contas comuns (login.defs)
#   DEBKIT_SVC_SSH                  nome do serviço SSH (vazio se não encontrado)
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
    local dep cmd tipo pacote presentes=0 total=0 senha_ssh
    DEBKIT_VERIF=(); DEBKIT_PACOTES_FALTANDO=(); DEBKIT_BLOQUEIOS=0; DEBKIT_BLOQ_MANUAL=0
    DEBKIT_SVC_SSH=""; DEBKIT_TEM_SSH=0; DEBKIT_SSH_DROPIN_OK=0; DEBKIT_SSH_PROTEGIDO=0
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
    if debkit_ler_login_defs; then
        debkit_verif_add sistema ok "$(t amb.contas_ok "$DEBKIT_ARQ_LOGIN_DEFS" "$DEBKIT_UID_MIN" "$DEBKIT_UID_MAX" "$DEBKIT_GID_MIN" "$DEBKIT_GID_MAX")"
    else
        debkit_verif_add sistema aviso "$(t amb.contas_padrao "$DEBKIT_ARQ_LOGIN_DEFS" "$DEBKIT_CONTAS_ERRO")"
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

    # ── Módulos (ex: Samba) ──
    debkit_modulos_gancho verificar

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
        senha_ssh=$(debkit_sshd -T 2>/dev/null | awk '$1 == "passwordauthentication" {print $2}')
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
    for grupo in sistema deps "${DEBKIT_MODULOS[@]}" ssh firewall dev; do
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
# Resolve o que a detecção encontrou: instala pacotes (Debian), cria a
# estrutura do debkit, aplica a proteção SSH, libera o firewall e o que os
# módulos pedirem (gancho "plano"; ex: ligar o Samba). Sempre com plano
# mostrado antes e UMA confirmação. Se um passo falhar, desfaz o que é do
# debkit (arquivos, pastas, grupo...); pacotes instalados NÃO são
# desinstalados (desinstalar no meio de uma falha arriscaria quebrar mais
# do que consertar) - e isso é informado.

DEBKIT_APT="${DEBKIT_APT:-apt-get}"    # variável para os testes poderem simular

# ── Backups ─────────────────────────────────────────────────────────────────
# debkit_backup <arquivo> [pasta]
# Copia o arquivo para a pasta (padrão: DEBKIT_BACKUP_DIR; criada com 700 se
# não existir), cópia 600, com o nome <arquivo>.dd-mm-aaaa-hh-mm-ss (ex:
# smb.conf.15-10-2026-17-42-05). Dois backups no mesmo segundo: o segundo
# ganha o sufixo -2 (depois -3...), nunca sobrescreve. O sufixo é sempre
# maior que o maior já usado naquele segundo (um nome liberado pela rotação
# não é reaproveitado: ficaria "mais antigo" que os outros). Confere a cópia
# e só então apaga as mais antigas, mantendo DEBKIT_BACKUP_MANTER (a cópia
# nova nunca é apagada). Imprime o caminho do backup.
debkit_backup() {
    local arquivo="$1" pasta="${2:-$DEBKIT_BACKUP_DIR}" nome carimbo destino arq n maior=0
    if [ ! -f "$arquivo" ]; then
        msg_erro "$(t prep.backup_sem_arquivo "$arquivo")"
        return 1
    fi
    if ! ( umask 077; mkdir -p -- "$pasta" ) || ! chmod 700 -- "$pasta"; then
        msg_erro "$(t prep.backup_falhou "$arquivo")"
        return 1
    fi
    nome=$(basename -- "$arquivo")
    carimbo=$(date +%d-%m-%Y-%H-%M-%S)
    for arq in "$pasta/$nome.$carimbo" "$pasta/$nome.$carimbo"-*; do
        [ -e "$arq" ] || [ -L "$arq" ] || continue
        n="${arq##*/"$nome.$carimbo"}"
        if [ -z "$n" ]; then
            n=1
        elif [[ "$n" =~ ^-([0-9]{1,6})$ ]]; then
            n=$((10#${BASH_REMATCH[1]}))
        else
            continue
        fi
        [ "$n" -gt "$maior" ] && maior=$n
    done
    if [ "$maior" -eq 0 ]; then
        destino="$pasta/$nome.$carimbo"
    else
        destino="$pasta/$nome.$carimbo-$((maior + 1))"
    fi
    if [ -e "$destino" ] || [ -L "$destino" ] \
       || ! cp -p -- "$arquivo" "$destino" || ! chmod 600 -- "$destino"; then
        rm -f -- "$destino"
        msg_erro "$(t prep.backup_falhou "$arquivo")"
        return 1
    fi
    if ! cmp -s -- "$arquivo" "$destino"; then
        rm -f -- "$destino"
        msg_erro "$(t prep.backup_conferencia "$arquivo")"
        return 1
    fi
    debkit_backup_limpar "$pasta" "$nome" "$destino"
    echo "$destino"
}

# debkit_backup_limpar <pasta> <nome> [proteger]
# Apaga os backups mais antigos de <nome>, mantendo DEBKIT_BACKUP_MANTER
# (contando o arquivo [proteger], que nunca é apagado - mesmo se o relógio
# tiver voltado e ele parecer mais antigo). Só considera arquivos com o
# padrão de nome do debkit (<nome>.dd-mm-aaaa-hh-mm-ss[-N]); qualquer outro
# arquivo da pasta é ignorado. A ordem é pela data do nome (não alfabética:
# 01-01-2026 vem depois de 31-12-2025; -10 depois de -9).
debkit_backup_limpar() {
    local pasta="$1" nome="$2" proteger="${3:-}" manter="${DEBKIT_BACKUP_MANTER:-30}" arq resto total=0 apagar
    local -a lista=()
    for arq in "$pasta/$nome".*; do
        if [ ! -f "$arq" ] || [ -L "$arq" ]; then continue; fi
        resto="${arq##*/}"
        resto="${resto#"$nome".}"
        [[ "$resto" =~ ^([0-9]{2})-([0-9]{2})-([0-9]{4})-([0-9]{2})-([0-9]{2})-([0-9]{2})(-([2-9]|[1-9][0-9]{1,5}))?$ ]] || continue
        total=$((total + 1))
        [ "$arq" == "$proteger" ] && continue
        # chave ordenável: aaaammddhhmmss-sufixo(6 dígitos)
        lista+=("$(printf '%s%s%s%s%s%s-%06d' "${BASH_REMATCH[3]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}" \
                   "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}" "$((10#${BASH_REMATCH[8]:-1}))") $arq")
    done
    apagar=$((total - manter))
    [ "$apagar" -gt 0 ] || return 0
    printf '%s\n' "${lista[@]}" | sort | head -n "$apagar" | cut -d' ' -f2- \
        | while IFS= read -r arq; do rm -f -- "$arq"; done
}

# ── Peças da estrutura do debkit ───────────────────────────────────────────────
debkit_dir_conf() { dirname -- "$DEBKIT_CONF_ARQUIVO"; }

# ── Plano ───────────────────────────────────────────────────────────────────
# DEBKIT_PLANO: ids das ações, na ordem de execução.
# DEBKIT_PLANO_IMPOSSIVEL: motivo, se algo não pode ser resolvido pelo debkit.
# Usar depois de debkit_verificar_ambiente.
# Cada ação <id> tem debkit_acao_<id> (executa e confere) e, se for de um
# módulo, debkit_descrever_<id> (texto do plano) e, se houver o que desfazer,
# debkit_desfazer_<id>.
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
    # Ações dos módulos (ex: ligar o Samba)
    debkit_modulos_gancho plano
    [ -d "$(debkit_dir_conf)" ]      || DEBKIT_PLANO+=(dir_conf)
    if [ ! -f "$DEBKIT_CONF_ARQUIVO" ]; then
        DEBKIT_PLANO+=(conf)
    elif [ -n "$(debkit_conf_obsoletas_no_arquivo)" ]; then
        DEBKIT_PLANO+=(conf_obsoletas)
    fi
    [ -d "$DEBKIT_BACKUP_DIR" ]      || DEBKIT_PLANO+=(dir_backup)
    [ -f "$DEBKIT_LOG" ]             || DEBKIT_PLANO+=(log)
    debkit_log_rotacao_ok            || DEBKIT_PLANO+=(log_rotacao)
    getent group "$DEBKIT_GRUPO_USUARIOS" >/dev/null 2>&1 || DEBKIT_PLANO+=(grupo)
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
        dir_conf)      t prep.d_dir_conf "$(debkit_dir_conf)" ;;
        conf)          t prep.d_conf "$DEBKIT_CONF_ARQUIVO" ;;
        conf_obsoletas) t prep.d_conf_obsoletas "$DEBKIT_CONF_ARQUIVO" "$(debkit_conf_obsoletas_no_arquivo)" ;;
        dir_backup)    t prep.d_dir_backup "$DEBKIT_BACKUP_DIR" ;;
        log)           t prep.d_log "$DEBKIT_LOG" ;;
        log_rotacao)   t prep.d_log_rotacao "$DEBKIT_LOG" "$DEBKIT_LOG_LOGROTATE" ;;
        grupo)         t prep.d_grupo "$DEBKIT_GRUPO_USUARIOS" ;;
        ssh_protecao)  t prep.d_ssh_protecao "$DEBKIT_SSH_DROPIN" "$DEBKIT_GRUPO_USUARIOS" ;;
        firewall)      t prep.d_firewall "$DEBKIT_FW_PORTA" "$DEBKIT_FW_TIPO" "$(debkit_redes_locais | paste -sd, - | sed 's/,/, /g')" ;;
        *)             declare -F "debkit_descrever_$1" >/dev/null && "debkit_descrever_$1" ;;
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
    # instalação anterior), mantém a existente em vez de parar perguntando.
    # --no-install-recommends: só o necessário (os "recomendados" do samba
    # trazem o samba-ad-dc e o winbind, que entra no PAM do sistema)
    if ! DEBIAN_FRONTEND=noninteractive "$DEBKIT_APT" -o DPkg::Lock::Timeout=120 \
            -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
            install -y --no-install-recommends "${DEBKIT_PACOTES_FALTANDO[@]}" >>"$registro" 2>&1; then
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

debkit_acao_dir_conf()   { ( umask 022; mkdir -p -- "$(debkit_dir_conf)" ) && chmod 755 -- "$(debkit_dir_conf)"; }
debkit_acao_dir_backup() { ( umask 077; mkdir -p -- "$DEBKIT_BACKUP_DIR" ) && chmod 700 -- "$DEBKIT_BACKUP_DIR"; }
debkit_acao_log()        { ( umask 027; : >> "$DEBKIT_LOG" ) && chmod 640 -- "$DEBKIT_LOG"; }
debkit_acao_grupo()      { groupadd --system -- "$DEBKIT_GRUPO_USUARIOS" && getent group "$DEBKIT_GRUPO_USUARIOS" >/dev/null; }

debkit_acao_conf() {
    local chave var cabecalho
    cabecalho=$(t conf.cabecalho "$DEBKIT_CONF_ARQUIVO" "$DEBKIT_VERSAO" "$(date '+%Y-%m-%d %H:%M')")
    {
        printf '# %s\n' "$cabecalho"
        printf '# %s\n' "$(t conf.cabecalho_exemplo)"
        printf '# %s\n' "$(t conf.cabecalho_formato)"
        echo ""
        for chave in "${DEBKIT_CONF_ORDEM[@]}"; do
            var="DEBKIT_$chave"
            printf '%s=%s\n' "$chave" "${!var}"
        done
    } > "$DEBKIT_CONF_ARQUIVO" && chmod 644 -- "$DEBKIT_CONF_ARQUIVO" && chown 0:0 -- "$DEBKIT_CONF_ARQUIVO" \
        && debkit_conf_carregar "$DEBKIT_CONF_ARQUIVO"
}

# ── Chaves antigas no debkit.conf ───────────────────────────────────────────
# Mesma regra de leitura de debkit_conf_carregar: linha "CHAVE=valor" (com
# espaços opcionais) cuja chave está em DEBKIT_CONF_OBSOLETA. Comentários
# ("# SHARES_CONF=...") não contam.
debkit_conf_linha_obsoleta() {
    [[ "$1" =~ ^[[:space:]]*([A-Z_]+)[[:space:]]*= ]] && [ -n "${DEBKIT_CONF_OBSOLETA[${BASH_REMATCH[1]}]+x}" ]
}

# Imprime as chaves antigas presentes no debkit.conf (ou no arquivo
# indicado), na ordem do arquivo, sem repetir, separadas por ", "; nada se
# não houver.
debkit_conf_obsoletas_no_arquivo() {
    local arq="${1:-$DEBKIT_CONF_ARQUIVO}" linha chaves=""
    [ -f "$arq" ] && [ -r "$arq" ] || return 0
    while IFS= read -r linha || [ -n "$linha" ]; do
        if debkit_conf_linha_obsoleta "$linha" && [[ ",$chaves," != *",${BASH_REMATCH[1]},"* ]]; then
            chaves+="${chaves:+,}${BASH_REMATCH[1]}"
        fi
    done < "$arq"
    printf '%s' "${chaves//,/, }"
}

# Valores em vigor (todas as chaves conhecidas) de um debkit.conf, uma por
# linha, em ordem: serve para conferir que só as chaves antigas saíram.
debkit_conf_valores() {
    (
        local chave var
        debkit_conf_carregar "$1" >/dev/null 2>&1 || echo "ERRO $DEBKIT_CONF_ERROS"
        for chave in $(printf '%s\n' "${!DEBKIT_CONF_TIPO[@]}" | sort); do
            var="DEBKIT_$chave"
            printf '%s=%s\n' "$chave" "${!var}"
        done
    )
}

# Tira do debkit.conf as linhas das chaves antigas, sem mexer no resto
# (comentários, valores próprios, ordem). Backup em BACKUP_DIR, arquivo novo
# num temporário na mesma pasta, conferência (mesmos valores em vigor e
# nenhuma chave antiga) e troca atômica mantendo dono/permissões.
debkit_acao_conf_obsoletas() {
    local arq="$DEBKIT_CONF_ARQUIVO" novo linha antes
    DEBKIT_BACKUP_CONF=""; DEBKIT_CONF_TROCADO=0
    DEBKIT_BACKUP_CONF=$(debkit_backup "$arq") || return 1
    if ! novo=$(umask 077; mktemp -- "$(dirname -- "$arq")/.debkit.conf.XXXXXX"); then
        msg_erro "$(t prep.conf_gravar_falhou "$arq")"
        return 1
    fi
    DEBKIT_TEMPORARIOS+=("$novo")
    while IFS= read -r linha || [ -n "$linha" ]; do
        debkit_conf_linha_obsoleta "$linha" || printf '%s\n' "$linha"
    done < "$arq" > "$novo"
    antes=$(debkit_conf_valores "$arq")
    if [ "$(debkit_conf_valores "$novo")" != "$antes" ] \
       || [ -n "$(debkit_conf_obsoletas_no_arquivo "$novo")" ]; then
        rm -f -- "$novo"
        msg_erro "$(t prep.conf_obsoletas_conferencia)"
        return 1
    fi
    if ! chown --reference="$arq" -- "$novo" || ! chmod --reference="$arq" -- "$novo" || ! mv -f -- "$novo" "$arq"; then
        rm -f -- "$novo"
        msg_erro "$(t prep.conf_gravar_falhou "$arq")"
        return 1
    fi
    DEBKIT_CONF_TROCADO=1
    debkit_conf_carregar "$arq" >/dev/null
}

# debkit_conf_definir <CHAVE> <valor>
# Grava uma chave no debkit.conf (substitui a linha da chave ou acrescenta
# no fim), sem mexer no resto: backup em BACKUP_DIR, arquivo novo num
# temporário na mesma pasta, conferência (só essa chave mudou nos valores em
# vigor), troca atômica mantendo dono/permissões. Atualiza DEBKIT_<CHAVE>.
# Para desfazer: debkit_conf_restaurar.
debkit_conf_definir() {
    local chave="$1" valor="$2" arq="$DEBKIT_CONF_ARQUIVO" novo linha achou=0 antes esperado
    DEBKIT_BACKUP_CONF=""; DEBKIT_CONF_TROCADO=0
    if [ -z "${DEBKIT_CONF_TIPO[$chave]+x}" ] || ! debkit_conf_valor_valido "${DEBKIT_CONF_TIPO[$chave]}" "$valor"; then
        msg_erro "$(t prep.conf_gravar_falhou "$arq")"
        return 1
    fi
    if [ ! -f "$arq" ]; then
        msg_erro "$(t prep.conf_gravar_falhou "$arq")"
        return 1
    fi
    DEBKIT_BACKUP_CONF=$(debkit_backup "$arq") || return 1
    if ! novo=$(umask 077; mktemp -- "$(dirname -- "$arq")/.debkit.conf.XXXXXX"); then
        msg_erro "$(t prep.conf_gravar_falhou "$arq")"
        return 1
    fi
    DEBKIT_TEMPORARIOS+=("$novo")
    while IFS= read -r linha || [ -n "$linha" ]; do
        if [[ "$linha" =~ ^[[:space:]]*([A-Z_]+)[[:space:]]*= ]] && [ "${BASH_REMATCH[1]}" == "$chave" ]; then
            [ "$achou" -eq 0 ] && printf '%s=%s\n' "$chave" "$valor"
            achou=1
            continue
        fi
        printf '%s\n' "$linha"
    done < "$arq" > "$novo"
    [ "$achou" -eq 1 ] || printf '%s=%s\n' "$chave" "$valor" >> "$novo"
    antes=$(debkit_conf_valores "$arq")
    esperado=$(printf '%s\n' "$antes" | sed "s|^$chave=.*|$chave=$valor|")
    if [ "$(debkit_conf_valores "$novo")" != "$esperado" ]; then
        rm -f -- "$novo"
        msg_erro "$(t prep.conf_gravar_falhou "$arq")"
        return 1
    fi
    if ! chown --reference="$arq" -- "$novo" || ! chmod --reference="$arq" -- "$novo" || ! mv -f -- "$novo" "$arq"; then
        rm -f -- "$novo"
        msg_erro "$(t prep.conf_gravar_falhou "$arq")"
        return 1
    fi
    DEBKIT_CONF_TROCADO=1
    printf -v "DEBKIT_$chave" '%s' "$valor"
    debkit_auditar conf_definir "chave=$chave valor=$valor"
}

# Volta o debkit.conf do backup, se a ação o trocou (troca atômica, mesmo
# dono/permissões)
debkit_conf_restaurar() {
    local arq="$DEBKIT_CONF_ARQUIVO" novo=""
    [ "${DEBKIT_CONF_TROCADO:-0}" -eq 1 ] || return 0
    if [ -f "$DEBKIT_BACKUP_CONF" ] \
       && novo=$(umask 077; mktemp -- "$(dirname -- "$arq")/.debkit.conf.XXXXXX") \
       && cp -- "$DEBKIT_BACKUP_CONF" "$novo" \
       && chown --reference="$arq" -- "$novo" && chmod --reference="$arq" -- "$novo" \
       && mv -f -- "$novo" "$arq"; then
        DEBKIT_CONF_TROCADO=0
        debkit_conf_carregar "$arq" >/dev/null
        return 0
    fi
    [ -n "$novo" ] && rm -f -- "$novo"
    return 1
}

# ── Rotação de logs (logrotate) ─────────────────────────────────────────────
# As regras em /etc/logrotate.d são arquivos do debkit: se mudarem, a
# preparação recria (com backup da anterior). Não precisam de postrotate:
# o debkit abre o log a cada linha gravada (e o Samba, a cada conexão).

# debkit_logrotate_ok <regra> <função que imprime o conteúdo>
debkit_logrotate_ok() { [ -f "$1" ] && cmp -s <("$2") "$1"; }

# debkit_logrotate_gravar <regra> <função que imprime o conteúdo>
# Grava a regra (backup se já existia; troca atômica) e confere com o
# "logrotate -d". Guarda em DEBKIT_LOGROTATE_ANTES[<regra>] o backup (ou
# "novo") para debkit_logrotate_desfazer.
declare -A DEBKIT_LOGROTATE_ANTES=()
debkit_logrotate_gravar() {
    local regra="$1" conteudo="$2" tmp antes
    DEBKIT_LOGROTATE_ANTES[$regra]=""
    debkit_logrotate_ok "$regra" "$conteudo" && return 0
    if [ -e "$regra" ]; then
        antes=$(debkit_backup "$regra") || return 1
    else
        antes=novo
    fi
    DEBKIT_LOGROTATE_ANTES[$regra]="$antes"
    tmp=$(umask 022; mktemp -- "$(dirname -- "$regra")/.debkit-logrotate.XXXXXX") || return 1
    DEBKIT_TEMPORARIOS+=("$tmp")
    if ! { "$conteudo" > "$tmp" && chmod 644 -- "$tmp" && mv -f -- "$tmp" "$regra"; }; then
        rm -f -- "$tmp"; return 1
    fi
    debkit_logrotate_ok "$regra" "$conteudo" && logrotate -d -- "$regra" >/dev/null 2>&1
}

# Esquece o estado de uma gravação anterior (início de uma ação que pode
# falhar antes de gravar a regra: o desfazer não mexe nela)
debkit_logrotate_inicio() { DEBKIT_LOGROTATE_ANTES[$1]=""; }

# Volta a regra como estava antes de debkit_logrotate_gravar (apaga a nova
# ou repõe a de antes)
debkit_logrotate_desfazer() {
    local regra="$1" antes="${DEBKIT_LOGROTATE_ANTES[$1]:-}"
    if [ "$antes" == "novo" ]; then
        rm -f -- "$regra"
    elif [ -n "$antes" ]; then
        cp -- "$antes" "$regra" && chmod 644 -- "$regra"
    fi
    DEBKIT_LOGROTATE_ANTES[$regra]=""
}

# Regra do log de auditoria do debkit: uma linha por ação, então é pequeno;
# mensal, 24 meses (a consulta à auditoria lê também os girados .N/.N.gz)
debkit_log_rotacao_conteudo() {
    printf '# debkit: rotação do log de auditoria do debkit (arquivo do debkit; a preparação recria se mudar)\n'
    printf '%s {\n    monthly\n    rotate 24\n    compress\n    delaycompress\n    missingok\n    notifempty\n    create 0640 root root\n}\n' "$DEBKIT_LOG"
}
debkit_log_rotacao_ok() { debkit_logrotate_ok "$DEBKIT_LOG_LOGROTATE" debkit_log_rotacao_conteudo; }
debkit_acao_log_rotacao() { debkit_logrotate_gravar "$DEBKIT_LOG_LOGROTATE" debkit_log_rotacao_conteudo; }

# ── Proteção SSH ────────────────────────────────────────────────────────────
# A marca identifica o arquivo como do debkit. NÃO mudar o texto: servidores
# já preparados têm o arquivo com esta marca (mesmo com o nome antigo
# "Gerenciador Samba"), e sem ela o debkit não o reconheceria como seu.
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

    if ! erros=$(debkit_sshd -t 2>&1); then
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
        # Sem -p: o backup é 600; o arquivo do SSH volta com 644
        cp -- "$DEBKIT_BACKUP_SSHDROPIN" "$DEBKIT_SSH_DROPIN" && chmod 644 -- "$DEBKIT_SSH_DROPIN"
    elif [ -f "$DEBKIT_SSH_DROPIN" ] && grep -qxF "$DEBKIT_SSH_MARCA" "$DEBKIT_SSH_DROPIN"; then
        rm -f -- "$DEBKIT_SSH_DROPIN"
    fi
    if [ "${DEBKIT_SSH_RECARREGADO:-0}" -eq 1 ] && debkit_sshd -t >/dev/null 2>&1; then
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
        conf_obsoletas) debkit_conf_restaurar ;;
        dir_backup)  rmdir -- "$DEBKIT_BACKUP_DIR" 2>/dev/null ;;   # só se vazia
        grupo)       getent group "$DEBKIT_GRUPO_USUARIOS" | awk -F: '$4 != "" {exit 1}' \
                         && groupdel -- "$DEBKIT_GRUPO_USUARIOS" ;;
        ssh_protecao) debkit_ssh_desfazer ;;
        firewall)    debkit_fw_desfazer ;;
        log_rotacao) debkit_logrotate_desfazer "$DEBKIT_LOG_LOGROTATE" ;;
        # Ações dos módulos: debkit_desfazer_<id>, se existir. Pacotes e log
        # não são desfeitos.
        *)           if declare -F "debkit_desfazer_$1" >/dev/null; then "debkit_desfazer_$1"; fi ;;
    esac
    return 0
}

# ── Execução do plano ───────────────────────────────────────────────────────
# Executa DEBKIT_PLANO na ordem. Se uma ação falhar, desfaz as anteriores (só o
# que é do debkit), na ordem inversa, e informa o que ficou.
debkit_executar_plano() {
    local acao i feito
    local -a feitos=()
    DEBKIT_PACOTES_INSTALADOS=""
    for acao in "${DEBKIT_PLANO[@]}"; do
        if "debkit_acao_$acao"; then
            feitos+=("$acao")
            msg_ok "$(debkit_descrever_acao "$acao")"
            debkit_auditar preparar "acao=$acao resultado=ok"
        else
            msg_erro "$(t prep.falhou "$(debkit_descrever_acao "$acao")")"
            debkit_auditar preparar "acao=$acao resultado=falha"
            # A própria ação pode ter alterado algo antes de falhar (ex: a
            # proteção SSH grava o arquivo e só depois valida): desfaz ela também
            debkit_desfazer "$acao"
            if [ ${#feitos[@]} -gt 0 ]; then
                msg_info "$(t prep.desfazendo)"
                for (( i=${#feitos[@]}-1; i>=0; i-- )); do
                    feito="${feitos[$i]}"
                    debkit_desfazer "$feito"
                    debkit_auditar preparar "acao=$feito resultado=desfeito"
                done
                [ -n "$DEBKIT_PACOTES_INSTALADOS" ] && msg_aviso "$(t prep.mantidos_pacotes "$DEBKIT_PACOTES_INSTALADOS")"
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
    debkit_executar_plano || return 1
    # Com pacotes instalados agora, o que depende deles (ex: as configurações
    # do Samba) só pôde ser avaliado depois: verifica de novo e, se houver
    # mais o que fazer, mostra e pergunta outra vez
    if [[ ",$plano_txt," == *",pacotes,"* ]]; then
        debkit_verificar_ambiente
        debkit_montar_plano
        if [ -n "$DEBKIT_PLANO_IMPOSSIVEL" ]; then
            msg_erro "$DEBKIT_PLANO_IMPOSSIVEL"
            return 1
        fi
        if [ ${#DEBKIT_PLANO[@]} -gt 0 ]; then
            plano_txt=$(IFS=,; echo "${DEBKIT_PLANO[*]}")
            echo ""
            msg_info "$(t prep.mais_itens)"
            debkit_mostrar_plano
            if ! confirmar "$(t prep.pergunta)"; then
                debkit_auditar preparar "plano=$plano_txt resposta=nao"
                msg_aviso "$(t prep.recusado)"
                return 1
            fi
            debkit_auditar preparar "plano=$plano_txt resposta=sim"
            debkit_executar_plano || return 1
        fi
    fi
    echo ""
    msg_ok "$(t prep.concluido)"
    return 0
}

# ════════════════════════════════════════════════════════════════════════════
# 8. MÓDULOS
# ════════════════════════════════════════════════════════════════════════════
# Cada arquivo de modulos/ (carregado pelo programa debkit depois deste
# núcleo) chama debkit_modulo_registrar <nome> e pode acrescentar chaves de
# configuração, mensagens e dependências nas tabelas do núcleo. Ganchos
# (funções opcionais, chamadas na ordem em que os módulos foram registrados):
#   debkit_<nome>_verificar   itens da verificação do ambiente, no grupo
#                             <nome> (título: mensagem amb.grupo_<nome>)
#   debkit_<nome>_plano       acrescenta ações ao plano de preparação
#                             (debkit_acao_/descrever_/desfazer_<id>)
#   debkit_<nome>_menu        tela do módulo (item do menu principal;
#                             texto: mensagem menu.<nome>)
DEBKIT_MODULOS=()

debkit_modulo_registrar() { DEBKIT_MODULOS+=("$1"); }

# Chama o gancho <nome> de cada módulo que o define
debkit_modulos_gancho() {
    local m
    for m in "${DEBKIT_MODULOS[@]}"; do
        if declare -F "debkit_${m}_$1" >/dev/null; then "debkit_${m}_$1"; fi
    done
    return 0
}

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
    local opcao m i
    local -a menus
    while true; do
        titulo "$(t geral.titulo)  ${C_CINZA}v${DEBKIT_VERSAO}${C_RESET}"
        # Módulos com tela, numerados de 1 a 8 na ordem de registro
        menus=()
        for m in "${DEBKIT_MODULOS[@]}"; do
            declare -F "debkit_${m}_menu" >/dev/null && menus+=("$m")
        done
        for (( i=0; i<${#menus[@]} && i<8; i++ )); do
            echo "  $((i + 1))) $(t "menu.${menus[$i]}")"
        done
        echo ""
        echo "  9) $(t menu.ambiente)"
        echo "  0) $(t geral.sair)"
        echo ""
        ler_opcao opcao
        case "$opcao" in
            "") continue ;;
            [1-8]) if [ "$opcao" -le "${#menus[@]}" ]; then
                       "debkit_${menus[$((opcao - 1))]}_menu"
                   else
                       msg_erro "$(t geral.opcao_invalida "$opcao")"; pausar
                   fi ;;
            9) menu_ambiente ;;
            0) [ -t 1 ] && clear; return 0 ;;
            *) msg_erro "$(t geral.opcao_invalida "$opcao")"; pausar ;;
        esac
    done
}

# ════════════════════════════════════════════════════════════════════════════
# 10. LINHA DE COMANDO
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

# ════════════════════════════════════════════════════════════════════════════
# DESINSTALAÇÃO (tarefa 4.4; seção 3.9)
# ════════════════════════════════════════════════════════════════════════════
# debkit --desinstalar [--tudo]: tira o programa e o comando. Nunca mexe no
# que faz o servidor de arquivos funcionar ou protege os usuários: usuários,
# grupos, compartilhamentos, smb.conf, regras do firewall e, se houver
# usuários de arquivos, a proteção SSH (sem ela eles entrariam por SSH).
# Com o grupo de proteção vazio, a proteção sai junto. Sem --tudo, a
# configuração, o log e os backups ficam (para reinstalar ou consultar);
# com --tudo, saem também. Um plano, UMA confirmação.
DEBKIT_INSTALAR_LINK="${DEBKIT_INSTALAR_LINK:-/usr/local/sbin/debkit}"
DEBKIT_MARCA_INSTALACAO=".debkit-instalado"

# Usuários (membros) do grupo de proteção SSH
debkit_desinstalar_protegidos() { getent group "$DEBKIT_GRUPO_USUARIOS" | cut -d: -f4 | tr ',' '\n' | sed '/^$/d' | wc -l; }

# shellcheck disable=SC2153  # DEBKIT_DIR vem do programa "debkit"
debkit_desinstalar() {
    local tudo="$1" n x falhas=0
    local -a remover=() ficar=()
    titulo "$(t desi.titulo)"
    # O que sai e o que fica
    if [ -L "$DEBKIT_INSTALAR_LINK" ] && [ "$(readlink -- "$DEBKIT_INSTALAR_LINK")" == "$DEBKIT_DIR/debkit" ]; then
        remover+=(link)
    fi
    if [ -f "$DEBKIT_DIR/$DEBKIT_MARCA_INSTALACAO" ]; then remover+=(programa); else ficar+=("$(t desi.f_repositorio "$DEBKIT_DIR")"); fi
    if getent group "$DEBKIT_GRUPO_USUARIOS" >/dev/null 2>&1 || { [ -f "$DEBKIT_SSH_DROPIN" ] && grep -qxF "$DEBKIT_SSH_MARCA" "$DEBKIT_SSH_DROPIN"; }; then
        n=$(debkit_desinstalar_protegidos)
        if [ "$n" -eq 0 ]; then remover+=(protecao); else ficar+=("$(t desi.f_protecao "$DEBKIT_SSH_DROPIN" "$DEBKIT_GRUPO_USUARIOS" "$n")"); fi
    fi
    if [ "$tudo" -eq 1 ]; then
        [ -e "$DEBKIT_CONF_ARQUIVO" ] && remover+=(conf)
        { [ -e "$DEBKIT_LOG" ] || [ -e "$DEBKIT_LOG_LOGROTATE" ]; } && remover+=(log)
        { [ -d "$DEBKIT_BACKUP_DIR" ] || [ -d "${DEBKIT_SMB_BACKUP_DIR:-}" ]; } && remover+=(backups)
    else
        ficar+=("$(t desi.f_dados "$DEBKIT_CONF_ARQUIVO" "$DEBKIT_LOG" "$DEBKIT_BACKUP_DIR" "${DEBKIT_SMB_BACKUP_DIR:-—}")")
    fi
    ficar+=("$(t desi.f_usuarios)" "$(t desi.f_firewall)")
    if [ ${#remover[@]} -eq 0 ]; then msg_info "$(t desi.nada)"; return 0; fi

    printf '  %s%s%s\n' "$C_NEGRITO" "$(t desi.vai)" "$C_RESET"
    for x in "${remover[@]}"; do printf '    • %s\n' "$(debkit_desinstalar_descrever "$x")"; done
    echo ""
    printf '  %s%s%s\n' "$C_NEGRITO" "$(t desi.fica)" "$C_RESET"
    for x in "${ficar[@]}"; do printf '    · %s\n' "$x"; done
    echo ""
    if ! confirmar "$(t desi.pergunta)"; then
        debkit_auditar desinstalar "itens=$(IFS=,; echo "${remover[*]}") resposta=nao"
        msg_aviso "$(t desi.cancelado)"; return 1
    fi
    debkit_auditar desinstalar "itens=$(IFS=,; echo "${remover[*]}") tudo=$tudo resposta=sim"

    # O programa pode sair enquanto roda (o bash já leu o que precisa). O
    # log sai por último, e a sessão termina antes dele (o fim da sessão
    # recriaria o arquivo)
    for x in protecao conf backups link programa log; do
        [[ " ${remover[*]} " == *" $x "* ]] || continue
        if [ "$x" == "log" ]; then
            debkit_auditar sessao_fim "motivo=desinstalado"; DEBKIT_SESSAO_ATIVA=0
        fi
        if "debkit_desinstalar_$x"; then
            msg_ok "$(t desi.feito "$(debkit_desinstalar_descrever "$x")")"
            [ "$x" != "log" ] && debkit_auditar desinstalar "item=$x resultado=ok"
        else
            msg_erro "$(t desi.falhou "$(debkit_desinstalar_descrever "$x")")"
            [ "$x" != "log" ] && debkit_auditar desinstalar "item=$x resultado=falha"
            falhas=$((falhas + 1))
        fi
    done
    echo ""
    if [ "$falhas" -eq 0 ]; then msg_ok "$(t desi.concluido)"; return 0; fi
    msg_erro "$(t desi.incompleto)"; return 1
}

debkit_desinstalar_descrever() {
    case "$1" in
        link)     t desi.r_link "$DEBKIT_INSTALAR_LINK" ;;
        programa) t desi.r_programa "$DEBKIT_DIR" ;;
        protecao) t desi.r_protecao "$DEBKIT_SSH_DROPIN" "$DEBKIT_GRUPO_USUARIOS" ;;
        conf)     t desi.r_conf "$DEBKIT_CONF_ARQUIVO" ;;
        log)      t desi.r_log "$DEBKIT_LOG" "$DEBKIT_LOG_LOGROTATE" ;;
        backups)  t desi.r_backups "$DEBKIT_BACKUP_DIR" "${DEBKIT_SMB_BACKUP_DIR:-—}" ;;
    esac
}

debkit_desinstalar_link() { rm -f -- "$DEBKIT_INSTALAR_LINK" && [ ! -e "$DEBKIT_INSTALAR_LINK" ]; }

# O programa: só a pasta com a marca do install.sh (e nunca "/")
debkit_desinstalar_programa() {
    [ -f "$DEBKIT_DIR/$DEBKIT_MARCA_INSTALACAO" ] && [ "$DEBKIT_DIR" != "/" ] || return 1
    rm -rf -- "$DEBKIT_DIR" && [ ! -e "$DEBKIT_DIR" ]
}

# Proteção SSH (só com o grupo vazio): o arquivo do SSH (backup e recarga,
# como o desfazer da preparação) e o grupo
debkit_desinstalar_protecao() {
    [ "$(debkit_desinstalar_protegidos)" -eq 0 ] || return 1
    debkit_ssh_remover_protecao || return 1
    if getent group "$DEBKIT_GRUPO_USUARIOS" >/dev/null 2>&1; then
        groupdel -- "$DEBKIT_GRUPO_USUARIOS" || return 1
    fi
}

# A configuração (e a pasta, se ficar vazia)
debkit_desinstalar_conf() {
    rm -f -- "$DEBKIT_CONF_ARQUIVO" || return 1
    rmdir -- "$(debkit_dir_conf)" 2>/dev/null
    [ ! -e "$DEBKIT_CONF_ARQUIVO" ]
}

# O log, os girados (.N e .N.gz) e a regra da rotação
debkit_desinstalar_log() {
    local arq
    for arq in "$DEBKIT_LOG" "$DEBKIT_LOG".[0-9]* "$DEBKIT_LOG_LOGROTATE"; do
        if [ -f "$arq" ] || [ -L "$arq" ]; then rm -f -- "$arq" || return 1; fi
    done
    [ ! -e "$DEBKIT_LOG" ]
}

# Os backups: a pasta do debkit inteira; na do smb.conf, só os arquivos com
# o nome dos backups do debkit (e a pasta, se ficar vazia)
debkit_desinstalar_backups() {
    local arq
    if [ -d "$DEBKIT_BACKUP_DIR" ]; then rm -rf -- "$DEBKIT_BACKUP_DIR" || return 1; fi
    if [ -n "${DEBKIT_SMB_BACKUP_DIR:-}" ] && [ -d "$DEBKIT_SMB_BACKUP_DIR" ]; then
        for arq in "$DEBKIT_SMB_BACKUP_DIR"/smb.conf.[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]-*; do
            [ -f "$arq" ] && { rm -f -- "$arq" || return 1; }
        done
        rmdir -- "$DEBKIT_SMB_BACKUP_DIR" 2>/dev/null
    fi
    [ ! -e "$DEBKIT_BACKUP_DIR" ]
}

# Comandos diretos: começa a "sessão" de um comando que altera algo (como
# a do menu): trava contra outra execução, auditoria de início/fim e
# limpeza ao sair. Os comandos que só leem não chamam (como o --verificar).
debkit_cli_sessao() {
    trap debkit_ao_sair EXIT
    trap 'echo; msg_aviso "$(t geral.interrompido)"; DEBKIT_MOTIVO_SAIDA="interrompida"; exit 130' INT TERM
    debkit_travar || return 1
    debkit_auditar sessao_inicio "v$DEBKIT_VERSAO comando: $*"
    DEBKIT_SESSAO_ATIVA=1
}

# Lê os argumentos de um comando direto:
#   debkit_cli_ler "<opções com valor>" "<opções sem valor>" "$@"
# (nomes sem o "--", separados por espaço; os em inglês de DEBKIT_CLI_ALIAS
# viram o nome em português). "--opcao valor" ou
# "--opcao=valor"; o resto vai, na ordem, para DEBKIT_ARGS. As opções ficam em
# DEBKIT_OPCOES[nome] (as sem valor, com 1). Opção desconhecida ou sem valor:
# mensagem e retorna 1. "--" encerra as opções.
# Nomes de opção em inglês -> o nome em português que o comando usa (os
# módulos acrescentam os seus)
declare -A DEBKIT_CLI_ALIAS=()
# shellcheck disable=SC2034  # DEBKIT_OPCOES é lido pelos módulos
declare -A DEBKIT_OPCOES=()
DEBKIT_ARGS=()
# shellcheck disable=SC2034
debkit_cli_ler() {
    local com=" $1 " sem=" $2 " a nome
    shift 2
    DEBKIT_OPCOES=(); DEBKIT_ARGS=()
    while [ $# -gt 0 ]; do
        a="$1"; shift
        case "$a" in
            --) DEBKIT_ARGS+=("$@"); break ;;
            --?*=*)
                nome="${a%%=*}"; nome="${nome#--}"
                [ -n "${DEBKIT_CLI_ALIAS[$nome]+x}" ] && nome="${DEBKIT_CLI_ALIAS[$nome]}"
                if [[ "$com" != *" $nome "* ]]; then msg_erro "$(t cli.opcao_desconhecida "${a%%=*}")"; return 1; fi
                DEBKIT_OPCOES[$nome]="${a#*=}" ;;
            --?*)
                nome="${a#--}"
                [ -n "${DEBKIT_CLI_ALIAS[$nome]+x}" ] && nome="${DEBKIT_CLI_ALIAS[$nome]}"
                if [[ "$com" == *" $nome "* ]]; then
                    if [ $# -eq 0 ]; then msg_erro "$(t cli.falta_valor "$a")"; return 1; fi
                    DEBKIT_OPCOES[$nome]="$1"; shift
                elif [[ "$sem" == *" $nome "* ]]; then
                    DEBKIT_OPCOES[$nome]=1
                else
                    msg_erro "$(t cli.opcao_desconhecida "$a")"; return 1
                fi ;;
            -?*) msg_erro "$(t cli.opcao_desconhecida "$a")"; return 1 ;;
            *)   DEBKIT_ARGS+=("$a") ;;
        esac
    done
}

# Módulo com comandos diretos (gancho debkit_<nome>_comando)?
debkit_modulo_com_comandos() {
    local m
    for m in "${DEBKIT_MODULOS[@]}"; do
        [ "$m" == "$1" ] && declare -F "debkit_${m}_comando" >/dev/null && return 0
    done
    return 1
}

main() {
    # Idioma por variável de ambiente tem prioridade (útil em testes)
    local idioma_env="${DEBKIT_IDIOMA:-}" arg modulo="" tudo
    local -a args=()

    # --sim (--yes) vale em qualquer posição; --tudo (--all), só com --desinstalar
    DEBKIT_SIM=0; DEBKIT_CLI=0; tudo=0
    for arg in "$@"; do
        case "$arg" in
            --sim|--yes) DEBKIT_SIM=1 ;;
            --tudo|--all) tudo=1 ;;
            *)           args+=("$arg") ;;
        esac
    done
    set -- "${args[@]}"

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

    if [ "$tudo" -eq 1 ] && [[ "${1:-}" != --desinstalar && "${1:-}" != --uninstall ]]; then
        msg_erro "$(t desi.tudo_onde)"; exit 2
    fi
    case "${1:-}" in
        --preparar|--setup|--desinstalar|--uninstall) ;;
        ""|--verificar|--check)
            if [ "$DEBKIT_SIM" -eq 1 ]; then msg_erro "$(t cli.sim_onde)"; exit 2; fi ;;
        -*) msg_erro "$(t erro.uso "$1")"; exit 2 ;;
        *)  if debkit_modulo_com_comandos "$1"; then modulo="$1"; shift
            else msg_erro "$(t erro.uso "$1")"; exit 2; fi ;;
    esac

    # Comandos diretos de um módulo (a ajuda dele não precisa de root)
    if [ -n "$modulo" ]; then
        DEBKIT_CLI=1
        case "${1:-}" in
            ""|-h|--ajuda|--help) "debkit_${modulo}_comando" --ajuda; exit $? ;;
        esac
    fi

    if [ "$EUID" -ne 0 ]; then
        msg_erro "$(t erro.root)"
        exit 1
    fi

    if [ -n "$modulo" ]; then
        "debkit_${modulo}_comando" "$@"
        exit $?
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

    # Desinstalação (DEBKIT_DIR vem do programa "debkit")
    if [ "${1:-}" == "--desinstalar" ] || [ "${1:-}" == "--uninstall" ]; then
        DEBKIT_CLI=1
        debkit_desinstalar "$tudo"
        exit $?
    fi

    # Preparação pela linha de comando
    if [ -n "${1:-}" ]; then
        debkit_preparar
        exit $?
    fi

    debkit_assistente || exit 1
    menu_principal
}
