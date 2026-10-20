# shellcheck shell=bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║  debkit - módulo samba                                                   ║
# ╚══════════════════════════════════════════════════════════════════════════╝
#
# Servidor de arquivos Samba (modo standalone, base de senhas tdbsam).
# Dependências, verificação e preparação do Samba, backups do smb.conf
# (SMB_BACKUP_DIR, com rotação), a edição segura do smb.conf
# (debkit_smbconf_editar), usuários (criar, listar, trocar senha, pasta
# pessoal) e grupos (criar, membros, remover). Compartilhamentos vêm na
# Fase 2 (ver docs/PLANEJAMENTO.md, seções 3, 4 e 6).
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
    DEBKIT_CONF_PADRAO[HOMES_BASE]=""
    DEBKIT_CONF_PADRAO[SHARES_BASE]=""
    DEBKIT_CONF_TIPO[SMB_CONF]="caminho"
    DEBKIT_CONF_TIPO[SMB_BACKUP_DIR]="caminho"
    DEBKIT_CONF_TIPO[HOMES_BASE]="caminho_opcional"
    DEBKIT_CONF_TIPO[SHARES_BASE]="caminho_opcional"
    DEBKIT_CONF_ORDEM+=(SMB_CONF SMB_BACKUP_DIR HOMES_BASE SHARES_BASE)
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
    [amb.sync_ligado]="\"unix password sync\" ligado: trocar a senha pelo Windows também define a senha do Linux (a dos usuários de arquivos deve ficar bloqueada): a preparação vai desligar"
    [prep.d_samba_sem_sync]="Desligar no %s a sincronização da senha do Linux (\"unix password sync = no\"; com backup e conferência de que só isso muda)"
    [amb.convidado]="\"map to guest = %s\": quem entra com um nome que não existe (ex: um usuário excluído) vira convidado em vez de ser recusado: a preparação vai mudar para \"never\""
    [prep.d_samba_sem_convidado]="Recusar no %s o login de quem não existe, em vez de virar convidado (\"map to guest = never\"; com backup e conferência de que só isso muda)"
    [amb.pacotes_dominio]="Pacotes de domínio instalados sem necessidade num servidor independente: %s. O winbind faz o Linux aceitar a senha do Samba em logins como o SSH: a preparação vai removê-los"
    [prep.d_samba_pacotes_dominio]="Remover os pacotes de domínio desnecessários: %s (apt-get purge; depois confere que o PAM e o NSS não usam mais o winbind e que o Samba continua funcionando)"
    [prep.dominio_removeria_mais]="O apt removeria também outros pacotes (%s): nada foi removido."
    [prep.dominio_simulacao_falhou]="Não foi possível simular a remoção (apt-get -s). Nada foi removido."
    [prep.dominio_falhou]="A remoção falhou. Últimas linhas:"
    [prep.dominio_conferencia]="Depois da remoção: %s"
    [prep.dominio_mantidos]="Os pacotes removidos não foram reinstalados: %s"
    [samba.criar_usuario]="Criar usuário"
    [samba.listar_usuarios]="Listar usuários"
    [samba.trocar_senha]="Trocar senha"
    [sen.titulo]="Trocar senha"
    [sen.titulo_usuarios]="Usuários:"
    [sen.sem_usuarios]="Nenhum usuário com senha que o debkit possa trocar."
    [sen.p_usuario]="Usuário (número; Enter cancela): "
    [sen.titulo_qual]="Qual senha?"
    [sen.q_samba]="Samba (pastas)"
    [sen.q_linux]="Linux (SSH/console)"
    [sen.q_ambas]="As duas (a mesma senha)"
    [sen.p_qual]="Opção [3]: "
    [sen.p_nova_samba]="Nova senha do Samba: "
    [sen.p_nova_linux]="Nova senha do Linux: "
    [sen.p_nova_ambas]="Nova senha (Samba e Linux): "
    [sen.so_samba_info]="%s é %s: só a senha do Samba é trocada (a do Linux continua bloqueada)."
    [sen.admin_info]="%s é administrador: o debkit troca só a senha do Samba (a do Linux, troque à mão com passwd)."
    [sen.nao_comum]="'%s' não é um usuário comum do servidor."
    [sen.sem_samba]="%s não tem conta no Samba."
    [sen.linux_nao_permitida]="%s não tem acesso ao servidor: a senha do Linux continua bloqueada (só a do Samba pode ser trocada)."
    [sen.linux_admin]="%s é administrador: troque a senha do Linux à mão (passwd)."
    [sen.alvo_invalido]="Opção de senha inválida: '%s'."
    [sen.trocada]="Senha de %s trocada (%s)."
    [sen.falhou]="Não foi possível trocar a senha de %s: %s"
    [sen.f_linux]="o chpasswd falhou"
    [sen.f_samba]="o smbpasswd falhou"
    [sen.f_bloqueio]="a senha do Linux deixou de estar bloqueada (foi restaurada)"
    [sen.linux_restaurada]="A senha do Linux voltou a ser a anterior: nada ficou pela metade."
    [sen.a_samba]="Samba"
    [sen.a_linux]="Linux"
    [sen.a_ambas]="Samba e Linux"
    [lst.titulo]="Usuários do servidor"
    [lst.c_login]="Login"
    [lst.c_nome]="Nome completo"
    [lst.c_tipo]="Tipo"
    [lst.c_samba]="Samba"
    [lst.c_home]="Pasta pessoal"
    [lst.c_grupos]="Grupos"
    [lst.t_arquivos]="arquivos"
    [lst.t_servidor]="servidor"
    [lst.t_admin]="admin"
    [lst.t_nologin]="nologin"
    [lst.s_ativa]="ativa"
    [lst.s_desativada]="desativada"
    [lst.s_so_samba]="só Samba"
    [lst.nenhum]="Nenhum usuário comum no servidor."
    [lst.total]="%d usuário(s): %d de arquivos, %d com acesso ao servidor, %d admin, %d outro(s)."
    [lst.legenda]="arquivos = só Samba, SSH recusado · servidor = Samba e SSH/console · admin = membro do sudo (o debkit não remove nem desativa)"
    [lst.a_so_samba]="%s: conta só no Samba, sem usuário no Linux"
    [lst.a_so_linux]="%s: sem conta no Samba (não acessa as pastas)"
    [lst.a_tunel]="%s: shell sem login, mas fora do grupo de proteção %s: o SSH ainda aceita a senha e permite túnel"
    [lst.titulo_alertas]="Atenção:"
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
    [samba.criar_home]="Criar pasta pessoal para um usuário existente"
    [samba.pastas_pessoais]="Pastas pessoais: base e compartilhamento [homes]"
    [home.titulo]="Pastas pessoais"
    [home.titulo_criar]="Criar pasta pessoal"
    [home.p_criar]="Criar pasta pessoal?"
    [home.base_atual]="Base das pastas pessoais: %s"
    [home.base_nenhuma]="Base das pastas pessoais: ainda não definida"
    [home.base_intro]="As pastas pessoais ficam num disco de dados (separado do disco do sistema), para os dados ficarem juntos no backup. Isso é definido uma vez e gravado na configuração."
    [home.discos]="Discos de dados montados:"
    [home.sem_discos]="Nenhum disco de dados montado (só o disco do sistema). Monte um disco de dados (ex: em /mnt/dados) e tente de novo."
    [home.p_base]="Base [%s]: "
    [home.p_base_sem]="Base (caminho completo; Enter cancela): "
    [home.base_vazia]="Informe o caminho da base."
    [home.base_formato]="Caminho inválido: '%s'. Use o caminho completo, só com letras sem acento, números e / . _ -"
    [home.base_link]="Use o caminho real de '%s' (sem links, sem / no fim nem //): %s"
    [home.base_sistema]="'%s' fica numa pasta do sistema (%s): escolha uma pasta num disco de dados."
    [home.base_nao_pasta]="'%s' existe e não é uma pasta."
    [home.base_disco_sistema]="'%s' fica no disco do sistema (/): escolha uma pasta num disco de dados montado."
    [home.base_nao_disco]="'%s' fica em %s (%s), que não é um disco de dados."
    [home.base_somente_leitura]="'%s' fica em %s, montado somente leitura."
    [home.base_sem_permissoes]="'%s' fica em %s (%s), que não guarda dono e permissões do Linux."
    [home.p_confirma_base]="Usar %s como base das pastas pessoais (cria a pasta se não existir e grava HOMES_BASE na configuração)?"
    [home.base_criar_falhou]="Não foi possível criar a pasta %s."
    [home.base_definida]="Base das pastas pessoais: %s (gravada em %s)."
    [home.base_invalida_agora]="A base das pastas pessoais (%s) não pode ser usada agora: %s"
    [home.r_sim]="Pasta pessoal: %s"
    [home.ja_existe]="A pasta %s já existe: o debkit não usa uma pasta que não criou."
    [home.f_criar]="não foi possível criar a pasta pessoal %s"
    [home.sem_candidatos]="Nenhum usuário comum sem pasta pessoal."
    [home.titulo_usuarios]="Usuários sem pasta pessoal:"
    [home.p_usuario]="Usuário (número; Enter cancela): "
    [home.usuario_tem_home]="O usuário %s já tem pasta pessoal (%s)."
    [home.usuario_nao_comum]="'%s' não é um usuário comum do servidor."
    [home.p_confirmar]="Criar a pasta pessoal %s para %s?"
    [home.criada]="Pasta pessoal %s criada para %s."
    [home.falhou]="Não foi possível criar a pasta pessoal de %s: %s"
    [home.f_usermod]="o usermod falhou"
    [home.segue_sem]="Seguindo sem pasta pessoal (ela pode ser criada depois)."
    [homes.estado_ok]="Compartilhamento [homes]: ativo e com escrita (cada usuário vê só a própria pasta)"
    [homes.estado_ausente]="Compartilhamento [homes]: não existe (as pastas pessoais não aparecem no Windows)"
    [homes.estado_leitura]="Compartilhamento [homes]: existe, mas somente leitura (ou sem \"valid users = %S\")"
    [homes.estado_outro]="Compartilhamento [homes]: configurado à mão com outro caminho (o debkit não mexe)"
    [homes.p_criar]="Criar o compartilhamento [homes] no smb.conf (cada usuário vê só a própria pasta, com escrita)?"
    [homes.p_liberar]="Liberar a escrita no compartilhamento [homes] (\"read only = no\"; cada usuário continua vendo só a própria pasta)?"
    [homes.feito]="Compartilhamento [homes] pronto."
    [homes.aviso_depois]="Para a pasta aparecer no Windows, ajuste o compartilhamento [homes] em Samba > Compartilhamentos > \"Pastas pessoais\"."
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
    [amb.sync_ligado]="\"unix password sync\" enabled: changing the password from Windows also sets the Linux password (file users must keep it locked): the setup will turn it off"
    [prep.d_samba_sem_sync]="Turn off in %s the Linux password sync (\"unix password sync = no\"; with backup and a check that nothing else changes)"
    [amb.convidado]="\"map to guest = %s\": logging in with a name that does not exist (e.g. a deleted user) becomes a guest instead of being refused: the preparation will change it to \"never\""
    [prep.d_samba_sem_convidado]="Refuse in %s the login of users that do not exist, instead of becoming a guest (\"map to guest = never\"; with backup and a check that nothing else changes)"
    [amb.pacotes_dominio]="Domain packages installed without need on a standalone server: %s. winbind makes Linux accept the Samba password in logins such as SSH: the setup will remove them"
    [prep.d_samba_pacotes_dominio]="Remove the unneeded domain packages: %s (apt-get purge; then checks that PAM and NSS no longer use winbind and that Samba still works)"
    [prep.dominio_removeria_mais]="apt would also remove other packages (%s): nothing was removed."
    [prep.dominio_simulacao_falhou]="Could not simulate the removal (apt-get -s). Nothing was removed."
    [prep.dominio_falhou]="The removal failed. Last lines:"
    [prep.dominio_conferencia]="After the removal: %s"
    [prep.dominio_mantidos]="The removed packages were not reinstalled: %s"
    [samba.criar_usuario]="Create user"
    [samba.listar_usuarios]="List users"
    [samba.trocar_senha]="Change password"
    [sen.titulo]="Change password"
    [sen.titulo_usuarios]="Users:"
    [sen.sem_usuarios]="No user with a password debkit can change."
    [sen.p_usuario]="User (number; Enter cancels): "
    [sen.titulo_qual]="Which password?"
    [sen.q_samba]="Samba (folders)"
    [sen.q_linux]="Linux (SSH/console)"
    [sen.q_ambas]="Both (the same password)"
    [sen.p_qual]="Option [3]: "
    [sen.p_nova_samba]="New Samba password: "
    [sen.p_nova_linux]="New Linux password: "
    [sen.p_nova_ambas]="New password (Samba and Linux): "
    [sen.so_samba_info]="%s is %s: only the Samba password is changed (the Linux one stays locked)."
    [sen.admin_info]="%s is an administrator: debkit only changes the Samba password (change the Linux one by hand with passwd)."
    [sen.nao_comum]="'%s' is not a regular server user."
    [sen.sem_samba]="%s has no Samba account."
    [sen.linux_nao_permitida]="%s has no server access: the Linux password stays locked (only the Samba one can be changed)."
    [sen.linux_admin]="%s is an administrator: change the Linux password by hand (passwd)."
    [sen.alvo_invalido]="Invalid password option: '%s'."
    [sen.trocada]="Password of %s changed (%s)."
    [sen.falhou]="Could not change the password of %s: %s"
    [sen.f_linux]="chpasswd failed"
    [sen.f_samba]="smbpasswd failed"
    [sen.f_bloqueio]="the Linux password was no longer locked (it was restored)"
    [sen.linux_restaurada]="The Linux password is back to the previous one: nothing was left half-done."
    [sen.a_samba]="Samba"
    [sen.a_linux]="Linux"
    [sen.a_ambas]="Samba and Linux"
    [lst.titulo]="Server users"
    [lst.c_login]="Login"
    [lst.c_nome]="Full name"
    [lst.c_tipo]="Type"
    [lst.c_samba]="Samba"
    [lst.c_home]="Home folder"
    [lst.c_grupos]="Groups"
    [lst.t_arquivos]="files"
    [lst.t_servidor]="server"
    [lst.t_admin]="admin"
    [lst.t_nologin]="nologin"
    [lst.s_ativa]="active"
    [lst.s_desativada]="disabled"
    [lst.s_so_samba]="Samba only"
    [lst.nenhum]="No regular users on the server."
    [lst.total]="%d user(s): %d file users, %d with server access, %d admin, %d other(s)."
    [lst.legenda]="files = Samba only, SSH denied · server = Samba and SSH/console · admin = sudo member (debkit does not remove or disable them)"
    [lst.a_so_samba]="%s: account only in Samba, no Linux user"
    [lst.a_so_linux]="%s: no Samba account (cannot access the folders)"
    [lst.a_tunel]="%s: no-login shell, but outside the protection group %s: SSH still accepts the password and allows tunnels"
    [lst.titulo_alertas]="Attention:"
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
    [samba.criar_home]="Create home folder for an existing user"
    [samba.pastas_pessoais]="Home folders: base and [homes] share"
    [home.titulo]="Home folders"
    [home.titulo_criar]="Create home folder"
    [home.p_criar]="Create a home folder?"
    [home.base_atual]="Home folders base: %s"
    [home.base_nenhuma]="Home folders base: not defined yet"
    [home.base_intro]="Home folders live on a data disk (separate from the system disk), so all data stays together for backup. This is set once and saved in the configuration."
    [home.discos]="Mounted data disks:"
    [home.sem_discos]="No data disk mounted (only the system disk). Mount a data disk (e.g. at /mnt/dados) and try again."
    [home.p_base]="Base [%s]: "
    [home.p_base_sem]="Base (full path; Enter cancels): "
    [home.base_vazia]="Enter the base path."
    [home.base_formato]="Invalid path: '%s'. Use the full path, only letters without accents, digits and / . _ -"
    [home.base_link]="Use the real path of '%s' (no links, no trailing / or //): %s"
    [home.base_sistema]="'%s' is in a system folder (%s): choose a folder on a data disk."
    [home.base_nao_pasta]="'%s' exists and is not a folder."
    [home.base_disco_sistema]="'%s' is on the system disk (/): choose a folder on a mounted data disk."
    [home.base_nao_disco]="'%s' is on %s (%s), which is not a data disk."
    [home.base_somente_leitura]="'%s' is on %s, mounted read-only."
    [home.base_sem_permissoes]="'%s' is on %s (%s), which does not keep Linux owners and permissions."
    [home.p_confirma_base]="Use %s as the home folders base (creates the folder if needed and saves HOMES_BASE in the configuration)?"
    [home.base_criar_falhou]="Could not create the folder %s."
    [home.base_definida]="Home folders base: %s (saved in %s)."
    [home.base_invalida_agora]="The home folders base (%s) cannot be used now: %s"
    [home.r_sim]="Home folder: %s"
    [home.ja_existe]="The folder %s already exists: debkit does not use a folder it did not create."
    [home.f_criar]="could not create the home folder %s"
    [home.sem_candidatos]="No regular user without a home folder."
    [home.titulo_usuarios]="Users without a home folder:"
    [home.p_usuario]="User (number; Enter cancels): "
    [home.usuario_tem_home]="User %s already has a home folder (%s)."
    [home.usuario_nao_comum]="'%s' is not a regular server user."
    [home.p_confirmar]="Create the home folder %s for %s?"
    [home.criada]="Home folder %s created for %s."
    [home.falhou]="Could not create the home folder of %s: %s"
    [home.f_usermod]="usermod failed"
    [home.segue_sem]="Continuing without a home folder (it can be created later)."
    [homes.estado_ok]="[homes] share: active and writable (each user only sees their own folder)"
    [homes.estado_ausente]="[homes] share: does not exist (home folders do not show up in Windows)"
    [homes.estado_leitura]="[homes] share: exists, but read-only (or without \"valid users = %S\")"
    [homes.estado_outro]="[homes] share: configured by hand with another path (debkit does not touch it)"
    [homes.p_criar]="Create the [homes] share in smb.conf (each user only sees their own folder, writable)?"
    [homes.p_liberar]="Allow writing in the [homes] share (\"read only = no\"; each user still only sees their own folder)?"
    [homes.feito]="[homes] share ready."
    [homes.aviso_depois]="For the folder to show up in Windows, adjust the [homes] share in Samba > Shares > \"Home folders\"."
)

# shellcheck disable=SC2034  # catálogo do núcleo
MSG_pt_BR+=(
    [samba.grupos]="Grupos"
    [samba.usuarios]="Usuários"
    [shr.listar]="Listar compartilhamentos"
    [shr.criar]="Criar compartilhamento"
    [shr.titulo_listar]="Compartilhamentos do servidor"
    [shr.titulo_criar]="Criar compartilhamento"
    [shr.c_nome]="Nome"
    [shr.c_pasta]="Pasta"
    [shr.c_grupo]="Grupo (acesso total)"
    [shr.so_leitura]="somente leitura"
    [shr.todos]="qualquer usuário"
    [shr.usuario]="usuário"
    [shr.total]="%d compartilhamento(s)."
    [shr.nenhum]="Nenhum compartilhamento no servidor ainda."
    [shr.a_sem_pasta]="%s: a pasta %s não existe"
    [shr.a_convidado]="%s: aberto para convidado (guest ok): qualquer pessoa na rede acessa sem senha"
    [shr.a_todos]="%s: sem \"valid users\": qualquer usuário do Samba acessa"
    [shr.a_fora_padrao]="%s: fora do padrão do debkit (um grupo só, com acesso total)"
    [shr.crie_grupo]="Nenhum grupo para dar acesso: crie um grupo antes (Samba > Grupos)."
    [shr.dica_nome]="Nome: letras minúsculas sem acento, números, - e _, começando por letra (ex: financeiro, ti-docs). Enter vazio cancela."
    [shr.p_nome]="Nome do compartilhamento: "
    [shr.p_comentario]="Descrição (opcional; aparece no Windows; Enter para pular): "
    [shr.p_pasta]="Pasta [%s]: "
    [shr.p_grupo]="Grupo do compartilhamento (número; Enter cancela): "
    [shr.p_confirmar]="Criar o compartilhamento?"
    [shr.p_confirma_base]="Usar %s como base dos compartilhamentos?"
    [shr.base_intro]="Os compartilhamentos ficam numa base dentro de /mnt ou /srv (ex: um disco de dados). Isso é definido uma vez e gravado na configuração; cada compartilhamento pode usar outra pasta dentro de /mnt ou /srv."
    [shr.base_definida]="Base dos compartilhamentos: %s (gravada em %s)."
    [shr.base_invalida_agora]="A base dos compartilhamentos (%s) não pode ser usada agora: %s"
    [shr.nome_vazio]="Informe o nome do compartilhamento."
    [shr.nome_tamanho]="O nome '%s' tem %d caractere(s): use de 2 a 32."
    [shr.nome_formato]="Nome inválido: '%s'. Use letras minúsculas sem acento, números, - e _, começando por letra e terminando em letra ou número (ex: financeiro, ti-docs)."
    [shr.nome_reservado]="'%s' é um nome reservado do Samba."
    [shr.nome_existe]="Já existe um compartilhamento (ou seção) '%s' no smb.conf."
    [shr.comentario_invalido]="Descrição inválida: não use \\, %% nem caracteres de controle."
    [shr.comentario_tamanho]="Descrição muito longa (máximo %d caracteres)."
    [shr.pasta_vazia]="Informe a pasta."
    [shr.fora_das_raizes]="'%s': a pasta precisa ficar dentro de /mnt ou /srv."
    [shr.pai_nao_existe]="'%s': a pasta de cima (%s) não existe."
    [shr.mistura_homes]="'%s' se mistura com a base das pastas pessoais (%s)."
    [shr.mistura_outro]="'%s' se mistura com a pasta de outro compartilhamento (%s)."
    [shr.sem_grupo]="Informe o grupo do compartilhamento."
    [shr.dica_grupo]="Os membros do grupo têm acesso total à pasta. Para dar acesso a mais alguém, adicione a pessoa ao grupo (Samba > Grupos)."
    [shr.r_nome]="Compartilhamento: %s"
    [shr.r_comentario]="Descrição: %s"
    [shr.r_pasta_nova]="Pasta: %s (será criada)"
    [shr.r_pasta_existe]="Pasta: %s (já existe; dono e permissões da pasta serão ajustados)"
    [shr.r_grupo]="Grupo (acesso total): %s"
    [shr.aviso_conteudo]="%s já tem arquivos: depois de criar, o debkit oferece ajustar as permissões do conteúdo."
    [shr.criando]="Criando o compartilhamento %s..."
    [shr.criado]="Compartilhamento %s criado (%s)."
    [shr.falhou]="Não foi possível criar o compartilhamento %s: %s"
    [shr.f_pasta]="não foi possível preparar a pasta %s"
    [shr.f_smbconf]="a alteração do smb.conf não foi feita"
    [shr.desfazer_falhou]="ATENÇÃO: não foi possível desfazer a pasta %s: confira à mão."
    [shr.trocar]="Trocar o grupo de um compartilhamento"
    [shr.ajustar]="Ajustar as permissões do conteúdo"
    [shr.nenhum_gerenciavel]="Nenhum compartilhamento no padrão do debkit (um grupo com acesso total). Os que estão fora do padrão aparecem em Listar."
    [shr.titulo_lista]="Compartilhamentos:"
    [shr.item]="%s (grupo %s, %s)"
    [shr.p_compartilhamento]="Compartilhamento (número; Enter cancela): "
    [shr.atual]="Grupo atual: %s (pasta %s)"
    [shr.p_novo_grupo]="Novo grupo (número; Enter cancela): "
    [shr.sem_outro_grupo]="Não há outro grupo para escolher: crie um grupo antes (Samba > Grupos)."
    [shr.mesmo_grupo]="%s já é o grupo do compartilhamento."
    [shr.nao_gerenciavel]="%s não existe ou não está no padrão do debkit (um grupo com acesso total; pasta existente dentro de /mnt ou /srv, só deste compartilhamento)."
    [shr.r_troca]="Grupo: %s -> %s"
    [shr.aviso_perdem]="Perdem o acesso (membros de %s que não estão em %s): %s"
    [shr.conteudo]="Conteúdo de %s: %d item(ns) (arquivos e pastas), %d fora do padrão."
    [shr.conteudo_ok]="Conteúdo de %s: %d item(ns), todos já no padrão."
    [shr.explica_ajuste]="Ajuste: tudo passa para o grupo %s, com leitura e escrita para o grupo (pastas com setgid) e sem acesso para outros. Os donos dos arquivos não mudam."
    [shr.p_confirmar_trocar]="Trocar o grupo de %s para %s?"
    [shr.p_confirmar_ajustar]="Ajustar as permissões do conteúdo de %s?"
    [shr.p_ajustar_agora]="Ajustar agora as permissões do conteúdo (tudo para o grupo %s)?"
    [shr.trocando]="Trocando o grupo do compartilhamento %s..."
    [shr.trocado]="Compartilhamento %s agora é do grupo %s."
    [shr.trocar_falhou]="Não foi possível trocar o grupo do compartilhamento %s: %s"
    [shr.ajustando]="Ajustando as permissões de %s..."
    [shr.ajustado]="Permissões de %s ajustadas: %d item(ns) no padrão."
    [shr.ajustar_invalido]="Não é possível ajustar %s (grupo %s): a pasta precisa existir dentro de /mnt ou /srv, sem se misturar com as pastas pessoais nem com outro compartilhamento, e o grupo precisa existir."
    [shr.ajustar_falhou]="Não foi possível ajustar tudo em %s: %d item(ns) ainda fora do padrão. Rode de novo: Compartilhamentos > Ajustar as permissões do conteúdo."
    [shr.remover]="Remover um compartilhamento"
    [shr.r_pasta_fica]="Pasta: %s (os arquivos ficam no disco; só o root acessa)"
    [shr.p_confirmar_remover]="Remover o compartilhamento %s?"
    [shr.removendo]="Removendo o compartilhamento %s..."
    [shr.removido]="Compartilhamento %s removido."
    [shr.pasta_mantida]="Os arquivos continuam em %s (pasta do root, sem acesso pela rede). Para usar de novo, crie um compartilhamento com essa pasta."
    [shr.remover_falhou]="Não foi possível remover o compartilhamento %s: %s"
    [shr.trancar_falhou]="O compartilhamento %s saiu do smb.conf, mas não foi possível deixar a pasta %s só para o root: confira à mão."
    [shr.r_pasta_intocada]="Pasta: %s (não muda: fora de /mnt e /srv, inexistente ou usada por outro compartilhamento)"
    [shr.pasta_intocada]="A pasta %s não foi alterada (fora de /mnt e /srv, inexistente ou usada por outro compartilhamento)."
    [shr.aviso_perdem_lista]="Perdem o acesso: %s"
    [shr.item_acesso]="%s (acesso: %s; %s)"
    [shr.padronizar]="Trazer um compartilhamento para o padrão"
    [shr.nenhum_padronizavel]="Nenhum compartilhamento fora do padrão pode ser trazido para ele (a pasta precisa existir dentro de /mnt ou /srv, só deste compartilhamento). Os outros podem ser removidos (Compartilhamentos > Remover)."
    [shr.acesso_atual]="Acesso atual: %s (pasta %s)"
    [shr.p_grupo_padrao]="Grupo com acesso total (número; Enter cancela): "
    [shr.r_padrao]="Acesso: %s -> %s (acesso total)"
    [shr.explica_padrao]="No smb.conf, a seção fica com valid users = @%s, read only = no, force group = %s, create mask = 0660 e directory mask = 2770; saem write list, read list, guest ok, force user, admin users e invalid users. O resto da seção não muda."
    [shr.p_confirmar_padrao]="Trazer %s para o padrão (grupo %s)?"
    [shr.padronizando]="Trazendo o compartilhamento %s para o padrão..."
    [shr.padronizado]="Compartilhamento %s no padrão: grupo %s com acesso total."
    [shr.padrao_falhou]="Não foi possível trazer o compartilhamento %s para o padrão: %s"
    [shr.nao_padronizavel]="%s não existe, já está no padrão ou a pasta não pode ser usada (precisa existir dentro de /mnt ou /srv, só deste compartilhamento)."
    [shr.nao_existe]="%s não existe."
    [samba.consistencia]="Verificar e corrigir contas (Linux x Samba)"
    [cns.titulo]="Verificar e corrigir contas"
    [cns.tudo_ok]="Tudo certo: todas as contas estão no Linux e no Samba, protegidas como o tipo pede."
    [cns.encontrados]="%d item(ns) fora do padrão:"
    [cns.p_so_samba]="%s: conta no Samba sem usuário no Linux"
    [cns.p_so_linux]="%s: usuário no Linux sem conta no Samba (não acessa as pastas)"
    [cns.p_tunel]="%s: shell sem login, mas fora do grupo de proteção %s (o SSH ainda aceita a senha e abre túnel)"
    [cns.p_senha_linux]="%s: usuário de arquivos com senha do Linux utilizável (devia estar bloqueada)"
    [cns.q_so_samba]="Apagar a conta Samba de %s?"
    [cns.q_so_linux]="Criar a conta Samba de %s (com uma senha nova)?"
    [cns.q_tunel]="Pôr %s no grupo de proteção %s (o SSH passa a recusar)?"
    [cns.q_senha_linux]="Bloquear a senha do Linux de %s (a do Samba não muda)?"
    [cns.p_senha]="Senha do Samba para %s: "
    [cns.pulado]="Mantido como está."
    [cns.resumo]="%d de %d item(ns) corrigido(s)."
    [cns.nao_se_aplica]="%s: a situação mudou, nada a corrigir."
    [cns.falhou]="Não foi possível corrigir %s: %s"
    [cns.f_pdbedit]="o pdbedit falhou"
    [cns.f_grupo]="não entrou no grupo %s"
    [cns.f_bloqueio]="a senha não ficou bloqueada"
    [cns.linux_restaurada]="%s: a senha do Linux tinha mudado junto e voltou a ser a anterior."
    [cns.ok_so_samba]="Conta Samba de %s apagada."
    [cns.ok_so_linux]="Conta Samba de %s criada."
    [cns.ok_tunel]="%s agora está no grupo de proteção %s (SSH recusado)."
    [cns.ok_senha_linux]="Senha do Linux de %s bloqueada."
    [samba.excluir_usuario]="Excluir usuário"
    [rmu.titulo]="Excluir usuário"
    [rmu.sem_usuarios]="Nenhum usuário que o debkit possa excluir (administradores e quem roda o debkit não são excluídos)."
    [rmu.admin]="%s é administrador (sudo): o debkit não exclui administradores."
    [rmu.proprio]="%s é quem está rodando o debkit: não pode ser excluído."
    [rmu.grupo_no_smb]="O grupo pessoal de %s é usado no Samba (%s): tire-o dos compartilhamentos antes de excluir."
    [rmu.processos]="%s tem processos em execução fora do Samba (%s; ex: SSH aberto): encerre-os antes de excluir."
    [rmu.titulo_perde]="Será excluído %s:"
    [rmu.r_contas]="Contas: Linux e Samba (a senha some junto)"
    [rmu.r_contas_linux]="Contas: Linux (sem conta no Samba)"
    [rmu.r_home_apagar]="Pasta pessoal: %s - será APAGADA com tudo dentro"
    [rmu.r_home_nenhuma]="Pasta pessoal: não tem"
    [rmu.r_home_manter]="Pasta pessoal: %s - será mantida (%s)"
    [rmu.h_nao_pasta]="não é uma pasta comum"
    [rmu.h_fora]="fora da base das pastas pessoais e de /home"
    [rmu.h_dono]="o dono não é o usuário"
    [rmu.h_outro]="outro usuário usa a mesma pasta"
    [rmu.aviso_sessoes]="Conectado ao Samba agora (%d sessão/ões): a conexão será encerrada."
    [rmu.aviso_usos]="O login é citado no %s, nos compartilhamentos: %s- essas regras passarão a apontar para um usuário que não existe."
    [rmu.procurando]="Procurando arquivos do usuário (UID %s) na base das pastas pessoais e nos compartilhamentos..."
    [rmu.aviso_arquivos]="%d arquivo(s)/pasta(s) dele nos compartilhamentos NÃO serão apagados. Eles ficam com o número %s e um usuário criado depois pode receber o mesmo número e virar dono deles."
    [rmu.aviso_arquivos_muitos]="%d ou mais arquivo(s)/pasta(s) dele nos compartilhamentos NÃO serão apagados. Eles ficam com o número %s e um usuário criado depois pode receber o mesmo número e virar dono deles."
    [rmu.sem_arquivos]="Nenhum arquivo dele nos compartilhamentos (fora a pasta pessoal)."
    [rmu.p_confirmar]="Excluir o usuário %s?"
    [rmu.excluindo]="Excluindo o usuário %s..."
    [rmu.excluido]="Usuário %s excluído."
    [rmu.falhou]="Não foi possível excluir o usuário %s: %s"
    [rmu.f_sessoes]="não foi possível encerrar a sessão do Samba (nada foi apagado)"
    [rmu.f_userdel]="o userdel falhou (nada foi apagado)"
    [rmu.f_samba]="O usuário Linux foi excluído, mas a conta Samba de %s ficou: ela aparece na listagem como \"só Samba\"."
    [rmu.f_home]="Não foi possível apagar a pasta pessoal %s: apague à mão."
    [rmu.sessoes_encerradas]="%d sessão(ões) do Samba encerrada(s)."
    [rmu.home_apagada]="Pasta pessoal %s apagada."
    [rmu.home_mantida]="Pasta pessoal %s mantida (%s)."
    [rmu.grupo_mantido]="O grupo pessoal %s foi mantido (tem membros ou é o grupo principal de outro usuário)."
    [samba.compartilhamentos]="Compartilhamentos"
    [samba.titulo_usuarios]="Samba: usuários"
    [samba.titulo_compartilhamentos]="Samba: compartilhamentos"
    [grp.titulo]="Samba: grupos"
    [grp.listar]="Listar grupos"
    [grp.criar]="Criar grupo"
    [grp.membros]="Membros: adicionar ou remover usuários"
    [grp.remover]="Remover grupo"
    [grp.titulo_listar]="Grupos do servidor"
    [grp.titulo_criar]="Criar grupo"
    [grp.titulo_membros]="Membros de um grupo"
    [grp.titulo_remover]="Remover grupo"
    [grp.titulo_grupos]="Grupos:"
    [grp.titulo_usuarios]="Usuários:"
    [grp.c_grupo]="Grupo"
    [grp.c_membros]="Membros"
    [grp.marca_principal]="(principal)"
    [grp.usado_em]="usado no Samba: %s"
    [grp.total]="%d grupo(s)."
    [grp.nenhum]="Nenhum grupo comum no servidor."
    [grp.sem_usuarios]="(nenhum usuário comum no servidor ainda)"
    [grp.dica_nome]="Nome: letras minúsculas sem acento e números, começando por letra, com _ entre as partes (ex: gp_rh). Enter vazio cancela."
    [grp.p_nome]="Nome do grupo: "
    [grp.nome_vazio]="Informe o nome do grupo."
    [grp.nome_formato]="Nome inválido: '%s'. Use letras minúsculas sem acento e números, começando por letra, com _ entre as partes (ex: gp_rh)."
    [grp.nome_debkit]="'%s': nomes começando por \"debkit\" são reservados para os grupos do próprio debkit."
    [grp.nome_existe]="Já existe um grupo '%s' no servidor."
    [grp.nome_usuario_existe]="Já existe um usuário '%s' (o grupo pessoal dele tem esse nome)."
    [grp.nome_sudoers]="'%s' é citado no sudoers: quem entrasse no grupo ganharia sudo. O debkit não cria esse grupo."
    [grp.p_membros]="Membros (números separados por vírgula ou espaço; Enter para nenhum): "
    [grp.r_grupo]="Grupo: %s"
    [grp.r_membros]="Membros: %s"
    [grp.r_outros]="Outros membros (de sistema; o debkit não mexe): %s"
    [grp.r_principais]="Grupo principal de: %s (não podem ser removidos)"
    [grp.p_confirmar_criar]="Criar o grupo?"
    [grp.criando]="Criando o grupo %s..."
    [grp.criado]="Grupo %s criado."
    [grp.falhou]="Não foi possível criar o grupo %s: %s"
    [grp.desfazer_falhou]="ATENÇÃO: não foi possível apagar o grupo %s criado pela metade: confira à mão."
    [grp.f_groupadd]="o groupadd falhou"
    [grp.f_gid]="o GID %s criado está fora da faixa de grupos comuns"
    [grp.f_membros]="não foi possível definir os membros"
    [grp.nao_usuario_comum]="'%s' não é um usuário comum do servidor."
    [grp.nao_gerenciado]="'%s' não é um grupo comum que o debkit gerencia."
    [grp.nada_a_fazer]="Nenhum usuário para adicionar ou remover."
    [grp.e_principal]="'%s' tem %s como grupo principal: não pode ser adicionado nem removido por aqui."
    [grp.ja_membro]="'%s' já é membro de %s."
    [grp.nao_membro]="'%s' não é membro de %s."
    [grp.entrar_e_sair]="'%s' está para ser adicionado e removido ao mesmo tempo."
    [grp.p_grupo]="Grupo (número; Enter cancela): "
    [grp.a_entrar]="Adicionar usuários ao grupo"
    [grp.a_sair]="Remover usuários do grupo"
    [grp.p_acao]="Opção (Enter cancela): "
    [grp.p_usuarios]="Usuários (números separados por vírgula ou espaço; Enter cancela): "
    [grp.sem_candidatos_entrar]="Todos os usuários comuns já estão em %s."
    [grp.sem_candidatos_sair]="%s não tem membros que possam ser removidos."
    [grp.p_confirmar_entrar]="Adicionar %s ao grupo %s?"
    [grp.p_confirmar_sair]="Remover %s do grupo %s?"
    [grp.membros_ok]="Membros de %s atualizados."
    [grp.membros_falhou]="Não foi possível mudar os membros de %s: a lista anterior foi mantida."
    [grp.membros_desfazer_falhou]="ATENÇÃO: os membros de %s não ficaram como o esperado e a lista anterior não voltou: confira à mão."
    [ses.aviso]="Conectado(s) ao Samba agora: %s. Ao terminar, a conexão será refeita para os grupos valerem na hora (arquivo aberto sem salvar pode ser afetado)."
    [ses.reconectado]="%s: %d sessão(ões) do Samba reconectada(s); o acesso já vale com os grupos novos."
    [ses.falhou]="%s: não foi possível encerrar a sessão do Samba; o acesso só muda quando ele reconectar."
    [grp.remover_principal]="%s é o grupo principal de: %s. O debkit não remove esse grupo."
    [grp.aviso_membros]="%d membro(s) perdem o acesso dado por este grupo: %s"
    [grp.sem_membros]="O grupo não tem membros."
    [grp.remover_usado]="O grupo %s é usado no Samba (%s): troque o grupo do compartilhamento (Compartilhamentos > Trocar o grupo) ou remova o compartilhamento antes."
    [grp.procurando]="Procurando arquivos do grupo (GID %s) na base das pastas pessoais e nos compartilhamentos..."
    [grp.aviso_arquivos]="%d arquivo(s)/pasta(s) pertencem ao grupo. Eles ficam com o número %s e um grupo criado depois pode receber o mesmo número e herdar o acesso."
    [grp.aviso_arquivos_muitos]="%d arquivo(s)/pasta(s) ou mais pertencem ao grupo. Eles ficam com o número %s e um grupo criado depois pode receber o mesmo número e herdar o acesso."
    [grp.sem_arquivos]="Nenhum arquivo do grupo encontrado na base das pastas pessoais nem nos compartilhamentos."
    [grp.p_confirmar_remover]="Remover o grupo %s?"
    [grp.removido]="Grupo %s removido."
    [grp.remover_falhou]="Não foi possível remover o grupo %s."
)
# shellcheck disable=SC2034  # catálogo do núcleo
MSG_en+=(
    [samba.grupos]="Groups"
    [samba.usuarios]="Users"
    [shr.listar]="List shares"
    [shr.criar]="Create share"
    [shr.titulo_listar]="Server shares"
    [shr.titulo_criar]="Create share"
    [shr.c_nome]="Name"
    [shr.c_pasta]="Folder"
    [shr.c_grupo]="Group (full access)"
    [shr.so_leitura]="read only"
    [shr.todos]="any user"
    [shr.usuario]="user"
    [shr.total]="%d share(s)."
    [shr.nenhum]="No shares on the server yet."
    [shr.a_sem_pasta]="%s: folder %s does not exist"
    [shr.a_convidado]="%s: open to guests (guest ok): anyone on the network gets in without a password"
    [shr.a_todos]="%s: no \"valid users\": any Samba user gets in"
    [shr.a_fora_padrao]="%s: not in the debkit pattern (a single group, with full access)"
    [shr.crie_grupo]="No group to give access to: create a group first (Samba > Groups)."
    [shr.dica_nome]="Name: lowercase letters without accents, digits, - and _, starting with a letter (e.g. finance, it-docs). Empty Enter cancels."
    [shr.p_nome]="Share name: "
    [shr.p_comentario]="Description (optional; shows in Windows; Enter to skip): "
    [shr.p_pasta]="Folder [%s]: "
    [shr.p_grupo]="Share group (number; Enter cancels): "
    [shr.p_confirmar]="Create the share?"
    [shr.p_confirma_base]="Use %s as the shares base?"
    [shr.base_intro]="Shares live in a base inside /mnt or /srv (e.g. a data disk). This is set once and saved in the configuration; each share may use another folder inside /mnt or /srv."
    [shr.base_definida]="Shares base: %s (saved in %s)."
    [shr.base_invalida_agora]="The shares base (%s) cannot be used now: %s"
    [shr.nome_vazio]="Enter the share name."
    [shr.nome_tamanho]="The name '%s' has %d character(s): use 2 to 32."
    [shr.nome_formato]="Invalid name: '%s'. Use lowercase letters without accents, digits, - and _, starting with a letter and ending with a letter or digit (e.g. finance, it-docs)."
    [shr.nome_reservado]="'%s' is a reserved Samba name."
    [shr.nome_existe]="A share (or section) '%s' already exists in smb.conf."
    [shr.comentario_invalido]="Invalid description: do not use \\, %% or control characters."
    [shr.comentario_tamanho]="Description too long (at most %d characters)."
    [shr.pasta_vazia]="Enter the folder."
    [shr.fora_das_raizes]="'%s': the folder must be inside /mnt or /srv."
    [shr.pai_nao_existe]="'%s': the parent folder (%s) does not exist."
    [shr.mistura_homes]="'%s' overlaps the home folders base (%s)."
    [shr.mistura_outro]="'%s' overlaps the folder of another share (%s)."
    [shr.sem_grupo]="Enter the share group."
    [shr.dica_grupo]="Group members have full access to the folder. To give someone else access, add them to the group (Samba > Groups)."
    [shr.r_nome]="Share: %s"
    [shr.r_comentario]="Description: %s"
    [shr.r_pasta_nova]="Folder: %s (will be created)"
    [shr.r_pasta_existe]="Folder: %s (already exists; the folder owner and permissions will be adjusted)"
    [shr.r_grupo]="Group (full access): %s"
    [shr.aviso_conteudo]="%s already has files: after creating, debkit offers to adjust the content permissions."
    [shr.criando]="Creating share %s..."
    [shr.criado]="Share %s created (%s)."
    [shr.falhou]="Could not create share %s: %s"
    [shr.f_pasta]="could not prepare folder %s"
    [shr.f_smbconf]="the smb.conf change was not made"
    [shr.desfazer_falhou]="WARNING: could not undo folder %s: check it by hand."
    [shr.trocar]="Change the group of a share"
    [shr.ajustar]="Adjust the content permissions"
    [shr.nenhum_gerenciavel]="No share in the debkit pattern (a single group with full access). Those out of the pattern show up in List."
    [shr.titulo_lista]="Shares:"
    [shr.item]="%s (group %s, %s)"
    [shr.p_compartilhamento]="Share (number; Enter cancels): "
    [shr.atual]="Current group: %s (folder %s)"
    [shr.p_novo_grupo]="New group (number; Enter cancels): "
    [shr.sem_outro_grupo]="There is no other group to choose: create a group first (Samba > Groups)."
    [shr.mesmo_grupo]="%s is already the share group."
    [shr.nao_gerenciavel]="%s does not exist or is not in the debkit pattern (a single group with full access; an existing folder inside /mnt or /srv, used only by this share)."
    [shr.r_troca]="Group: %s -> %s"
    [shr.aviso_perdem]="Lose access (members of %s who are not in %s): %s"
    [shr.conteudo]="Content of %s: %d item(s) (files and folders), %d out of the pattern."
    [shr.conteudo_ok]="Content of %s: %d item(s), all already in the pattern."
    [shr.explica_ajuste]="Adjustment: everything goes to group %s, with read and write for the group (folders with setgid) and no access for others. File owners do not change."
    [shr.p_confirmar_trocar]="Change the group of %s to %s?"
    [shr.p_confirmar_ajustar]="Adjust the content permissions of %s?"
    [shr.p_ajustar_agora]="Adjust the content permissions now (everything to group %s)?"
    [shr.trocando]="Changing the group of share %s..."
    [shr.trocado]="Share %s now belongs to group %s."
    [shr.trocar_falhou]="Could not change the group of share %s: %s"
    [shr.ajustando]="Adjusting the permissions of %s..."
    [shr.ajustado]="Permissions of %s adjusted: %d item(s) in the pattern."
    [shr.ajustar_invalido]="Cannot adjust %s (group %s): the folder must exist inside /mnt or /srv, not overlapping the home folders nor another share, and the group must exist."
    [shr.ajustar_falhou]="Could not adjust everything in %s: %d item(s) still out of the pattern. Run it again: Shares > Adjust the content permissions."
    [shr.remover]="Remove a share"
    [shr.r_pasta_fica]="Folder: %s (the files stay on disk; only root has access)"
    [shr.p_confirmar_remover]="Remove share %s?"
    [shr.removendo]="Removing share %s..."
    [shr.removido]="Share %s removed."
    [shr.pasta_mantida]="The files remain in %s (root folder, no network access). To use them again, create a share with this folder."
    [shr.remover_falhou]="Could not remove share %s: %s"
    [shr.trancar_falhou]="Share %s left smb.conf, but folder %s could not be restricted to root: check it by hand."
    [shr.r_pasta_intocada]="Folder: %s (unchanged: outside /mnt and /srv, missing or used by another share)"
    [shr.pasta_intocada]="Folder %s was not changed (outside /mnt and /srv, missing or used by another share)."
    [shr.aviso_perdem_lista]="Lose access: %s"
    [shr.item_acesso]="%s (access: %s; %s)"
    [shr.padronizar]="Bring a share into the pattern"
    [shr.nenhum_padronizavel]="No share out of the pattern can be brought into it (the folder must exist inside /mnt or /srv, used only by this share). The others can be removed (Shares > Remove)."
    [shr.acesso_atual]="Current access: %s (folder %s)"
    [shr.p_grupo_padrao]="Group with full access (number; Enter cancels): "
    [shr.r_padrao]="Access: %s -> %s (full access)"
    [shr.explica_padrao]="In smb.conf, the section gets valid users = @%s, read only = no, force group = %s, create mask = 0660 and directory mask = 2770; write list, read list, guest ok, force user, admin users and invalid users are removed. The rest of the section does not change."
    [shr.p_confirmar_padrao]="Bring %s into the pattern (group %s)?"
    [shr.padronizando]="Bringing share %s into the pattern..."
    [shr.padronizado]="Share %s in the pattern: group %s with full access."
    [shr.padrao_falhou]="Could not bring share %s into the pattern: %s"
    [shr.nao_padronizavel]="%s does not exist, is already in the pattern or its folder cannot be used (it must exist inside /mnt or /srv, used only by this share)."
    [shr.nao_existe]="%s does not exist."
    [samba.consistencia]="Check and fix accounts (Linux x Samba)"
    [cns.titulo]="Check and fix accounts"
    [cns.tudo_ok]="All good: every account is in Linux and in Samba, protected as its type requires."
    [cns.encontrados]="%d item(s) out of standard:"
    [cns.p_so_samba]="%s: Samba account without a Linux user"
    [cns.p_so_linux]="%s: Linux user without a Samba account (cannot access the folders)"
    [cns.p_tunel]="%s: no-login shell, but outside the protection group %s (SSH still accepts the password and opens tunnels)"
    [cns.p_senha_linux]="%s: file user with a usable Linux password (should be locked)"
    [cns.q_so_samba]="Delete the Samba account of %s?"
    [cns.q_so_linux]="Create the Samba account of %s (with a new password)?"
    [cns.q_tunel]="Put %s in the protection group %s (SSH will refuse)?"
    [cns.q_senha_linux]="Lock the Linux password of %s (the Samba one does not change)?"
    [cns.p_senha]="Samba password for %s: "
    [cns.pulado]="Left as is."
    [cns.resumo]="%d of %d item(s) fixed."
    [cns.nao_se_aplica]="%s: the situation changed, nothing to fix."
    [cns.falhou]="Could not fix %s: %s"
    [cns.f_pdbedit]="pdbedit failed"
    [cns.f_grupo]="did not join group %s"
    [cns.f_bloqueio]="the password was not locked"
    [cns.linux_restaurada]="%s: the Linux password had changed too and was restored."
    [cns.ok_so_samba]="Samba account of %s deleted."
    [cns.ok_so_linux]="Samba account of %s created."
    [cns.ok_tunel]="%s is now in the protection group %s (SSH refused)."
    [cns.ok_senha_linux]="Linux password of %s locked."
    [samba.excluir_usuario]="Delete user"
    [rmu.titulo]="Delete user"
    [rmu.sem_usuarios]="No users that debkit can delete (administrators and whoever runs debkit are not deleted)."
    [rmu.admin]="%s is an administrator (sudo): debkit does not delete administrators."
    [rmu.proprio]="%s is the one running debkit: cannot be deleted."
    [rmu.grupo_no_smb]="The personal group of %s is used in Samba (%s): remove it from the shares before deleting."
    [rmu.processos]="%s has processes running outside Samba (%s; e.g. open SSH): end them before deleting."
    [rmu.titulo_perde]="%s will be deleted:"
    [rmu.r_contas]="Accounts: Linux and Samba (the password goes with them)"
    [rmu.r_contas_linux]="Accounts: Linux (no Samba account)"
    [rmu.r_home_apagar]="Home folder: %s - will be DELETED with everything inside"
    [rmu.r_home_nenhuma]="Home folder: none"
    [rmu.r_home_manter]="Home folder: %s - will be kept (%s)"
    [rmu.h_nao_pasta]="not a regular folder"
    [rmu.h_fora]="outside the home folder base and /home"
    [rmu.h_dono]="the owner is not the user"
    [rmu.h_outro]="another user uses the same folder"
    [rmu.aviso_sessoes]="Connected to Samba now (%d session(s)): the connection will be closed."
    [rmu.aviso_usos]="The login is referenced in %s, in the shares: %s- those rules will point to a user that does not exist."
    [rmu.procurando]="Looking for the user's files (UID %s) in the home folder base and in the shares..."
    [rmu.aviso_arquivos]="%d of their file(s)/folder(s) in the shares will NOT be deleted. They keep the number %s, and a user created later may get the same number and own them."
    [rmu.aviso_arquivos_muitos]="%d or more of their file(s)/folder(s) in the shares will NOT be deleted. They keep the number %s, and a user created later may get the same number and own them."
    [rmu.sem_arquivos]="No files of theirs in the shares (apart from the home folder)."
    [rmu.p_confirmar]="Delete user %s?"
    [rmu.excluindo]="Deleting user %s..."
    [rmu.excluido]="User %s deleted."
    [rmu.falhou]="Could not delete user %s: %s"
    [rmu.f_sessoes]="could not close the Samba session (nothing was deleted)"
    [rmu.f_userdel]="userdel failed (nothing was deleted)"
    [rmu.f_samba]="The Linux user was deleted, but the Samba account of %s remained: it shows in the listing as \"Samba only\"."
    [rmu.f_home]="Could not delete the home folder %s: delete it by hand."
    [rmu.sessoes_encerradas]="%d Samba session(s) closed."
    [rmu.home_apagada]="Home folder %s deleted."
    [rmu.home_mantida]="Home folder %s kept (%s)."
    [rmu.grupo_mantido]="The personal group %s was kept (it has members or is another user's primary group)."
    [samba.compartilhamentos]="Shares"
    [samba.titulo_usuarios]="Samba: users"
    [samba.titulo_compartilhamentos]="Samba: shares"
    [grp.titulo]="Samba: groups"
    [grp.listar]="List groups"
    [grp.criar]="Create group"
    [grp.membros]="Members: add or remove users"
    [grp.remover]="Remove group"
    [grp.titulo_listar]="Server groups"
    [grp.titulo_criar]="Create group"
    [grp.titulo_membros]="Group members"
    [grp.titulo_remover]="Remove group"
    [grp.titulo_grupos]="Groups:"
    [grp.titulo_usuarios]="Users:"
    [grp.c_grupo]="Group"
    [grp.c_membros]="Members"
    [grp.marca_principal]="(primary)"
    [grp.usado_em]="used in Samba: %s"
    [grp.total]="%d group(s)."
    [grp.nenhum]="No regular groups on the server."
    [grp.sem_usuarios]="(no regular users on the server yet)"
    [grp.dica_nome]="Name: lowercase letters without accents and digits, starting with a letter, with _ between parts (e.g. gp_hr). Empty Enter cancels."
    [grp.p_nome]="Group name: "
    [grp.nome_vazio]="Enter the group name."
    [grp.nome_formato]="Invalid name: '%s'. Use lowercase letters without accents and digits, starting with a letter, with _ between parts (e.g. gp_hr)."
    [grp.nome_debkit]="'%s': names starting with \"debkit\" are reserved for debkit's own groups."
    [grp.nome_existe]="A group '%s' already exists on the server."
    [grp.nome_usuario_existe]="A user '%s' already exists (their personal group has that name)."
    [grp.nome_sudoers]="'%s' is referenced in sudoers: anyone joining the group would get sudo. debkit does not create this group."
    [grp.p_membros]="Members (numbers separated by commas or spaces; Enter for none): "
    [grp.r_grupo]="Group: %s"
    [grp.r_membros]="Members: %s"
    [grp.r_outros]="Other members (system; debkit does not touch them): %s"
    [grp.r_principais]="Primary group of: %s (cannot leave)"
    [grp.p_confirmar_criar]="Create the group?"
    [grp.criando]="Creating group %s..."
    [grp.criado]="Group %s created."
    [grp.falhou]="Could not create group %s: %s"
    [grp.desfazer_falhou]="WARNING: could not delete the half-created group %s: check it by hand."
    [grp.f_groupadd]="groupadd failed"
    [grp.f_gid]="the created GID %s is outside the regular group range"
    [grp.f_membros]="could not set the members"
    [grp.nao_usuario_comum]="'%s' is not a regular user on the server."
    [grp.nao_gerenciado]="'%s' is not a regular group managed by debkit."
    [grp.nada_a_fazer]="No users to add or remove."
    [grp.e_principal]="'%s' has %s as primary group: cannot join or leave here."
    [grp.ja_membro]="'%s' is already a member of %s."
    [grp.nao_membro]="'%s' is not a member of %s."
    [grp.entrar_e_sair]="'%s' is set to join and leave at the same time."
    [grp.p_grupo]="Group (number; Enter cancels): "
    [grp.a_entrar]="Add users to the group"
    [grp.a_sair]="Remove users from the group"
    [grp.p_acao]="Option (Enter cancels): "
    [grp.p_usuarios]="Users (numbers separated by commas or spaces; Enter cancels): "
    [grp.sem_candidatos_entrar]="All regular users are already in %s."
    [grp.sem_candidatos_sair]="%s has no members that can leave."
    [grp.p_confirmar_entrar]="Add %s to group %s?"
    [grp.p_confirmar_sair]="Remove %s from group %s?"
    [grp.membros_ok]="Members of %s updated."
    [grp.membros_falhou]="Could not change the members of %s: the previous list was kept."
    [grp.membros_desfazer_falhou]="WARNING: the members of %s are not as expected and the previous list did not come back: check it by hand."
    [ses.aviso]="Connected to Samba now: %s. When done, the connection will be redone so the groups apply right away (an open unsaved file may be affected)."
    [ses.reconectado]="%s: %d Samba session(s) reconnected; access now follows the new groups."
    [ses.falhou]="%s: could not close the Samba session; access only changes when they reconnect."
    [grp.remover_principal]="%s is the primary group of: %s. debkit does not remove this group."
    [grp.aviso_membros]="%d member(s) lose the access given by this group: %s"
    [grp.sem_membros]="The group has no members."
    [grp.remover_usado]="Group %s is used in Samba (%s): change the share group (Shares > Change the group) or remove the share first."
    [grp.procurando]="Looking for files of the group (GID %s) in the home folder base and in the shares..."
    [grp.aviso_arquivos]="%d file(s)/folder(s) belong to the group. They keep the number %s, and a group created later may get the same number and inherit the access."
    [grp.aviso_arquivos_muitos]="%d or more file(s)/folder(s) belong to the group. They keep the number %s, and a group created later may get the same number and inherit the access."
    [grp.sem_arquivos]="No files of the group found in the home folder base or in the shares."
    [grp.p_confirmar_remover]="Remove group %s?"
    [grp.removido]="Group %s removed."
    [grp.remover_falhou]="Could not remove group %s."
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
    DEBKIT_SVC_SAMBA=""; DEBKIT_SAMBA_INCLUDE_ANTIGO=""; DEBKIT_SAMBA_INCLUDE_VAZIO=0; DEBKIT_SAMBA_DOMINIO=""; DEBKIT_SAMBA_SYNC=0
    DEBKIT_SAMBA_CONVIDADO=""
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
        if [ "$(debkit_samba_param "unix password sync")" == "Yes" ]; then
            DEBKIT_SAMBA_SYNC=1
            debkit_verif_add samba aviso "$(t amb.sync_ligado)"
        fi
        DEBKIT_SAMBA_CONVIDADO=$(debkit_samba_param "map to guest")
        if [ -n "$DEBKIT_SAMBA_CONVIDADO" ] && [ "$DEBKIT_SAMBA_CONVIDADO" != "Never" ]; then
            debkit_verif_add samba aviso "$(t amb.convidado "$DEBKIT_SAMBA_CONVIDADO")"
        else
            DEBKIT_SAMBA_CONVIDADO=""
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
    if [ "${DEBKIT_SAMBA_SYNC:-0}" -eq 1 ]; then
        DEBKIT_PLANO+=(samba_sem_sync)
    fi
    if [ -n "${DEBKIT_SAMBA_CONVIDADO:-}" ]; then
        DEBKIT_PLANO+=(samba_sem_convidado)
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

# ── Sincronização da senha do Linux (unix password sync) ────────────────────
# Decisão de 16/10/2026: desligada. Com ela ligada (padrão do smb.conf do
# Debian), trocar a senha pelo Windows roda o "passwd program" e define a
# senha do Linux - a do usuário de arquivos deve ficar sempre bloqueada.
debkit_descrever_samba_sem_sync() { t prep.d_samba_sem_sync "$DEBKIT_SMB_CONF"; }

# Filtro: debkit_samba_filtro_global <parâmetro> <valor>. No [global],
# troca o valor da(s) linha(s) do parâmetro (o nome é comparado sem espaços
# e sem maiúsculas, como o Samba faz: "MapToGuest" = "map to guest"); a
# primeira fica no lugar, com o mesmo recuo, e as repetidas saem. Se não
# houver a linha (valor vindo do padrão), põe no fim do [global].
debkit_samba_filtro_global() {
    awk -v nome="$1" -v valor="$2" '
        BEGIN { alvo = tolower(nome); gsub(/[ \t]/, "", alvo); linha = nome " = " valor }
        /^[ \t]*\[/ { if (em && !feito) { print "   " linha; feito = 1 }
                      em = (tolower($0) ~ /^[ \t]*\[global\][ \t]*$/); print; next }
        em && /^[ \t]*[^#;[ \t][^=]*=/ {
            k = $0; sub(/=.*/, "", k); gsub(/[ \t]/, "", k)
            if (tolower(k) == alvo) {
                if (!feito) { match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) linha; feito = 1 }
                next
            }
        }
        { print }
        END { if (em && !feito) print "   " linha }'
}

# Filtro: "unix password sync = no" no [global]
debkit_samba_filtro_sem_sync() { debkit_samba_filtro_global "unix password sync" no; }

# Conferência: a configuração em vigor depois = antes sem a linha do sync
debkit_samba_conferir_sem_sync() {
    cmp -s <(grep -vxF $'\tunix password sync = Yes' "$1") "$2" && ! grep -qxF $'\tunix password sync = Yes' "$2"
}

debkit_acao_samba_sem_sync() {
    debkit_smbconf_editar debkit_samba_filtro_sem_sync debkit_samba_conferir_sem_sync || return 1
    [ "$(debkit_samba_param "unix password sync")" == "No" ]
}

debkit_desfazer_samba_sem_sync() { debkit_smbconf_restaurar; }

# ── Preparação: login de usuário inexistente não vira convidado ─────────────
# Decisão de 19/10/2026 (Fase 2): o smb.conf padrão do Debian tem "map to
# guest = bad user" - quem entra com um nome que não existe (ex: um usuário
# excluído) vira convidado (nobody) em vez de ser recusado. A preparação
# muda para "never" (o padrão do Samba). O debkit não cria compartilhamento
# para convidado (guest ok).
debkit_descrever_samba_sem_convidado() { t prep.d_samba_sem_convidado "$DEBKIT_SMB_CONF"; }
debkit_samba_filtro_sem_convidado() { debkit_samba_filtro_global "map to guest" never; }

# Conferência: a configuração em vigor depois = antes sem a linha do "map
# to guest" (o testparm não mostra o valor padrão, Never)
debkit_samba_conferir_sem_convidado() {
    cmp -s <(grep -v $'^\tmap to guest = ' "$1") "$2" && ! grep -q $'^\tmap to guest = ' "$2"
}

debkit_acao_samba_sem_convidado() {
    debkit_smbconf_editar debkit_samba_filtro_sem_convidado debkit_samba_conferir_sem_convidado || return 1
    [ "$(debkit_samba_param "map to guest")" == "Never" ]
}

debkit_desfazer_samba_sem_convidado() { debkit_smbconf_restaurar; }

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
# que o tem como grupo principal), sem o grupo de proteção do debkit e sem
# os grupos citados no sudoers (entrar neles daria sudo)
debkit_samba_grupos_comuns() {
    local nome gid
    local -A pessoal=() sudoers=()
    while IFS=: read -r nome _ _ gid _; do
        pessoal["$nome:$gid"]=1
    done < <(getent passwd)
    while read -r nome; do sudoers["$nome"]=1; done < <(debkit_grupos_sudoers)
    while IFS=: read -r nome _ gid _; do
        debkit_gid_comum "$gid" || continue
        [ -n "${pessoal["$nome:$gid"]+x}" ] && continue
        [ "$nome" == "$DEBKIT_GRUPO_USUARIOS" ] && continue
        [ -n "${sudoers[$nome]+x}" ] || [ -n "${sudoers[#$gid]+x}" ] && continue
        echo "$nome"
    done < <(getent group) | sort -u
}

# Grupos citados no sudoers e no sudoers.d ("%grupo" e "%#gid"; um por
# linha: "grupo" ou "#gid"). Lê com folga: na dúvida, o grupo fica de fora.
DEBKIT_ARQ_SUDOERS="${DEBKIT_ARQ_SUDOERS:-/etc/sudoers}"
DEBKIT_DIR_SUDOERS_D="${DEBKIT_DIR_SUDOERS_D:-/etc/sudoers.d}"
debkit_grupos_sudoers() {
    cat -- "$DEBKIT_ARQ_SUDOERS" "$DEBKIT_DIR_SUDOERS_D"/* 2>/dev/null \
        | grep -vE '^[[:space:]]*#([^i#]|$)' \
        | grep -oE '%:?#?[^][:space:],:=()!%"\\]+' | sed 's/^%:\{0,1\}//' | sort -u
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
#   DEBKIT_U_SENHA_LINUX (só tipo servidor), DEBKIT_U_HOME (1 = criar a
#   pasta pessoal em HOMES_BASE/<login>; a base já precisa estar pronta)
# Tudo ou nada: cria o usuário Linux (grupo pessoal, sem home; tipo
# arquivos: shell nologin, senha Linux bloqueada e grupo de proteção SSH;
# tipo servidor: /bin/bash e senha Linux própria), a conta Samba, confere
# tudo e, se algo falhar, desfaz o que fez. Senhas só pela entrada padrão.
debkit_usuario_criar() {
    local nome="$DEBKIT_U_NOME" shell grupos estado uid gid g motivo="" home="$DEBKIT_USR_HOME" skel=0
    local -a membros=()
    DEBKIT_U_FEITO_LINUX=0; DEBKIT_U_FEITO_SAMBA=0; DEBKIT_H_CRIADA=0; DEBKIT_U_HOME_DIR=""
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
    # Pasta pessoal: base pronta agora (disco montado) e pasta ainda inexistente
    if [ "${DEBKIT_U_HOME:-0}" -eq 1 ]; then
        if ! motivo=$(debkit_samba_base_problema "$DEBKIT_HOMES_BASE") || [ ! -d "$DEBKIT_HOMES_BASE" ]; then
            msg_erro "$(t usr.falhou "$nome" "$(t home.base_invalida_agora "$DEBKIT_HOMES_BASE" "$motivo")")"
            return 1
        fi
        home="$DEBKIT_HOMES_BASE/$nome"
        if [ -e "$home" ] || [ -L "$home" ]; then
            msg_erro "$(t usr.falhou "$nome" "$(t home.ja_existe "$home")")"
            return 1
        fi
        [ "$DEBKIT_U_TIPO" == "servidor" ] && skel=1
    fi
    DEBKIT_U_HOME_DIR="$home"

    msg_info "$(t usr.criando "$nome")"
    # 1. Usuário Linux (useradd já deixa a senha bloqueada: "!"); a pasta
    # pessoal é criada pelo debkit logo depois (dono, 700, skel só p/ servidor)
    if ! useradd -M -d "$home" -s "$shell" -U -c "$DEBKIT_U_GECOS" ${grupos:+-G "$grupos"} -- "$nome" >/dev/null 2>&1; then
        debkit_usuario_falhou "$(t usr.f_useradd)"
        return 1
    fi
    DEBKIT_U_FEITO_LINUX=1
    IFS=: read -r _ _ uid gid _ < <(getent passwd "$nome")
    if ! debkit_uid_comum "$uid"; then
        debkit_usuario_falhou "$(t usr.f_uid "$uid")"
        return 1
    fi
    if [ "${DEBKIT_U_HOME:-0}" -eq 1 ] && ! debkit_samba_criar_pasta "$nome" "$home" "$gid" "$skel"; then
        debkit_usuario_falhou "$(t home.f_criar "$home")"
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
    [ "$estado" == "$home:$shell" ] || motivo="home/shell"
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
    if [ "${DEBKIT_U_HOME:-0}" -eq 1 ]; then
        [ "$(stat -c '%u %g %a' -- "$home" 2>/dev/null)" == "$uid $gid 700" ] || motivo="pasta pessoal"
    elif [ -d "$DEBKIT_USR_HOME" ]; then
        motivo="$DEBKIT_USR_HOME existe"
    fi
    if [ -n "$motivo" ]; then
        debkit_usuario_falhou "$(t usr.f_conferencia "$motivo")"
        return 1
    fi
    debkit_auditar usuario_criar "nome=$nome tipo=$DEBKIT_U_TIPO uid=$uid grupos=$(IFS=,; echo "${DEBKIT_U_GRUPOS[*]}") home=$home resultado=ok"
    msg_ok "$(t usr.criado "$nome")"
}

# Falha no meio da criação: informa, desfaz o que foi feito e audita
debkit_usuario_falhou() {
    local nome="$DEBKIT_U_NOME"
    msg_erro "$(t usr.falhou "$nome" "$1")"
    debkit_auditar usuario_criar "nome=$nome tipo=$DEBKIT_U_TIPO resultado=falha motivo=$1"
    local havia=$((DEBKIT_U_FEITO_LINUX + DEBKIT_U_FEITO_SAMBA + ${DEBKIT_H_CRIADA:-0}))
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
        debkit_samba_remover_pasta_criada "$DEBKIT_U_HOME_DIR" || return 1
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

# ── Pastas pessoais: base ───────────────────────────────────────────────────
# As pastas pessoais ficam em HOMES_BASE/<login>, num disco de dados (nunca
# no disco do sistema nem em pastas do sistema), para o backup pegar todos
# os dados juntos (decisão 3.3).
DEBKIT_PASTAS_SISTEMA=(/bin /boot /dev /etc /lib /lib32 /lib64 /libx32 /lost+found /proc /root /run /sbin /snap /sys /tmp /usr /var)
# Sistemas de arquivos que não são disco de dados / não guardam dono e permissões
DEBKIT_FS_NAO_DISCO=" tmpfs ramfs devtmpfs proc sysfs cgroup cgroup2 overlay squashfs iso9660 udf autofs devpts mqueue debugfs tracefs securityfs pstore bpf hugetlbfs configfs fusectl binfmt_misc efivarfs nsfs "
DEBKIT_FS_SEM_PERMISSOES=" vfat msdos exfat ntfs ntfs3 fuseblk "

# Imprime o problema da base (mensagem) e retorna 1; 0 = pode ser usada.
# A base pode ainda não existir (será criada): vale o disco onde ficaria.
debkit_samba_base_problema() {
    local dir="$1" s real existente alvo fstipo opcoes
    if [ -z "$dir" ]; then t home.base_vazia; return 1; fi
    if ! debkit_conf_valor_valido caminho "$dir"; then t home.base_formato "$dir"; return 1; fi
    if [ "$dir" == "/" ]; then t home.base_disco_sistema "$dir"; return 1; fi
    for s in "${DEBKIT_PASTAS_SISTEMA[@]}"; do
        if [ "$dir" == "$s" ] || [[ "$dir" == "$s"/* ]]; then t home.base_sistema "$dir" "$s"; return 1; fi
    done
    real=$(realpath -m -- "$dir")
    if [ "$real" != "$dir" ]; then t home.base_link "$dir" "$real"; return 1; fi
    existente="$dir"
    while [ ! -e "$existente" ] && [ ! -L "$existente" ]; do existente=$(dirname -- "$existente"); done
    if [ ! -d "$existente" ] || [ -L "$existente" ]; then t home.base_nao_pasta "$existente"; return 1; fi
    read -r alvo fstipo opcoes < <(findmnt -n -o TARGET,FSTYPE,OPTIONS --target "$existente" 2>/dev/null | tail -n 1)
    if [ -z "$alvo" ] || [ "$alvo" == "/" ]; then t home.base_disco_sistema "$dir"; return 1; fi
    if [[ "$DEBKIT_FS_NAO_DISCO" == *" $fstipo "* ]]; then t home.base_nao_disco "$dir" "$alvo" "$fstipo"; return 1; fi
    if [[ "$DEBKIT_FS_SEM_PERMISSOES" == *" $fstipo "* ]]; then t home.base_sem_permissoes "$dir" "$alvo" "$fstipo"; return 1; fi
    if [[ ",$opcoes," == *",ro,"* ]]; then t home.base_somente_leitura "$dir" "$alvo"; return 1; fi
    return 0
}

# Pontos de montagem que servem de base (um por linha): disco de dados,
# com dono/permissões, gravável, fora das pastas do sistema
debkit_samba_discos_dados() {
    local alvo fstipo opcoes
    while read -r alvo fstipo opcoes; do
        [ "$alvo" == "/" ] && continue
        [[ "$DEBKIT_FS_NAO_DISCO$DEBKIT_FS_SEM_PERMISSOES" == *" $fstipo "* ]] && continue
        [[ ",$opcoes," == *",ro,"* ]] && continue
        debkit_samba_base_problema "$alvo" >/dev/null || continue
        echo "$alvo"
    done < <(findmnt -rn -o TARGET,FSTYPE,OPTIONS 2>/dev/null) | sort -u
}

# Define a base (sem perguntas): valida, cria a pasta se não existe (root,
# 755) e grava HOMES_BASE no debkit.conf. Se a gravação falhar, tira a
# pasta que criou.
debkit_samba_definir_base() {
    local base="$1" problema criada=0
    if ! problema=$(debkit_samba_base_problema "$base"); then msg_erro "$problema"; return 1; fi
    if [ ! -d "$base" ]; then
        if ! ( umask 022; mkdir -p -- "$base" ) || ! chown 0:0 -- "$base" || ! chmod 755 -- "$base"; then
            msg_erro "$(t home.base_criar_falhou "$base")"
            return 1
        fi
        criada=1
    fi
    if ! debkit_conf_definir HOMES_BASE "$base"; then
        [ "$criada" -eq 1 ] && rmdir -- "$base" 2>/dev/null
        return 1
    fi
    msg_ok "$(t home.base_definida "$base" "$DEBKIT_CONF_ARQUIVO")"
}

# Pergunta a base (primeira vez): mostra os discos de dados e sugere
# <primeiro disco>/homes. Retorna 1 se não há disco, cancelou ou falhou.
debkit_samba_escolher_base() {
    local base sugestao problema d
    local -a discos=()
    echo ""
    msg_info "$(t home.base_intro)"
    mapfile -t discos < <(debkit_samba_discos_dados)
    if [ ${#discos[@]} -eq 0 ]; then
        msg_erro "$(t home.sem_discos)"
        return 1
    fi
    echo "  $(t home.discos)"
    for d in "${discos[@]}"; do echo "    $d"; done
    sugestao="${discos[0]}/homes"
    while true; do
        debkit_ler base "$(t home.p_base "$sugestao")" || return 1
        [ -z "$base" ] && base="$sugestao"
        problema=$(debkit_samba_base_problema "$base") && break
        msg_erro "$problema"
    done
    confirmar "$(t home.p_confirma_base "$base")" || return 1
    debkit_samba_definir_base "$base"
}

# A base está pronta para uso agora? Se não definida, pergunta (primeira
# vez); se definida, confere (ex: o disco de dados pode estar desmontado).
debkit_samba_garantir_base() {
    local problema
    if [ -z "$DEBKIT_HOMES_BASE" ]; then
        debkit_samba_escolher_base
        return
    fi
    if ! problema=$(debkit_samba_base_problema "$DEBKIT_HOMES_BASE"); then
        msg_erro "$(t home.base_invalida_agora "$DEBKIT_HOMES_BASE" "$problema")"
        return 1
    fi
    [ -d "$DEBKIT_HOMES_BASE" ] || debkit_samba_definir_base "$DEBKIT_HOMES_BASE"
}

# ── Pastas pessoais: criar a pasta ──────────────────────────────────────────
# debkit_samba_criar_pasta <login> <pasta> <gid> <com_skel 0|1>
# Cria a pasta (não pode existir), 700, dono o usuário e o grupo principal;
# com_skel=1 copia o /etc/skel (usuário com acesso ao servidor). Deixa
# DEBKIT_H_CRIADA=1 (para debkit_samba_remover_pasta_criada desfazer).
debkit_samba_criar_pasta() {
    local nome="$1" dir="$2" gid="$3" skel="$4"
    DEBKIT_H_CRIADA=0
    if [ -e "$dir" ] || [ -L "$dir" ]; then
        msg_erro "$(t home.ja_existe "$dir")"
        return 1
    fi
    ( umask 077; mkdir -- "$dir" ) || return 1
    DEBKIT_H_CRIADA=1
    if [ "$skel" -eq 1 ] && [ -d /etc/skel ]; then
        cp -a -- /etc/skel/. "$dir"/ || return 1
    fi
    chown -R -- "$nome:$gid" "$dir" && chmod 700 -- "$dir"
}

# Remove a pasta criada nesta operação - só se é exatamente
# HOMES_BASE/<um nome> (nunca outra coisa)
debkit_samba_remover_pasta_criada() {
    local dir="$1" resto
    [ "${DEBKIT_H_CRIADA:-0}" -eq 1 ] || return 0
    [ -n "$DEBKIT_HOMES_BASE" ] || return 1
    resto="${dir#"$DEBKIT_HOMES_BASE"/}"
    if [ "$resto" == "$dir" ] || [ -z "$resto" ] || [[ "$resto" == */* || "$resto" == .* ]]; then return 1; fi
    rm -rf -- "$dir" && DEBKIT_H_CRIADA=0
}

# ── Pastas pessoais: usuário existente ──────────────────────────────────────
# Usuários comuns sem pasta pessoal (home /nonexistent ou pasta que não existe)
debkit_samba_usuarios_sem_home() {
    local nome uid home
    while IFS=: read -r nome _ uid _ _ home _; do
        debkit_uid_comum "$uid" || continue
        if [ "$home" == "$DEBKIT_USR_HOME" ] || [ ! -d "$home" ]; then echo "$nome"; fi
    done < <(getent passwd) | sort
}

# Cria HOMES_BASE/<login> para um usuário comum que não tem pasta pessoal
# e grava no Linux (usermod -d). Base já garantida. Desfaz se algo falhar.
debkit_samba_home_existente() {
    local nome="$1" uid gid home_atual shell dir skel=1 motivo=""
    DEBKIT_H_CRIADA=0
    if ! IFS=: read -r _ _ uid gid _ home_atual shell < <(getent passwd "$nome") || ! debkit_uid_comum "$uid"; then
        msg_erro "$(t home.usuario_nao_comum "$nome")"
        return 1
    fi
    if [ "$home_atual" != "$DEBKIT_USR_HOME" ] && [ -d "$home_atual" ]; then
        msg_erro "$(t home.usuario_tem_home "$nome" "$home_atual")"
        return 1
    fi
    if ! motivo=$(debkit_samba_base_problema "$DEBKIT_HOMES_BASE") || [ ! -d "$DEBKIT_HOMES_BASE" ]; then
        msg_erro "$(t home.base_invalida_agora "$DEBKIT_HOMES_BASE" "$motivo")"
        return 1
    fi
    dir="$DEBKIT_HOMES_BASE/$nome"
    case "$shell" in */nologin|*/false) skel=0 ;; esac
    if ! debkit_samba_criar_pasta "$nome" "$dir" "$gid" "$skel"; then
        motivo="$(t home.f_criar "$dir")"
    elif ! usermod -d "$dir" -- "$nome" >/dev/null 2>&1; then
        motivo="$(t home.f_usermod)"
    elif [ "$(getent passwd "$nome" | cut -d: -f6)" != "$dir" ] || [ "$(stat -c '%u %g %a' -- "$dir")" != "$uid $gid 700" ]; then
        motivo="$(t usr.f_conferencia "home")"
    fi
    if [ -n "$motivo" ]; then
        msg_erro "$(t home.falhou "$nome" "$motivo")"
        [ "$(getent passwd "$nome" | cut -d: -f6)" == "$dir" ] && usermod -d "$home_atual" -- "$nome" >/dev/null 2>&1
        debkit_samba_remover_pasta_criada "$dir"
        debkit_auditar home_criar "nome=$nome pasta=$dir resultado=falha"
        return 1
    fi
    debkit_auditar home_criar "nome=$nome pasta=$dir resultado=ok"
    msg_ok "$(t home.criada "$dir" "$nome")"
}

# ── Compartilhamento [homes] ────────────────────────────────────────────────
# O [homes] do Samba mostra a cada usuário só a própria pasta pessoal (o
# caminho vem do Linux). O smb.conf padrão do Debian já tem um [homes], mas
# somente leitura. Estados: ok | ausente | leitura (somente leitura ou sem
# "valid users = %S") | outro (com "path" próprio ou "valid users" sem %S:
# feito à mão, o debkit não mexe).
debkit_samba_homes_param() { testparm -s --section-name=homes --parameter-name="$1" "$DEBKIT_SMB_CONF" 2>/dev/null; }

debkit_samba_homes_estado() {
    local vu
    if ! testparm -s "$DEBKIT_SMB_CONF" 2>/dev/null | grep -qx '\[homes\]'; then echo ausente; return; fi
    vu=$(debkit_samba_homes_param "valid users")
    if [ -n "$(debkit_samba_homes_param path)" ] || { [ -n "$vu" ] && [[ " $vu " != *" %S "* ]]; }; then echo outro; return; fi
    if [ "$(debkit_samba_homes_param "read only")" == "No" ] && [ -n "$vu" ]; then echo ok; else echo leitura; fi
}

# Filtro: acrescenta um [homes] no fim
debkit_samba_filtro_homes_novo() {
    cat
    printf '\n# debkit: pastas pessoais (cada usuário vê só a própria pasta)\n[homes]\n'
    printf '   comment = Pasta pessoal\n   browseable = no\n   read only = no\n   valid users = %%S\n   create mask = 0600\n   directory mask = 0700\n'
}

# Filtro: no [homes] existente, tira as linhas de escrita (read only,
# writable/writeable, write ok) e põe "read only = no" logo depois do
# cabeçalho; acrescenta "valid users = %S" se não houver
debkit_samba_filtro_homes_ajustar() {
    local vu=1
    [ -n "$(debkit_samba_homes_param "valid users")" ] && vu=0
    awk -v vu="$vu" '
        /^[ \t]*\[/ { em = (tolower($0) ~ /^[ \t]*\[homes\][ \t]*$/) ? 1 : 0
                      print
                      if (em) { print "   read only = no"; if (vu) print "   valid users = %S" }
                      next }
        em && tolower($0) ~ /^[ \t]*(read[ \t]*only|writ[e]?able|write[ \t]*ok)[ \t]*=/ { next }
        { print }'
}

# Bloco do [homes] / tudo menos ele, na saída do testparm -s (sem as linhas
# vazias, que ali só separam as seções)
debkit_samba_bloco_homes() { awk '/^\[/ { em = ($0 == "[homes]"); next } em && NF' "$1"; }
debkit_samba_sem_homes()   { awk '/^\[/ { em = ($0 == "[homes]") } !em && NF' "$1"; }

# Conferência: fora do [homes] nada muda; no [homes], além de read only/
# valid users, nada muda (no criado do zero, o resto é o que o debkit pôs);
# e o resultado é read only = No com valid users = %S
debkit_samba_conferir_homes() {
    local filtro='/^\t(read only|valid users) = /'
    cmp -s <(debkit_samba_sem_homes "$1") <(debkit_samba_sem_homes "$2") || return 1
    if [ -n "$(debkit_samba_bloco_homes "$1")" ]; then
        cmp -s <(debkit_samba_bloco_homes "$1" | awk "!$filtro") <(debkit_samba_bloco_homes "$2" | awk "!$filtro") || return 1
    fi
    debkit_samba_bloco_homes "$2" | grep -qxF $'\tread only = No' || return 1
    debkit_samba_bloco_homes "$2" | grep -qE $'^\tvalid users = (.* )?%S( |$)'
}

# Deixa o [homes] pronto (cria ou ajusta) pela edição segura do smb.conf
debkit_samba_ajustar_homes() {
    local estado rc
    estado=$(debkit_samba_homes_estado)
    case "$estado" in
        ok)      return 0 ;;
        ausente) debkit_smbconf_editar debkit_samba_filtro_homes_novo debkit_samba_conferir_homes; rc=$? ;;
        leitura) debkit_smbconf_editar debkit_samba_filtro_homes_ajustar debkit_samba_conferir_homes; rc=$? ;;
        *)       msg_aviso "$(t homes.estado_outro)"; return 1 ;;
    esac
    if [ "$rc" -eq 0 ] && [ "$(debkit_samba_homes_estado)" == "ok" ]; then
        debkit_auditar homes_ajustar "estado_antes=$estado resultado=ok"
        msg_ok "$(t homes.feito)"
        return 0
    fi
    debkit_auditar homes_ajustar "estado_antes=$estado resultado=falha"
    [ "$rc" -eq 0 ] && debkit_smbconf_restaurar
    return 1
}

# Oferece ajustar o [homes] se não estiver ok (pergunta antes)
debkit_samba_oferecer_homes() {
    case "$(debkit_samba_homes_estado)" in
        ok)      return 0 ;;
        ausente) msg_info "$(t homes.estado_ausente)"; confirmar "$(t homes.p_criar)" || { msg_info "$(t homes.aviso_depois)"; return 1; } ;;
        leitura) msg_info "$(t homes.estado_leitura)"; confirmar "$(t homes.p_liberar)" || { msg_info "$(t homes.aviso_depois)"; return 1; } ;;
        *)       msg_aviso "$(t homes.estado_outro)"; return 1 ;;
    esac
    debkit_samba_ajustar_homes
}

# ── Usuários: listar ────────────────────────────────────────────────────────
# Uma linha por usuário comum (ordem do login), campos separados por "|":
#   login|nome completo|tipo|samba|pasta pessoal|grupos (vírgula)|alerta
#   tipo:   admin (membro do sudo) | arquivos (no grupo de proteção SSH) |
#           servidor (shell de login) | nologin (shell sem login, fora do
#           grupo de proteção: o SSH ainda autentica e abre túnel)
#   samba:  ativa | desativada (flag D) | nao (sem conta)
#   alerta: tunel | so_linux | "" ; contas só no Samba vêm no fim com
#           tipo "" e samba so_samba
# Grupos: só os comuns (sem o pessoal, o de proteção e o sudo).
debkit_samba_usuarios_dados() {
    local nome uid gecos home shell tipo samba pasta alerta g grupos sudo protecao
    local -A contas=() comuns=() linux=()
    if debkit_tem_comando pdbedit; then
        while IFS=: read -r nome _ _ _ g _; do contas["$nome"]="$g"; done < <(debkit_pdbedit -L -w 2>/dev/null)
    fi
    while read -r g; do comuns["$g"]=1; done < <(debkit_samba_grupos_comuns)
    sudo=",$(getent group sudo | cut -d: -f4),"
    protecao=",$(getent group "$DEBKIT_GRUPO_USUARIOS" | cut -d: -f4),"
    while IFS=: read -r nome _ uid _ gecos home shell; do
        debkit_uid_comum "$uid" || continue
        linux["$nome"]=1
        tipo=$(debkit_samba_tipo_de "$nome" "$shell" "$sudo" "$protecao")
        if [ -z "${contas[$nome]+x}" ]; then samba=nao
        elif [[ "${contas[$nome]}" == *D* ]]; then samba=desativada
        else samba=ativa
        fi
        pasta=""
        [ "$home" != "$DEBKIT_USR_HOME" ] && [ -d "$home" ] && pasta="$home"
        grupos=""
        for g in $(id -nG -- "$nome" 2>/dev/null); do
            [ -n "${comuns[$g]+x}" ] && grupos+="${grupos:+,}$g"
        done
        alerta=""
        [ "$tipo" == "nologin" ] && alerta=tunel
        [ -z "$alerta" ] && [ "$samba" == "nao" ] && alerta=so_linux
        printf '%s|%s|%s|%s|%s|%s|%s\n' "$nome" "${gecos%%,*}" "$tipo" "$samba" "$pasta" "$grupos" "$alerta"
    done < <(getent passwd | sort -t: -k1,1)
    for nome in $(printf '%s\n' "${!contas[@]}" | sort); do
        [ -n "${linux[$nome]+x}" ] && continue
        getent passwd "$nome" >/dev/null 2>&1 && continue     # usuário de sistema com conta Samba: não lista
        printf '%s||||||so_samba\n' "$nome"
    done
}

# Tipo de um usuário (admin | arquivos | servidor | nologin), a partir do
# shell e das listas ",membros," do sudo e do grupo de proteção
debkit_samba_tipo_de() {
    local nome="$1" shell="$2" sudo="$3" protecao="$4"
    if [[ "$sudo" == *",$nome,"* ]]; then echo admin
    elif [[ "$protecao" == *",$nome,"* ]]; then echo arquivos
    else
        case "$shell" in */nologin|*/false) echo nologin ;; *) echo servidor ;; esac
    fi
}

# Tipo de um usuário pelo nome (consulta o sistema)
debkit_usuario_tipo() {
    local shell
    shell=$(getent passwd "$1" | cut -d: -f7)
    debkit_samba_tipo_de "$1" "$shell" ",$(getent group sudo | cut -d: -f4)," ",$(getent group "$DEBKIT_GRUPO_USUARIOS" | cut -d: -f4),"
}

# Completa com espaços até <largura> caracteres (conta caracteres, não
# bytes: o printf %-Ns erra com acentos)
debkit_pad() {
    local texto="$1" largura="$2"
    [ "${#texto}" -gt "$largura" ] && texto="${texto:0:$((largura - 1))}…"
    printf '%s%*s' "$texto" "$((largura - ${#texto}))" ""
}

# Mostra a tabela, o total e os alertas
debkit_samba_listar_usuarios() {
    local l nome gecos tipo samba pasta grupos alerta n_arq=0 n_srv=0 n_adm=0 n_out=0 total=0
    local -a linhas=() alertas=()
    local wl=5 wn=13 wt=8 ws=10 wh=13
    mapfile -t linhas < <(debkit_samba_usuarios_dados)
    if [ ${#linhas[@]} -eq 0 ]; then msg_info "$(t lst.nenhum)"; return 0; fi
    for l in "${linhas[@]}"; do
        IFS='|' read -r nome gecos _ _ pasta _ _ <<< "$l"
        [ "${#nome}" -gt "$wl" ] && wl=${#nome}
        [ "${#gecos}" -gt "$wn" ] && wn=${#gecos}
        [ "${#pasta}" -gt "$wh" ] && wh=${#pasta}
    done
    [ "$wn" -gt 30 ] && wn=30
    [ "$wh" -gt 40 ] && wh=40
    printf '  %s%s  %s  %s  %s  %s  %s%s\n' "$C_NEGRITO" "$(debkit_pad "$(t lst.c_login)" "$wl")" "$(debkit_pad "$(t lst.c_nome)" "$wn")" \
        "$(debkit_pad "$(t lst.c_tipo)" "$wt")" "$(debkit_pad "$(t lst.c_samba)" "$ws")" "$(debkit_pad "$(t lst.c_home)" "$wh")" "$(t lst.c_grupos)" "$C_RESET"
    for l in "${linhas[@]}"; do
        IFS='|' read -r nome gecos tipo samba pasta grupos alerta <<< "$l"
        case "$samba" in
            ativa) samba="$(t lst.s_ativa)" ;; desativada) samba="$(t lst.s_desativada)" ;; nao) samba="—" ;;
        esac
        case "$alerta" in
            so_samba) samba="$(t lst.s_so_samba)"; alertas+=("$(t lst.a_so_samba "$nome")") ;;
            so_linux) alertas+=("$(t lst.a_so_linux "$nome")") ;;
            tunel)    alertas+=("$(t lst.a_tunel "$nome" "$DEBKIT_GRUPO_USUARIOS")") ;;
        esac
        case "$tipo" in
            arquivos) n_arq=$((n_arq + 1)) ;; servidor) n_srv=$((n_srv + 1)) ;; admin) n_adm=$((n_adm + 1)) ;; nologin) n_out=$((n_out + 1)) ;;
        esac
        [ -n "$tipo" ] && { total=$((total + 1)); tipo="$(t "lst.t_$tipo")"; }
        printf '  %s  %s  %s  %s  %s  %s\n' "$(debkit_pad "$nome" "$wl")" "$(debkit_pad "${gecos:-—}" "$wn")" "$(debkit_pad "${tipo:-—}" "$wt")" \
            "$(debkit_pad "$samba" "$ws")" "$(debkit_pad "${pasta:-—}" "$wh")" "${grupos//,/, }"
    done
    echo ""
    echo "  $(t lst.total "$total" "$n_arq" "$n_srv" "$n_adm" "$n_out")"
    printf '  %s%s%s\n' "$C_CINZA" "$(t lst.legenda)" "$C_RESET"
    if [ ${#alertas[@]} -gt 0 ]; then
        echo ""
        printf '  %s%s%s\n' "$C_AMARELO" "$(t lst.titulo_alertas)" "$C_RESET"
        for l in "${alertas[@]}"; do echo "    ! $l"; done
    fi
}

debkit_samba_tela_listar_usuarios() {
    titulo "$(t lst.titulo)"
    debkit_samba_listar_usuarios
    pausar
}

# ── Usuários: trocar senha ──────────────────────────────────────────────────
# debkit_usuario_trocar_senha <login> <samba | linux | ambas>
# Nova senha em DEBKIT_U_SENHA (nunca na linha de comando). Regras:
#   - senha do Linux só para usuário com acesso ao servidor (o de arquivos
#     a mantém bloqueada; a de admin é trocada à mão com passwd);
#   - "ambas": Linux primeiro; se o Samba falhar, a do Linux volta a ser a
#     anterior (hash antigo pela entrada padrão do chpasswd -e);
#   - depois de trocar só a do Samba, confere que a do Linux não mudou.
debkit_usuario_trocar_senha() {
    local nome="$1" alvo="$2" uid tipo shadow_antes motivo=""
    if ! IFS=: read -r _ _ uid _ < <(getent passwd "$nome") || ! debkit_uid_comum "$uid"; then
        msg_erro "$(t sen.nao_comum "$nome")"; return 1
    fi
    tipo=$(debkit_usuario_tipo "$nome")
    case "$alvo" in
        samba|linux|ambas) ;;
        *) msg_erro "$(t sen.alvo_invalido "$alvo")"; return 1 ;;
    esac
    if [ "$alvo" != "samba" ]; then
        if [ "$tipo" == "admin" ]; then msg_erro "$(t sen.linux_admin "$nome")"; return 1; fi
        if [ "$tipo" != "servidor" ]; then msg_erro "$(t sen.linux_nao_permitida "$nome")"; return 1; fi
    fi
    if [ "$alvo" != "linux" ] && ! debkit_samba_conta_existe "$nome"; then
        msg_erro "$(t sen.sem_samba "$nome")"; return 1
    fi
    if [ "${#DEBKIT_U_SENHA}" -lt "$DEBKIT_SENHA_MIN" ]; then msg_erro "$(t usr.senha_curta "$DEBKIT_SENHA_MIN")"; return 1; fi
    if [ "${#DEBKIT_U_SENHA}" -gt "$DEBKIT_USR_SENHA_MAX" ]; then msg_erro "$(t usr.senha_longa "$DEBKIT_USR_SENHA_MAX")"; return 1; fi
    shadow_antes=$(getent shadow "$nome" | cut -d: -f2)

    # 1. Linux
    if [ "$alvo" != "samba" ]; then
        if ! printf '%s:%s\n' "$nome" "$DEBKIT_U_SENHA" | chpasswd >/dev/null 2>&1 \
           || [ "$(passwd -S -- "$nome" 2>/dev/null | awk '{print $2}')" != "P" ]; then
            debkit_senha_linux_restaurar "$nome" "$shadow_antes"
            msg_erro "$(t sen.falhou "$nome" "$(t sen.f_linux)")"
            debkit_auditar senha_trocar "nome=$nome alvo=$alvo resultado=falha motivo=linux"
            return 1
        fi
    fi
    # 2. Samba
    if [ "$alvo" != "linux" ]; then
        if ! printf '%s\n%s\n' "$DEBKIT_U_SENHA" "$DEBKIT_U_SENHA" | debkit_smbpasswd -s -- "$nome" >/dev/null 2>&1; then
            msg_erro "$(t sen.falhou "$nome" "$(t sen.f_samba)")"
            if [ "$alvo" == "ambas" ] && debkit_senha_linux_restaurar "$nome" "$shadow_antes"; then
                msg_info "$(t sen.linux_restaurada)"
            fi
            debkit_auditar senha_trocar "nome=$nome alvo=$alvo resultado=falha motivo=samba"
            return 1
        fi
    fi
    # 3. Só o Samba: a senha do Linux não pode ter mudado
    if [ "$alvo" == "samba" ] && [ "$(getent shadow "$nome" | cut -d: -f2)" != "$shadow_antes" ]; then
        debkit_senha_linux_restaurar "$nome" "$shadow_antes"
        motivo="$(t sen.f_bloqueio)"
        msg_aviso "$(t sen.falhou "$nome" "$motivo")"
        debkit_auditar senha_trocar "nome=$nome alvo=$alvo resultado=falha motivo=linux_mudou"
        return 1
    fi
    debkit_auditar senha_trocar "nome=$nome alvo=$alvo resultado=ok"
    msg_ok "$(t sen.trocada "$nome" "$(t "sen.a_$alvo")")"
}

# Volta o campo de senha do shadow ao valor anterior (hash ou "!"), pela
# entrada padrão do chpasswd -e. Retorna 0 se ficou igual ao anterior.
debkit_senha_linux_restaurar() {
    local nome="$1" antes="$2"
    [ "$(getent shadow "$nome" | cut -d: -f2)" == "$antes" ] && return 0
    printf '%s:%s\n' "$nome" "$antes" | chpasswd -e >/dev/null 2>&1
    [ "$(getent shadow "$nome" | cut -d: -f2)" == "$antes" ]
}

# Tela: escolhe o usuário, qual senha (se tiver acesso ao servidor) e lê a nova
debkit_samba_tela_trocar_senha() {
    local escolha nome tipo samba alvo prompt i l rc
    local -a nomes=() tipos=() sambas=()
    titulo "$(t sen.titulo)"
    if ! debkit_samba_ambiente_pronto; then msg_erro "$(t usr.ambiente_nao_pronto)"; pausar; return 1; fi
    while IFS='|' read -r nome _ tipo samba _ _ _; do
        [ -n "$tipo" ] || continue                                    # só no Samba
        [ "$samba" != "nao" ] || [ "$tipo" == "servidor" ] || continue  # nada a trocar
        nomes+=("$nome"); tipos+=("$tipo"); sambas+=("$samba")
    done < <(debkit_samba_usuarios_dados)
    if [ ${#nomes[@]} -eq 0 ]; then msg_info "$(t sen.sem_usuarios)"; pausar; return 0; fi
    echo "  $(t sen.titulo_usuarios)"
    for i in "${!nomes[@]}"; do echo "    $((i + 1))) $(debkit_pad "${nomes[$i]}" 20) $(t "lst.t_${tipos[$i]}")"; done
    while true; do
        debkit_ler escolha "$(t sen.p_usuario)" || { msg_aviso "$(t usr.cancelado)"; return 1; }
        [ -z "$escolha" ] && { msg_aviso "$(t usr.cancelado)"; return 1; }
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$((10#$escolha))" -ge 1 ] && [ "$((10#$escolha))" -le ${#nomes[@]} ]; then
            i=$((10#$escolha - 1)); break
        fi
        msg_erro "$(t geral.opcao_invalida "$escolha")"
    done
    nome="${nomes[$i]}"; tipo="${tipos[$i]}"; samba="${sambas[$i]}"
    echo ""
    case "$tipo" in
        servidor)
            if [ "$samba" == "nao" ]; then
                alvo=linux
            else
                echo "  $(t sen.titulo_qual)"
                echo "    1) $(t sen.q_samba)"; echo "    2) $(t sen.q_linux)"; echo "    3) $(t sen.q_ambas)"
                while true; do
                    debkit_ler l "$(t sen.p_qual)" || { msg_aviso "$(t usr.cancelado)"; return 1; }
                    case "$l" in 1) alvo=samba; break ;; 2) alvo=linux; break ;; ""|3) alvo=ambas; break ;;
                                 *) msg_erro "$(t geral.opcao_invalida "$l")" ;; esac
                done
            fi ;;
        admin) alvo=samba; msg_info "$(t sen.admin_info "$nome")" ;;
        *)     alvo=samba; msg_info "$(t sen.so_samba_info "$nome" "$(t "lst.t_$tipo")")" ;;
    esac
    case "$alvo" in samba) prompt="$(t sen.p_nova_samba)" ;; linux) prompt="$(t sen.p_nova_linux)" ;; *) prompt="$(t sen.p_nova_ambas)" ;; esac
    DEBKIT_U_SENHA=""
    debkit_ler_senha DEBKIT_U_SENHA "$prompt" || { msg_aviso "$(t usr.cancelado)"; return 1; }
    debkit_usuario_trocar_senha "$nome" "$alvo"; rc=$?
    DEBKIT_U_SENHA=""
    pausar
    return "$rc"
}

# ── Usuários: consistência ──────────────────────────────────────────────────
# Seção 3.4 (e as regras 3.1/3.2): acha e corrige, uma a uma e com
# confirmação, as contas fora do padrão. Uma por linha "tipo|login":
#   so_samba    conta Samba sem usuário no Linux       -> apagar a conta Samba
#   so_linux    usuário comum sem conta no Samba       -> criar a senha do Samba
#   tunel       shell sem login fora do grupo de proteção (SSH ainda autentica
#               e abre túnel)                          -> pôr no grupo de proteção
#   senha_linux usuário de arquivos com senha do Linux utilizável -> bloquear
debkit_samba_inconsistencias() {
    local nome tipo samba alerta
    while IFS='|' read -r nome _ tipo samba _ _ alerta; do
        if [ "$alerta" == "so_samba" ]; then echo "so_samba|$nome"; continue; fi
        [ "$samba" == "nao" ] && echo "so_linux|$nome"
        [ "$tipo" == "nologin" ] && echo "tunel|$nome"
        if [ "$tipo" == "arquivos" ] && [ "$(passwd -S -- "$nome" 2>/dev/null | awk '{print $2}')" != "L" ]; then
            echo "senha_linux|$nome"
        fi
    done < <(debkit_samba_usuarios_dados)
    return 0
}

# so_samba: apaga a conta Samba órfã (só se não há usuário com esse nome)
debkit_consist_so_samba() {
    local nome="$1"
    if getent passwd "$nome" >/dev/null 2>&1 || ! debkit_samba_conta_existe "$nome"; then
        msg_erro "$(t cns.nao_se_aplica "$nome")"; return 1
    fi
    if ! debkit_pdbedit -x -u "$nome" >/dev/null 2>&1 || debkit_samba_conta_existe "$nome"; then
        msg_erro "$(t cns.falhou "$nome" "$(t cns.f_pdbedit)")"
        debkit_auditar consistencia "acao=so_samba nome=$nome resultado=falha"; return 1
    fi
    debkit_auditar consistencia "acao=so_samba nome=$nome resultado=ok"
    msg_ok "$(t cns.ok_so_samba "$nome")"
}

# so_linux: cria a conta Samba com a senha em DEBKIT_U_SENHA (usuário de
# arquivos: confere depois que a senha do Linux continua como estava)
debkit_consist_so_linux() {
    local nome="$1" uid shadow_antes
    if ! IFS=: read -r _ _ uid _ < <(getent passwd "$nome") || ! debkit_uid_comum "$uid" || debkit_samba_conta_existe "$nome"; then
        msg_erro "$(t cns.nao_se_aplica "$nome")"; return 1
    fi
    if [ "${#DEBKIT_U_SENHA}" -lt "$DEBKIT_SENHA_MIN" ]; then msg_erro "$(t usr.senha_curta "$DEBKIT_SENHA_MIN")"; return 1; fi
    if [ "${#DEBKIT_U_SENHA}" -gt "$DEBKIT_USR_SENHA_MAX" ]; then msg_erro "$(t usr.senha_longa "$DEBKIT_USR_SENHA_MAX")"; return 1; fi
    shadow_antes=$(getent shadow "$nome" | cut -d: -f2)
    if ! printf '%s\n%s\n' "$DEBKIT_U_SENHA" "$DEBKIT_U_SENHA" | debkit_smbpasswd -s -a -- "$nome" >/dev/null 2>&1 \
       || ! debkit_samba_conta_existe "$nome"; then
        msg_erro "$(t cns.falhou "$nome" "$(t usr.f_samba)")"
        debkit_auditar consistencia "acao=so_linux nome=$nome resultado=falha"; return 1
    fi
    if [ "$(getent shadow "$nome" | cut -d: -f2)" != "$shadow_antes" ]; then
        debkit_senha_linux_restaurar "$nome" "$shadow_antes"
        msg_aviso "$(t cns.linux_restaurada "$nome")"
    fi
    debkit_auditar consistencia "acao=so_linux nome=$nome resultado=ok"
    msg_ok "$(t cns.ok_so_linux "$nome")"
}

# tunel: põe no grupo de proteção (o SSH passa a recusar; sessões SSH já
# abertas continuam até sair)
debkit_consist_tunel() {
    local nome="$1"
    if [ "$(debkit_usuario_tipo "$nome")" != "nologin" ]; then msg_erro "$(t cns.nao_se_aplica "$nome")"; return 1; fi
    if ! gpasswd -a "$nome" "$DEBKIT_GRUPO_USUARIOS" >/dev/null 2>&1 \
       || ! id -nG -- "$nome" 2>/dev/null | tr ' ' '\n' | grep -qxF "$DEBKIT_GRUPO_USUARIOS"; then
        msg_erro "$(t cns.falhou "$nome" "$(t cns.f_grupo "$DEBKIT_GRUPO_USUARIOS")")"
        debkit_auditar consistencia "acao=tunel nome=$nome resultado=falha"; return 1
    fi
    debkit_auditar consistencia "acao=tunel nome=$nome resultado=ok"
    msg_ok "$(t cns.ok_tunel "$nome" "$DEBKIT_GRUPO_USUARIOS")"
}

# senha_linux: bloqueia a senha do Linux do usuário de arquivos ("!", como
# na criação; a do Samba não muda)
debkit_consist_senha_linux() {
    local nome="$1"
    if [ "$(debkit_usuario_tipo "$nome")" != "arquivos" ]; then msg_erro "$(t cns.nao_se_aplica "$nome")"; return 1; fi
    if ! usermod -p '!' -- "$nome" >/dev/null 2>&1 || [ "$(passwd -S -- "$nome" 2>/dev/null | awk '{print $2}')" != "L" ]; then
        msg_erro "$(t cns.falhou "$nome" "$(t cns.f_bloqueio)")"
        debkit_auditar consistencia "acao=senha_linux nome=$nome resultado=falha"; return 1
    fi
    debkit_auditar consistencia "acao=senha_linux nome=$nome resultado=ok"
    msg_ok "$(t cns.ok_senha_linux "$nome")"
}

# ── Usuários: excluir ───────────────────────────────────────────────────────
# Decisão de 19/10/2026 (seção 3.4): apaga do Linux, do Samba e a pasta
# pessoal, com UMA confirmação (s/n) depois de mostrar o que será perdido.

# Quem está rodando o debkit (o administrador por trás do sudo)
debkit_quem_roda() { echo "${SUDO_USER:-$(logname 2>/dev/null || id -un)}"; }

# Imprime o motivo (mensagem) se o usuário NÃO pode ser excluído e retorna 1
debkit_usuario_exclusao_problema() {
    local nome="$1" uid usos outros
    if ! IFS=: read -r _ _ uid _ < <(getent passwd "$nome") || ! debkit_uid_comum "$uid"; then
        t sen.nao_comum "$nome"; return 1
    fi
    if [ "$(debkit_usuario_tipo "$nome")" == "admin" ]; then t rmu.admin "$nome"; return 1; fi
    if [ "$nome" == "$(debkit_quem_roda)" ]; then t rmu.proprio "$nome"; return 1; fi
    usos=$(debkit_samba_grupo_usos "$nome" | sed 's/.*/[&]/' | paste -sd' ')
    if [ -n "$usos" ]; then t rmu.grupo_no_smb "$nome" "$usos"; return 1; fi
    outros=$(debkit_usuario_processos "$nome" | paste -sd' ')
    if [ -n "$outros" ]; then t rmu.processos "$nome" "$outros"; return 1; fi
    return 0
}

# Processos do usuário que NÃO são sessões do Samba (ex: SSH aberto): o
# userdel recusa e o debkit não os mata. Imprime "pid(comando)".
debkit_usuario_processos() {
    local pid
    local -A samba=()
    for pid in $(debkit_samba_sessoes "$1"); do samba["$pid"]=1; done
    pgrep -u "$1" 2>/dev/null | while read -r pid; do
        [ -n "${samba[$pid]+x}" ] && continue
        [[ "$(cat "/proc/$pid/comm" 2>/dev/null)" == smbd* ]] && continue
        echo "$pid($(cat "/proc/$pid/comm" 2>/dev/null))"
    done
}

# A pasta pessoal pode ser apagada? Só se for <HOMES_BASE ou /home>/<algo>,
# pasta de verdade (não link), do próprio usuário e de mais ninguém.
# Imprime: "apagar" | "nenhuma" | "manter:<motivo>"
debkit_usuario_home_destino() {
    local nome="$1" uid home pai
    IFS=: read -r _ _ uid _ _ home _ < <(getent passwd "$nome")
    if [ "$home" == "$DEBKIT_USR_HOME" ] || { [ ! -e "$home" ] && [ ! -L "$home" ]; }; then echo nenhuma; return; fi
    if [ -L "$home" ] || [ ! -d "$home" ]; then echo "manter:$(t rmu.h_nao_pasta)"; return; fi
    pai=$(dirname -- "$home")
    if [ "$pai" != "/home" ] && { [ -z "$DEBKIT_HOMES_BASE" ] || [ "$pai" != "${DEBKIT_HOMES_BASE%/}" ]; }; then
        echo "manter:$(t rmu.h_fora)"; return
    fi
    if [ "$(stat -c %u -- "$home" 2>/dev/null)" != "$uid" ]; then echo "manter:$(t rmu.h_dono)"; return; fi
    if [ "$(getent passwd | awk -F: -v h="$home" -v n="$nome" '$6 == h && $1 != n' | wc -l)" -gt 0 ]; then
        echo "manter:$(t rmu.h_outro)"; return
    fi
    echo apagar
}

# debkit_usuario_excluir <login>: confere de novo as travas, encerra as
# sessões do Samba, apaga o usuário Linux (userdel, NUNCA -r), a conta
# Samba, a pasta pessoal (se pode) e o grupo pessoal que sobrar vazio.
# Se o userdel falhar, nada foi apagado.
debkit_usuario_excluir() {
    local nome="$1" motivo uid gid home destino grupos avisos=0
    if ! motivo=$(debkit_usuario_exclusao_problema "$nome"); then
        msg_erro "$(t rmu.falhou "$nome" "$motivo")"; return 1
    fi
    IFS=: read -r _ _ uid gid _ home _ < <(getent passwd "$nome")
    destino=$(debkit_usuario_home_destino "$nome")
    grupos=$(id -nG -- "$nome" 2>/dev/null | tr ' ' ',')
    msg_info "$(t rmu.excluindo "$nome")"
    # 1. Sessões do Samba (o userdel recusa usuário com processo)
    if ! debkit_samba_encerrar_sessoes "$nome"; then
        msg_erro "$(t rmu.falhou "$nome" "$(t rmu.f_sessoes)")"
        debkit_auditar usuario_excluir "nome=$nome resultado=falha motivo=sessoes"
        return 1
    fi
    [ ${#DEBKIT_SES_PIDS[@]} -gt 0 ] && msg_info "$(t rmu.sessoes_encerradas "${#DEBKIT_SES_PIDS[@]}")"
    # 2. Usuário Linux (tira também dos grupos; o grupo pessoal sai junto)
    if ! userdel -- "$nome" >/dev/null 2>&1 || getent passwd "$nome" >/dev/null 2>&1; then
        msg_erro "$(t rmu.falhou "$nome" "$(t rmu.f_userdel)")"
        debkit_auditar usuario_excluir "nome=$nome resultado=falha motivo=userdel"
        return 1
    fi
    # 3. Conta Samba
    if debkit_samba_conta_existe "$nome"; then
        if ! debkit_pdbedit -x -u "$nome" >/dev/null 2>&1 || debkit_samba_conta_existe "$nome"; then
            msg_aviso "$(t rmu.f_samba "$nome")"; avisos=1
        fi
    fi
    # 4. Pasta pessoal
    case "$destino" in
        apagar)
            if rm -rf --one-file-system -- "$home" && [ ! -e "$home" ]; then
                msg_info "$(t rmu.home_apagada "$home")"
            else
                msg_aviso "$(t rmu.f_home "$home")"; avisos=1
            fi ;;
        manter:*) msg_aviso "$(t rmu.home_mantida "$home" "${destino#manter:}")" ;;
    esac
    # 5. Grupo pessoal que sobrou (o userdel não apaga se for o principal de outro)
    if getent group "$nome" >/dev/null 2>&1 && [ "$(getent group "$nome" | cut -d: -f3)" == "$gid" ]; then
        if [ -z "$(getent group "$nome" | cut -d: -f4)" ] && [ -z "$(debkit_grupo_principais "$nome")" ]; then
            groupdel -- "$nome" >/dev/null 2>&1
        else
            msg_aviso "$(t rmu.grupo_mantido "$nome")"
        fi
    fi
    debkit_auditar usuario_excluir "nome=$nome uid=$uid grupos=$grupos home=$home pasta=${destino%%:*} avisos=$avisos resultado=ok"
    msg_ok "$(t rmu.excluido "$nome")"
}

# ── Grupos: regras e consultas ──────────────────────────────────────────────
# Decisão de 19/10/2026 (planejamento, 3.6). Nome do grupo: as regras do
# login, sem os reservados, sem o que já existe (grupo ou usuário) e sem
# nomes começando por "debkit" (grupos do próprio debkit).
DEBKIT_GRP_RESERVADOS=(users sudo adm staff wheel admins sambashare)

# Imprime o problema do nome do grupo novo (mensagem) e retorna 1; 0 = livre e válido
debkit_grupo_nome_problema() {
    local nome="$1" r
    if [ -z "$nome" ]; then t grp.nome_vazio; return 1; fi
    if [ "${#nome}" -lt 2 ] || [ "${#nome}" -gt 32 ]; then t usr.nome_tamanho "$nome" "${#nome}"; return 1; fi
    local l="$DEBKIT_MINUSCULAS" ld="$DEBKIT_MINUSCULAS$DEBKIT_DIGITOS"   # sem intervalos: ver núcleo
    if [[ ! "$nome" =~ ^[$l][$ld]*(_[$ld]+)*$ ]]; then t grp.nome_formato "$nome"; return 1; fi
    for r in "${DEBKIT_USR_RESERVADOS[@]}" "${DEBKIT_GRP_RESERVADOS[@]}"; do
        if [ "$nome" == "$r" ]; then t usr.nome_reservado "$nome"; return 1; fi
    done
    if [[ "$nome" == debkit* ]]; then t grp.nome_debkit "$nome"; return 1; fi
    if getent group "$nome" >/dev/null 2>&1; then t grp.nome_existe "$nome"; return 1; fi
    if getent passwd "$nome" >/dev/null 2>&1; then t grp.nome_usuario_existe "$nome"; return 1; fi
    if debkit_grupos_sudoers | grep -qxF -- "$nome"; then t grp.nome_sudoers "$nome"; return 1; fi
    return 0
}

# O grupo é um dos que o debkit gerencia? (comum, sem os pessoais e o de proteção)
debkit_grupo_gerenciado() { [ -n "$1" ] && debkit_samba_grupos_comuns | grep -qxF -- "$1"; }

# Membros listados no grupo (os "suplementares"; um por linha, em ordem)
debkit_grupo_membros() {
    getent group "$1" | cut -d: -f4 | tr ',' '\n' | sed '/^$/d' | sort
}

# Usuários que têm o grupo como grupo principal (um por linha, em ordem)
debkit_grupo_principais() {
    local gid
    gid=$(getent group "$1" | cut -d: -f3)
    [ -n "$gid" ] || return 0
    getent passwd | awk -F: -v g="$gid" '$4 == g {print $1}' | sort
}

# Usuários comuns (UID na faixa do login.defs; um por linha, em ordem)
debkit_samba_usuarios_comuns() {
    local nome uid
    while IFS=: read -r nome _ uid _; do
        debkit_uid_comum "$uid" && echo "$nome"
    done < <(getent passwd) | sort -u
}

# Compartilhamentos do smb.conf que usam o grupo (um por linha): "@g", "+g",
# "&g" em valid/invalid users, read/write list e admin users, e force group
debkit_samba_grupo_usos() {
    testparm -s "$DEBKIT_SMB_CONF" 2>/dev/null | awk -v g="$1" '
        /^\[/ { sec = substr($0, 2, length($0) - 2); next }
        {
            linha = $0; sub(/^[ \t]+/, "", linha)
            p = linha; sub(/[ \t]*=.*/, "", p); p = tolower(p)
            v = linha; if (!sub(/^[^=]*=[ \t]*/, "", v)) next
            if (p == "force group") {
                sub(/^\+/, "", v); if (v == g) usa[sec] = 1
            } else if (p ~ /^(valid users|invalid users|read list|write list|admin users)$/) {
                n = split(v, tok, /[ ,]+/)
                for (i = 1; i <= n; i++) {
                    x = tok[i]; gsub(/"/, "", x)
                    if (x ~ /^[@+&]/) { sub(/^[@+&]+/, "", x); if (x == g) usa[sec] = 1 }
                }
            }
        }
        END { for (s in usa) print s }' | sort
}

# Compartilhamentos que citam o USUÁRIO pelo nome (sem @ + &) nas listas de
# usuários, ou em force user (um por linha)
debkit_samba_usuario_usos() {
    testparm -s "$DEBKIT_SMB_CONF" 2>/dev/null | awk -v u="$1" '
        /^\[/ { sec = substr($0, 2, length($0) - 2); next }
        {
            linha = $0; sub(/^[ \t]+/, "", linha)
            p = linha; sub(/[ \t]*=.*/, "", p); p = tolower(p)
            v = linha; if (!sub(/^[^=]*=[ \t]*/, "", v)) next
            if (p == "force user") { if (v == u) usa[sec] = 1 }
            else if (p ~ /^(valid users|invalid users|read list|write list|admin users)$/) {
                n = split(v, tok, /[ ,]+/)
                for (i = 1; i <= n; i++) { x = tok[i]; gsub(/"/, "", x); if (x == u) usa[sec] = 1 }
            }
        }
        END { for (s in usa) print s }' | sort
}

# Pastas onde procurar arquivos de um grupo: a base das pastas pessoais e os
# caminhos dos compartilhamentos (sem variáveis como %U), sem repetir pasta
# que já está dentro de outra da lista
debkit_samba_pastas_dados() {
    local p q dentro
    local -a todas=()
    mapfile -t todas < <({
        [ -n "$DEBKIT_HOMES_BASE" ] && echo "$DEBKIT_HOMES_BASE"
        testparm -s "$DEBKIT_SMB_CONF" 2>/dev/null | awk '
            /^\[/ { sec = tolower(substr($0, 2, length($0) - 2)); next }
            sec != "global" && sec != "homes" && sec != "printers" && sec != "print$" && $1 == "path" && $2 == "=" {
                v = $0; sub(/^[^=]*=[ \t]*/, "", v); if (v !~ /%/) print v }'
    } | sed 's:/*$::; /^$/d' | sort -u)
    for p in "${todas[@]}"; do
        if [ ! -d "$p" ] || [ -L "$p" ]; then continue; fi
        dentro=0
        for q in "${todas[@]}"; do
            [ "$q" != "$p" ] && [[ "$p" == "$q"/* ]] && dentro=1
        done
        [ "$dentro" -eq 0 ] && echo "$p"
    done
}

DEBKIT_GRP_ARQUIVOS_MAX=1000
# debkit_contar_arquivos <-group|-user> <número> [pasta a ignorar]
# Conta (até GRP_ARQUIVOS_MAX) os arquivos e pastas do GID/UID nas pastas de
# dados, sem entrar na pasta a ignorar (ex: a pasta pessoal que vai ser
# apagada). Imprime o número.
debkit_contar_arquivos() {
    local teste="$1" id="$2" ignorar="${3:-}" p
    local -a pastas=()
    mapfile -t pastas < <(debkit_samba_pastas_dados)
    for p in "${pastas[@]}"; do
        if [ -n "$ignorar" ]; then
            find "$p" -xdev -path "$ignorar" -prune -o "$teste" "$id" -printf '.\n' 2>/dev/null
        else
            find "$p" -xdev "$teste" "$id" -printf '.\n' 2>/dev/null
        fi
    done | head -n "$DEBKIT_GRP_ARQUIVOS_MAX" | wc -l
}
debkit_grupo_contar_arquivos() { debkit_contar_arquivos -group "$1"; }

# ── Sessões do Samba ────────────────────────────────────────────────────────
# O Samba lê os grupos do usuário só quando a sessão começa (e o Windows
# reaproveita a sessão para todas as pastas): para entrar/sair de um grupo
# valer na hora, as sessões abertas do usuário são encerradas e o Windows
# reconecta sozinho, já com os grupos novos (decisão de 19/10/2026: sempre).

# PIDs do smbd com sessão aberta do usuário (um por linha)
debkit_samba_sessoes() {
    LC_ALL=C smbstatus -s "$DEBKIT_SMB_CONF" -p 2>/dev/null | awk -v u="$1" '$1 ~ /^[0-9]+$/ && $2 == u {print $1}' | sort -u
}

# Dos usuários indicados, imprime os que estão conectados agora (um por linha)
debkit_samba_conectados() {
    local u
    for u in "$@"; do [ -n "$(debkit_samba_sessoes "$u")" ] && echo "$u"; done
    return 0
}

# Encerra as sessões abertas do usuário (smbcontrol <pid> shutdown; se não
# adiantar, TERM no processo, só se for um smbd) e confere que acabaram.
# Deixa em DEBKIT_SES_PIDS os PIDs encontrados. Retorna 1 se alguma ficou.
debkit_samba_encerrar_sessoes() {
    local pid i vivos=""
    mapfile -t DEBKIT_SES_PIDS < <(debkit_samba_sessoes "$1")
    [ ${#DEBKIT_SES_PIDS[@]} -gt 0 ] || return 0
    for pid in "${DEBKIT_SES_PIDS[@]}"; do
        smbcontrol -s "$DEBKIT_SMB_CONF" "$pid" shutdown >/dev/null 2>&1
    done
    for (( i = 0; i < 25; i++ )); do
        vivos=""
        for pid in "${DEBKIT_SES_PIDS[@]}"; do kill -0 "$pid" 2>/dev/null && vivos+=" $pid"; done
        [ -z "$vivos" ] && return 0
        [ "$i" -eq 10 ] && for pid in $vivos; do
            [[ "$(cat "/proc/$pid/comm" 2>/dev/null)" == smbd* ]] && kill -TERM "$pid" 2>/dev/null
        done
        sleep 0.2
    done
    return 1
}

# Refaz as sessões abertas dos usuários (o Windows reconecta com os grupos
# novos). Retorna 1 se alguma sessão não foi encerrada.
debkit_samba_reconectar() {
    local u rc=0 pids
    for u in "$@"; do
        if debkit_samba_encerrar_sessoes "$u"; then
            [ ${#DEBKIT_SES_PIDS[@]} -gt 0 ] || continue
            pids=$(IFS=,; echo "${DEBKIT_SES_PIDS[*]}")
            msg_info "$(t ses.reconectado "$u" "${#DEBKIT_SES_PIDS[@]}")"
            debkit_auditar samba_reconectar "usuario=$u pids=$pids resultado=ok"
        else
            pids=$(IFS=,; echo "${DEBKIT_SES_PIDS[*]}")
            msg_aviso "$(t ses.falhou "$u")"
            debkit_auditar samba_reconectar "usuario=$u pids=$pids resultado=falha"
            rc=1
        fi
    done
    return "$rc"
}

# ── Grupos: criar ───────────────────────────────────────────────────────────
# Entrada: DEBKIT_G_NOME e DEBKIT_G_MEMBROS (array de usuários comuns).
# Tudo ou nada: cria o grupo comum (groupadd, GID da faixa do login.defs),
# define os membros de uma vez (gpasswd -M), confere e, se algo falhar,
# apaga o grupo que criou.
debkit_grupo_criar() {
    local nome="$DEBKIT_G_NOME" gid u motivo="" esperado
    local -a membros=()
    DEBKIT_G_FEITO=0
    if ! motivo=$(debkit_grupo_nome_problema "$nome"); then
        msg_erro "$(t grp.falhou "$nome" "$motivo")"; return 1
    fi
    for u in "${DEBKIT_G_MEMBROS[@]}"; do
        if ! debkit_samba_usuarios_comuns | grep -qxF -- "$u"; then
            msg_erro "$(t grp.falhou "$nome" "$(t grp.nao_usuario_comum "$u")")"; return 1
        fi
        [[ " ${membros[*]} " == *" $u "* ]] || membros+=("$u")
    done
    [ ${#membros[@]} -gt 0 ] && mapfile -t membros < <(printf '%s\n' "${membros[@]}" | sort)
    msg_info "$(t grp.criando "$nome")"
    if ! groupadd -- "$nome" >/dev/null 2>&1; then
        debkit_grupo_falhou "$(t grp.f_groupadd)"; return 1
    fi
    DEBKIT_G_FEITO=1
    gid=$(getent group "$nome" | cut -d: -f3)
    if ! debkit_gid_comum "$gid"; then
        debkit_grupo_falhou "$(t grp.f_gid "$gid")"; return 1
    fi
    if [ ${#membros[@]} -gt 0 ] && ! gpasswd -M "$(IFS=,; echo "${membros[*]}")" -- "$nome" >/dev/null 2>&1; then
        debkit_grupo_falhou "$(t grp.f_membros)"; return 1
    fi
    # Conferência final (resultado real)
    esperado=$(printf '%s\n' "${membros[@]}" | sed '/^$/d' | sort)
    [ "$(debkit_grupo_membros "$nome")" == "$esperado" ] || motivo="membros"
    debkit_grupo_gerenciado "$nome" || motivo="grupo comum"
    if [ -n "$motivo" ]; then
        debkit_grupo_falhou "$(t usr.f_conferencia "$motivo")"; return 1
    fi
    debkit_auditar grupo_criar "nome=$nome gid=$gid membros=$(IFS=,; echo "${membros[*]}") resultado=ok"
    msg_ok "$(t grp.criado "$nome")"
    debkit_samba_reconectar "${membros[@]}"
    return 0
}

# Falha no meio da criação: informa, apaga o grupo que foi criado e audita
debkit_grupo_falhou() {
    local nome="$DEBKIT_G_NOME"
    msg_erro "$(t grp.falhou "$nome" "$1")"
    debkit_auditar grupo_criar "nome=$nome resultado=falha motivo=$1"
    [ "$DEBKIT_G_FEITO" -eq 1 ] || return 0
    groupdel -- "$nome" >/dev/null 2>&1
    if getent group "$nome" >/dev/null 2>&1; then
        msg_erro "$(t grp.desfazer_falhou "$nome")"
    else
        DEBKIT_G_FEITO=0
        msg_info "$(t usr.desfeito)"
        debkit_auditar grupo_criar "nome=$nome resultado=desfeito"
    fi
}

# ── Grupos: entrar e sair ───────────────────────────────────────────────────
# debkit_grupo_alterar_membros <grupo>; entrada: DEBKIT_G_ENTRAR e
# DEBKIT_G_SAIR (arrays de usuários comuns). Troca a lista de uma vez
# (gpasswd -M), mantendo os outros membros; confere e, se não conferir,
# volta a lista anterior.
debkit_grupo_alterar_membros() {
    local grupo="$1" u antes depois esperado
    local -a atuais=() novos=() principais=()
    if ! debkit_grupo_gerenciado "$grupo"; then msg_erro "$(t grp.nao_gerenciado "$grupo")"; return 1; fi
    if [ $((${#DEBKIT_G_ENTRAR[@]} + ${#DEBKIT_G_SAIR[@]})) -eq 0 ]; then msg_erro "$(t grp.nada_a_fazer)"; return 1; fi
    mapfile -t atuais < <(getent group "$grupo" | cut -d: -f4 | tr ',' '\n' | sed '/^$/d')   # na ordem do arquivo
    mapfile -t principais < <(debkit_grupo_principais "$grupo")
    for u in "${DEBKIT_G_ENTRAR[@]}" "${DEBKIT_G_SAIR[@]}"; do
        if ! debkit_samba_usuarios_comuns | grep -qxF -- "$u"; then msg_erro "$(t grp.nao_usuario_comum "$u")"; return 1; fi
        if [[ " ${principais[*]} " == *" $u "* ]]; then msg_erro "$(t grp.e_principal "$u" "$grupo")"; return 1; fi
    done
    for u in "${DEBKIT_G_ENTRAR[@]}"; do
        if [[ " ${atuais[*]} " == *" $u "* ]]; then msg_erro "$(t grp.ja_membro "$u" "$grupo")"; return 1; fi
        if [[ " ${DEBKIT_G_SAIR[*]} " == *" $u "* ]]; then msg_erro "$(t grp.entrar_e_sair "$u")"; return 1; fi
    done
    for u in "${DEBKIT_G_SAIR[@]}"; do
        if [[ " ${atuais[*]} " != *" $u "* ]]; then msg_erro "$(t grp.nao_membro "$u" "$grupo")"; return 1; fi
    done
    for u in "${atuais[@]}"; do
        [[ " ${DEBKIT_G_SAIR[*]} " == *" $u "* ]] || novos+=("$u")
    done
    for u in "${DEBKIT_G_ENTRAR[@]}"; do
        [[ " ${novos[*]} " == *" $u "* ]] || novos+=("$u")
    done
    antes=$(IFS=,; echo "${atuais[*]}")
    depois=$(IFS=,; echo "${novos[*]}")
    esperado=$(printf '%s\n' "${novos[@]}" | sed '/^$/d' | sort)
    if ! gpasswd -M "$depois" -- "$grupo" >/dev/null 2>&1 || [ "$(debkit_grupo_membros "$grupo")" != "$esperado" ]; then
        gpasswd -M "$antes" -- "$grupo" >/dev/null 2>&1
        if [ "$(debkit_grupo_membros "$grupo")" == "$(printf '%s\n' "${atuais[@]}" | sed '/^$/d' | sort)" ]; then
            msg_erro "$(t grp.membros_falhou "$grupo")"
        else
            msg_erro "$(t grp.membros_desfazer_falhou "$grupo")"
        fi
        debkit_auditar grupo_membros "grupo=$grupo resultado=falha"
        return 1
    fi
    debkit_auditar grupo_membros "grupo=$grupo entraram=$(IFS=,; echo "${DEBKIT_G_ENTRAR[*]}") sairam=$(IFS=,; echo "${DEBKIT_G_SAIR[*]}") resultado=ok"
    msg_ok "$(t grp.membros_ok "$grupo")"
    debkit_samba_reconectar "${DEBKIT_G_ENTRAR[@]}" "${DEBKIT_G_SAIR[@]}"
    return 0
}

# ── Grupos: remover ─────────────────────────────────────────────────────────
# debkit_grupo_remover <grupo>: só grupo gerenciado, que não é o grupo
# principal de ninguém e que não é usado no smb.conf (decisão de 19/10/2026:
# o grupo de um compartilhamento só sai depois de trocar o grupo ou remover
# o compartilhamento). Os avisos (membros, arquivos) e a confirmação ficam
# na tela.
debkit_grupo_remover() {
    local grupo="$1" gid principais membros usos
    local -a lista=()
    if ! debkit_grupo_gerenciado "$grupo"; then msg_erro "$(t grp.nao_gerenciado "$grupo")"; return 1; fi
    principais=$(debkit_grupo_principais "$grupo" | paste -sd, | sed 's/,/, /g')
    if [ -n "$principais" ]; then msg_erro "$(t grp.remover_principal "$grupo" "$principais")"; return 1; fi
    usos=$(debkit_samba_grupo_usos "$grupo" | sed 's/.*/[&]/' | paste -sd' ')
    if [ -n "$usos" ]; then msg_erro "$(t grp.remover_usado "$grupo" "$usos")"; return 1; fi
    gid=$(getent group "$grupo" | cut -d: -f3)
    membros=$(debkit_grupo_membros "$grupo" | paste -sd,)
    mapfile -t lista < <(debkit_grupo_membros "$grupo")
    if ! groupdel -- "$grupo" >/dev/null 2>&1 || getent group "$grupo" >/dev/null 2>&1; then
        msg_erro "$(t grp.remover_falhou "$grupo")"
        debkit_auditar grupo_remover "nome=$grupo resultado=falha"
        return 1
    fi
    debkit_auditar grupo_remover "nome=$grupo gid=$gid membros=$membros resultado=ok"
    msg_ok "$(t grp.removido "$grupo")"
    debkit_samba_reconectar "${lista[@]}"
    return 0
}

# ── Compartilhamentos: regras ───────────────────────────────────────────────
# Decisões de 19/10/2026 (seção 3.7): cada compartilhamento tem UM grupo,
# com acesso total (dar acesso = pôr a pessoa no grupo); pastas só dentro de
# /mnt ou /srv; nome só em minúsculas.
DEBKIT_SHR_RESERVADOS=(global homes printers 'print$' 'ipc$')
DEBKIT_SHR_RAIZES=(/mnt /srv)
DEBKIT_SHR_COMENTARIO_MAX=100
# Seções do smb.conf que não são compartilhamentos do debkit
DEBKIT_SHR_FORA=" global homes printers print$ "

# Imprime o problema do nome do compartilhamento novo e retorna 1; 0 = livre
debkit_shr_nome_problema() {
    local nome="$1" r l="$DEBKIT_MINUSCULAS" ld="$DEBKIT_MINUSCULAS$DEBKIT_DIGITOS"
    if [ -z "$nome" ]; then t shr.nome_vazio; return 1; fi
    if [ "${#nome}" -lt 2 ] || [ "${#nome}" -gt 32 ]; then t shr.nome_tamanho "$nome" "${#nome}"; return 1; fi
    if [[ ! "$nome" =~ ^[$l][${ld}_-]*[$ld]$ ]]; then t shr.nome_formato "$nome"; return 1; fi
    for r in "${DEBKIT_SHR_RESERVADOS[@]}"; do
        if [ "$nome" == "$r" ]; then t shr.nome_reservado "$nome"; return 1; fi
    done
    # o Samba não diferencia maiúsculas nos nomes de compartilhamento
    if debkit_shr_secoes | grep -qixF -- "$nome"; then t shr.nome_existe "$nome"; return 1; fi
    return 0
}

# Descrição (comment), opcional: sem caracteres de controle, sem \ (no fim
# da linha o Samba junta com a próxima) e sem % (variáveis do Samba)
debkit_shr_comentario_problema() {
    local c="$1"
    if [[ "$c" == *[\\%]* || "$c" =~ [[:cntrl:]] ]]; then t shr.comentario_invalido; return 1; fi
    if [ "${#c}" -gt "$DEBKIT_SHR_COMENTARIO_MAX" ]; then t shr.comentario_tamanho "$DEBKIT_SHR_COMENTARIO_MAX"; return 1; fi
    return 0
}

# Nomes de todas as seções do smb.conf (um por linha, como estão)
debkit_shr_secoes() {
    testparm -s "$DEBKIT_SMB_CONF" 2>/dev/null | sed -n 's/^\[\(.*\)\]$/\1/p'
}

# Caminho dentro de /mnt ou /srv, real (sem links), num sistema de arquivos
# que guarda dono e permissões e gravável. Serve para a base e para a pasta.
# Imprime o problema e retorna 1; 0 = pode ser usado.
debkit_shr_raiz_problema() {
    local dir="$1" r dentro=0 real existente alvo fstipo opcoes
    if [ -z "$dir" ]; then t shr.pasta_vazia; return 1; fi
    if ! debkit_conf_valor_valido caminho "$dir"; then t home.base_formato "$dir"; return 1; fi
    for r in "${DEBKIT_SHR_RAIZES[@]}"; do [[ "$dir" == "$r"/?* ]] && dentro=1; done
    if [ "$dentro" -eq 0 ]; then t shr.fora_das_raizes "$dir"; return 1; fi
    real=$(realpath -m -- "$dir")
    if [ "$real" != "$dir" ]; then t home.base_link "$dir" "$real"; return 1; fi
    existente="$dir"
    while [ ! -e "$existente" ] && [ ! -L "$existente" ]; do existente=$(dirname -- "$existente"); done
    if [ ! -d "$existente" ] || [ -L "$existente" ]; then t home.base_nao_pasta "$existente"; return 1; fi
    read -r alvo fstipo opcoes < <(findmnt -n -o TARGET,FSTYPE,OPTIONS --target "$existente" 2>/dev/null | tail -n 1)
    if [[ "$DEBKIT_FS_NAO_DISCO" == *" $fstipo "* ]]; then t home.base_nao_disco "$dir" "$alvo" "$fstipo"; return 1; fi
    if [[ "$DEBKIT_FS_SEM_PERMISSOES" == *" $fstipo "* ]]; then t home.base_sem_permissoes "$dir" "$alvo" "$fstipo"; return 1; fi
    if [[ ",$opcoes," == *",ro,"* ]]; then t home.base_somente_leitura "$dir" "$alvo"; return 1; fi
    return 0
}

# Pastas dos compartilhamentos que existem (um por linha, sem / no fim)
debkit_shr_caminhos() {
    testparm -s "$DEBKIT_SMB_CONF" 2>/dev/null | awk '$1 == "path" && $2 == "=" { v = $0; sub(/^[^=]*=[ \t]*/, "", v); print v }' \
        | sed 's:/*$::; /^$/d' | sort -u
}

# Pasta de um compartilhamento novo: raiz válida, pasta (ou ainda não
# existe, com a pasta de cima existindo), sem se misturar com a base das
# pastas pessoais nem com a pasta de outro compartilhamento
debkit_shr_pasta_problema() {
    local dir="$1" outro
    debkit_shr_raiz_problema "$dir" || return 1
    if [ -e "$dir" ] || [ -L "$dir" ]; then
        if [ -L "$dir" ] || [ ! -d "$dir" ]; then t home.base_nao_pasta "$dir"; return 1; fi
    elif [ ! -d "$(dirname -- "$dir")" ]; then
        t shr.pai_nao_existe "$dir" "$(dirname -- "$dir")"; return 1
    fi
    if [ -n "$DEBKIT_HOMES_BASE" ] && { [ "$dir" == "$DEBKIT_HOMES_BASE" ] || [[ "$dir" == "$DEBKIT_HOMES_BASE"/* || "$DEBKIT_HOMES_BASE" == "$dir"/* ]]; }; then
        t shr.mistura_homes "$dir" "$DEBKIT_HOMES_BASE"; return 1
    fi
    while read -r outro; do
        [ -n "$outro" ] || continue
        if [ "$dir" == "$outro" ] || [[ "$dir" == "$outro"/* || "$outro" == "$dir"/* ]]; then
            t shr.mistura_outro "$dir" "$outro"; return 1
        fi
    done < <(debkit_shr_caminhos)
    return 0
}

# ── Compartilhamentos: base ─────────────────────────────────────────────────
# Sugestão de base: <primeiro disco de dados em /mnt>/compartilhamentos ou
# /srv/samba
debkit_shr_sugerir_base() {
    local d
    while read -r d; do
        [[ "$d" == /mnt/* ]] && { echo "$d/compartilhamentos"; return 0; }
    done < <(debkit_samba_discos_dados)
    echo "/srv/samba"
}

# Define a base: valida, cria a pasta se não existe (root, 755) e grava
# SHARES_BASE no debkit.conf. Se a gravação falhar, tira a pasta que criou.
debkit_shr_definir_base() {
    local base="$1" problema criada=0
    if ! problema=$(debkit_shr_raiz_problema "$base"); then msg_erro "$problema"; return 1; fi
    if [ -e "$base" ] && { [ -L "$base" ] || [ ! -d "$base" ]; }; then msg_erro "$(t home.base_nao_pasta "$base")"; return 1; fi
    if [ ! -d "$base" ]; then
        if ! ( umask 022; mkdir -p -- "$base" ) || ! chown 0:0 -- "$base" || ! chmod 755 -- "$base"; then
            msg_erro "$(t home.base_criar_falhou "$base")"; return 1
        fi
        criada=1
    fi
    if ! debkit_conf_definir SHARES_BASE "$base"; then
        [ "$criada" -eq 1 ] && rmdir -- "$base" 2>/dev/null
        return 1
    fi
    msg_ok "$(t shr.base_definida "$base" "$DEBKIT_CONF_ARQUIVO")"
}

# A base está pronta? Se não definida, pergunta (primeira vez) e grava.
debkit_shr_garantir_base() {
    local base sugestao problema
    if [ -n "$DEBKIT_SHARES_BASE" ]; then
        if ! problema=$(debkit_shr_raiz_problema "$DEBKIT_SHARES_BASE"); then
            msg_erro "$(t shr.base_invalida_agora "$DEBKIT_SHARES_BASE" "$problema")"; return 1
        fi
        [ -d "$DEBKIT_SHARES_BASE" ] || debkit_shr_definir_base "$DEBKIT_SHARES_BASE"
        return
    fi
    echo ""
    msg_info "$(t shr.base_intro)"
    sugestao=$(debkit_shr_sugerir_base)
    while true; do
        debkit_ler base "$(t home.p_base "$sugestao")" || return 1
        [ -z "$base" ] && base="$sugestao"
        problema=$(debkit_shr_raiz_problema "$base") && break
        msg_erro "$problema"
    done
    confirmar "$(t shr.p_confirma_base "$base")" || return 1
    debkit_shr_definir_base "$base"
}

# ── Compartilhamentos: criar ────────────────────────────────────────────────
# Bloco do smb.conf (sem a linha de comentário do debkit)
debkit_shr_bloco() {
    local nome="$1" comentario="$2" pasta="$3" grupo="$4"
    printf '[%s]\n' "$nome"
    [ -n "$comentario" ] && printf '   comment = %s\n' "$comentario"
    printf '   path = %s\n   valid users = @%s\n   read only = no\n' "$pasta" "$grupo"
    printf '   force group = %s\n   create mask = 0660\n   directory mask = 2770\n' "$grupo"
}

# Uma seção da saída do testparm -s (sem o cabeçalho e as linhas vazias)
debkit_shr_secao_efetiva() {
    awk -v s="[$2]" '/^\[/ { em = ($0 == s); next } em && NF' "$1"
}
# Saída do testparm -s sem a seção <nome> (e sem as linhas vazias, que o
# testparm põe entre as seções)
debkit_shr_sem_secao() {
    awk -v s="[$2]" '/^\[/ { em = ($0 == s) } !em && NF' "$1"
}

# Filtro: acrescenta o bloco novo (DEBKIT_S_BLOCO) no fim do smb.conf
debkit_shr_filtro_criar() {
    awk '{ print }'
    printf '\n# debkit: compartilhamento criado em %s\n%s\n' "$(date '+%d/%m/%Y')" "$DEBKIT_S_BLOCO"
}

# Conferência: fora a seção nova, nada mudou; e a seção nova em vigor é
# exatamente a do bloco (comparada com o testparm do bloco sozinho)
debkit_shr_conferir_criar() {
    local esperado
    esperado=$(debkit_temp) || return 1
    printf '[global]\n%s\n' "$DEBKIT_S_BLOCO" > "$esperado.conf"
    DEBKIT_TEMPORARIOS+=("$esperado.conf")
    testparm -s "$esperado.conf" >"$esperado" 2>/dev/null || return 1
    cmp -s <(debkit_shr_sem_secao "$1" "$DEBKIT_S_NOME") <(debkit_shr_sem_secao "$2" "$DEBKIT_S_NOME") \
        && [ -n "$(debkit_shr_secao_efetiva "$2" "$DEBKIT_S_NOME")" ] \
        && cmp -s <(debkit_shr_secao_efetiva "$esperado" "$DEBKIT_S_NOME") <(debkit_shr_secao_efetiva "$2" "$DEBKIT_S_NOME")
}

# Entrada: DEBKIT_S_NOME, DEBKIT_S_COMENTARIO, DEBKIT_S_PASTA e
# DEBKIT_S_GRUPO (grupo gerenciado; acesso total). Tudo ou nada: cria (ou
# ajusta) a pasta root:<grupo> 2770 e a seção no smb.conf (edição segura);
# confere e, se algo falhar, desfaz.
debkit_shr_criar() {
    local nome="$DEBKIT_S_NOME" pasta="$DEBKIT_S_PASTA" grupo="$DEBKIT_S_GRUPO" motivo gid antes="" criada=0
    if ! motivo=$(debkit_shr_nome_problema "$nome") || ! motivo=$(debkit_shr_comentario_problema "$DEBKIT_S_COMENTARIO") \
       || ! motivo=$(debkit_shr_pasta_problema "$pasta"); then
        msg_erro "$(t shr.falhou "$nome" "$motivo")"; return 1
    fi
    if [ -z "$grupo" ]; then msg_erro "$(t shr.falhou "$nome" "$(t shr.sem_grupo)")"; return 1; fi
    if ! debkit_grupo_gerenciado "$grupo" || [[ ! "$grupo" =~ ^[^[:space:],@+\&\"]+$ ]]; then
        msg_erro "$(t shr.falhou "$nome" "$(t grp.nao_gerenciado "$grupo")")"; return 1
    fi
    gid=$(getent group "$grupo" | cut -d: -f3)
    DEBKIT_S_BLOCO=$(debkit_shr_bloco "$nome" "$DEBKIT_S_COMENTARIO" "$pasta" "$grupo")
    msg_info "$(t shr.criando "$nome")"
    # 1. Pasta: nova, ou a que já existe (guarda dono e permissões para desfazer)
    if [ -d "$pasta" ]; then
        antes=$(stat -c '%u:%g:%a' -- "$pasta")
    elif ( umask 077; mkdir -- "$pasta" ); then
        criada=1
    else
        debkit_shr_falhou "$(t shr.f_pasta "$pasta")"; return 1
    fi
    if ! chown "0:$gid" -- "$pasta" || ! chmod 2770 -- "$pasta"; then
        debkit_shr_falhou "$(t shr.f_pasta "$pasta")" "$criada" "$antes"; return 1
    fi
    # 2. smb.conf (backup, testparm, conferência, troca atômica e reload)
    if ! debkit_smbconf_editar debkit_shr_filtro_criar debkit_shr_conferir_criar; then
        debkit_shr_falhou "$(t shr.f_smbconf)" "$criada" "$antes"; return 1
    fi
    # 3. Conferência final (resultado real)
    if [ "$(stat -c '%u %g %a' -- "$pasta")" != "0 $gid 2770" ] \
       || [ "$(testparm -s --section-name="$nome" --parameter-name=path "$DEBKIT_SMB_CONF" 2>/dev/null)" != "$pasta" ]; then
        debkit_smbconf_restaurar
        debkit_shr_falhou "$(t usr.f_conferencia "pasta/smb.conf")" "$criada" "$antes"; return 1
    fi
    debkit_auditar shr_criar "nome=$nome pasta=$pasta grupo=$grupo resultado=ok"
    msg_ok "$(t shr.criado "$nome" "$pasta")"
}

# Falha na criação: informa, desfaz a pasta (apaga se criou; volta dono e
# permissões se já existia) e audita. debkit_shr_falhou <motivo> [criada] [antes]
debkit_shr_falhou() {
    local criada="${2:-0}" antes="${3:-}"
    msg_erro "$(t shr.falhou "$DEBKIT_S_NOME" "$1")"
    debkit_auditar shr_criar "nome=$DEBKIT_S_NOME resultado=falha motivo=$1"
    if [ "$criada" -eq 1 ]; then
        rmdir -- "$DEBKIT_S_PASTA" 2>/dev/null || msg_erro "$(t shr.desfazer_falhou "$DEBKIT_S_PASTA")"
    elif [ -n "$antes" ]; then
        # chmod com 5 dígitos: em pasta, "755" manteria o setgid de agora
        chown "${antes%:*}" -- "$DEBKIT_S_PASTA" 2>/dev/null; chmod "$(printf '%05d' "${antes##*:}")" -- "$DEBKIT_S_PASTA" 2>/dev/null
        [ "$(stat -c '%u:%g:%a' -- "$DEBKIT_S_PASTA")" == "$antes" ] || msg_erro "$(t shr.desfazer_falhou "$DEBKIT_S_PASTA")"
    fi
    return 0
}

# ── Compartilhamentos: listar ───────────────────────────────────────────────
# Um por linha: nome|pasta|escrita|leitura|alertas (listas separadas por
# vírgula; "@g" = grupo, sem @ = usuário; "*" = qualquer usuário do Samba;
# alertas: sem_pasta, convidado, todos, fora_padrao = não é um grupo só com
# acesso total, o padrão do debkit). Inclui os feitos à mão; fora
# [global], [homes], [printers] e [print$].
debkit_shr_dados() {
    testparm -s "$DEBKIT_SMB_CONF" 2>/dev/null | awk -v fora="$DEBKIT_SHR_FORA" '
        function lista(v,   n, i, t, r) { n = split(v, t, /[ ,]+/); r = ""
            for (i = 1; i <= n; i++) if (t[i] != "") { gsub(/"/, "", t[i]); sub(/^\+/, "@", t[i]); sub(/^&/, "@", t[i]); r = r (r == "" ? "" : ",") t[i] }
            return r }
        function tem(l, x) { return index("," l ",", "," x ",") > 0 }
        function junta(l, x) { return l (l == "" ? "" : ",") x }
        # Quem acessa: valid users (vazio = qualquer usuário, "*"). Cada um
        # escreve se "read only = no" ou se está no write list, e só lê se
        # está no read list ou nos demais casos.
        function fim(   n, i, t, esc, lei) {
            if (sec == "" || index(fora, " " tolower(sec) " ")) return
            esc = ""; lei = ""
            if (vu == "") {
                if (ro == "No") { esc = "*"; lei = rl } else { esc = wl; lei = "*" }
            } else {
                n = split(vu, t, ",")
                for (i = 1; i <= n; i++) {
                    if (tem(rl, t[i])) lei = junta(lei, t[i])
                    else if (ro == "No" || tem(wl, t[i])) esc = junta(esc, t[i])
                    else lei = junta(lei, t[i])
                }
            }
            print sec "|" path "|" esc "|" lei "|" guest
        }
        /^\[/ { fim(); sec = substr($0, 2, length($0) - 2); path = ""; vu = ""; wl = ""; rl = ""; ro = ""; guest = ""; next }
        {
            l = $0; sub(/^[ \t]+/, "", l); p = l; sub(/[ \t]*=.*/, "", p); v = l; if (!sub(/^[^=]*=[ \t]*/, "", v)) next
            if (p == "path") path = v; else if (p == "valid users") vu = lista(v)
            else if (p == "write list") wl = lista(v); else if (p == "read list") rl = lista(v)
            else if (p == "read only") ro = v; else if (p == "guest ok" && v == "Yes") guest = "convidado"
        }
        END { fim() }' | while IFS='|' read -r nome pasta esc lei alerta; do
            [ -n "$pasta" ] && [ ! -d "$pasta" ] && alerta="${alerta:+$alerta,}sem_pasta"
            if [[ ",$esc,$lei," == *",*,"* ]]; then alerta="${alerta:+$alerta,}todos"
            elif [[ ! "$esc" =~ ^@[^,]+$ ]] || [ -n "$lei" ]; then alerta="${alerta:+$alerta,}fora_padrao"; fi
            printf '%s|%s|%s|%s|%s\n' "$nome" "$pasta" "$esc" "$lei" "$alerta"
        done
}

# Lista legível ("@g" -> "g"; usuário -> "fulano (usuário)"; "*" -> todos)
debkit_shr_rotulo() {
    local x r="" IFS=,
    for x in $1; do
        case "$x" in
            "*") x="$(t shr.todos)" ;;
            @*)  x="${x#@}" ;;
            *)   x="$x ($(t shr.usuario))" ;;
        esac
        r+="${r:+, }$x"
    done
    printf '%s' "${r:-—}"
}

# Quem acessa, legível: debkit_shr_rotulo_acesso <escrita> <leitura>
debkit_shr_rotulo_acesso() {
    local acesso
    acesso=$(debkit_shr_rotulo "$1")
    [ -n "$2" ] && acesso="${1:+$acesso, }$(debkit_shr_rotulo "$2" | sed "s/, / ($(t shr.so_leitura)), /g; s/\$/ ($(t shr.so_leitura))/")"
    printf '%s' "$acesso"
}

debkit_shr_listar() {
    local l nome pasta esc lei alerta acesso wn=4 wp=5 a
    local -a linhas=() alertas=()
    mapfile -t linhas < <(debkit_shr_dados)
    if [ ${#linhas[@]} -eq 0 ]; then msg_info "$(t shr.nenhum)"; return 0; fi
    for l in "${linhas[@]}"; do
        IFS='|' read -r nome pasta _ _ _ <<< "$l"
        [ "${#nome}" -gt "$wn" ] && wn=${#nome}
        [ "${#pasta}" -gt "$wp" ] && wp=${#pasta}
    done
    [ "$wp" -gt 40 ] && wp=40
    printf '  %s%s  %s  %s%s\n' "$C_NEGRITO" "$(debkit_pad "$(t shr.c_nome)" "$wn")" "$(debkit_pad "$(t shr.c_pasta)" "$wp")" \
        "$(t shr.c_grupo)" "$C_RESET"
    for l in "${linhas[@]}"; do
        IFS='|' read -r nome pasta esc lei alerta <<< "$l"
        acesso=$(debkit_shr_rotulo_acesso "$esc" "$lei")
        printf '  %s  %s  %s\n' "$(debkit_pad "$nome" "$wn")" "$(debkit_pad "${pasta:-—}" "$wp")" "$acesso"
        # só o sem_pasta mostra a pasta (argumento a mais repetiria a mensagem)
        for a in ${alerta//,/ }; do
            if [ "$a" == "sem_pasta" ]; then alertas+=("$(t shr.a_sem_pasta "$nome" "$pasta")"); else alertas+=("$(t "shr.a_$a" "$nome")"); fi
        done
    done
    echo ""
    echo "  $(t shr.total "${#linhas[@]}")"
    if [ ${#alertas[@]} -gt 0 ]; then
        echo ""
        printf '  %s%s%s\n' "$C_AMARELO" "$(t lst.titulo_alertas)" "$C_RESET"
        for l in "${alertas[@]}"; do echo "    ! $l"; done
    fi
}

# ── Compartilhamentos: grupo e permissões ───────────────────────────────────
# A pasta pode ter o conteúdo ajustado? Dentro de /mnt ou /srv (as regras de
# criar), sem se misturar com a base das pastas pessoais nem com a pasta de
# outro compartilhamento (senão o ajuste passaria o conteúdo do outro para
# este grupo). Retorna 1 se não pode. debkit_shr_pasta_segura <pasta>
debkit_shr_pasta_segura() {
    local dir="${1%/}" outro iguais=0
    debkit_shr_raiz_problema "$dir" >/dev/null || return 1
    [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
    if [ -n "$DEBKIT_HOMES_BASE" ] && { [ "$dir" == "$DEBKIT_HOMES_BASE" ] || [[ "$dir" == "$DEBKIT_HOMES_BASE"/* || "$DEBKIT_HOMES_BASE" == "$dir"/* ]]; }; then
        return 1
    fi
    while read -r outro; do
        [ -n "$outro" ] || continue
        if [ "$outro" == "$dir" ]; then iguais=$((iguais + 1)); continue; fi
        [[ "$dir" == "$outro"/* || "$outro" == "$dir"/* ]] && return 1
    done < <(debkit_shr_caminhos)
    # a mesma pasta em dois compartilhamentos: também não
    [ "$(testparm -s "$DEBKIT_SMB_CONF" 2>/dev/null | awk -v d="$dir" '$1 == "path" && $2 == "=" { v = $0; sub(/^[^=]*=[ \t]*/, "", v); sub(/\/+$/, "", v); if (v == d) n++ } END { print n + 0 }')" -le 1 ]
}

# Os que estão no padrão do debkit (um grupo gerenciado com acesso total e a
# pasta existindo, num lugar seguro), inclusive os feitos à mão:
# nome|pasta|grupo
debkit_shr_gerenciaveis() {
    local nome pasta esc lei alerta
    while IFS='|' read -r nome pasta esc lei alerta; do
        [[ ",$alerta," == *,fora_padrao,* || ",$alerta," == *,todos,* || ",$alerta," == *,sem_pasta,* ]] && continue
        if [[ ! "$esc" =~ ^@[^,]+$ ]] || [ -n "$lei" ] || [ -z "$pasta" ] || [[ "$pasta" == *%* ]]; then continue; fi
        debkit_shr_pasta_segura "$pasta" || continue
        debkit_grupo_gerenciado "${esc#@}" || continue
        printf '%s|%s|%s\n' "$nome" "$pasta" "${esc#@}"
    done < <(debkit_shr_dados)
}

# Quantos itens (arquivos e pastas, sem seguir links nem sair do disco) há
# na pasta: debkit_shr_contar <pasta>; e quantos estão fora do padrão:
# debkit_shr_pendentes <pasta> <gid> (grupo diferente, acesso para outros,
# pasta sem rwx+setgid para o grupo, arquivo sem rw para o grupo ou com
# setuid/setgid; e a pasta do compartilhamento que não é do root)
debkit_shr_contar() {
    find "$1" -xdev \( -type d -o -type f \) -printf x 2>/dev/null | wc -c
}
debkit_shr_pendentes() {
    local n
    n=$(find "$1" -xdev \( -type d -o -type f \) \( ! -group "$2" -o -perm /o=rwx \
            -o \( -type d ! -perm -2770 \) -o \( -type f \( ! -perm -0660 -o -perm /6000 \) \) \) -printf x 2>/dev/null | wc -c)
    [ "$(stat -c %u -- "$1" 2>/dev/null)" == "0" ] || n=$((n + 1))
    echo "$n"
}

# Ajusta o conteúdo da pasta para o grupo (decisão de 19/10/2026): pasta
# root:<grupo> 2770; dentro, tudo com o grupo, rw para o grupo (pastas rwx
# com setgid; arquivo executável continua executável), sem acesso para
# outros e sem setuid/setgid em arquivo. Os donos não mudam. Não segue
# links (chgrp -h; links ficam como estão) nem sai do disco (-xdev).
# Os usuários de arquivos não criam links pelo Samba (SMB2/3 sem as
# extensões unix), por isso não há troca de pasta por link no meio.
# Não dá para desfazer; é seguro rodar de novo. Retorna 1 se sobrou algo.
debkit_shr_ajustar_conteudo() {
    local pasta="$1" grupo="$2" gid resto total
    gid=$(getent group "$grupo" | cut -d: -f3)
    if [ -z "$gid" ] || ! debkit_shr_pasta_segura "$pasta"; then
        msg_erro "$(t shr.ajustar_invalido "$pasta" "$grupo")"; return 1
    fi
    msg_info "$(t shr.ajustando "$pasta")"
    chown "0:$gid" -- "$pasta" 2>/dev/null; chmod 2770 -- "$pasta" 2>/dev/null
    find "$pasta" -xdev -mindepth 1 \( -type d -o -type f \) ! -group "$gid" -exec chgrp -h -- "$gid" {} + 2>/dev/null
    find "$pasta" -xdev -mindepth 1 -type d -exec chmod u+rwx,g+rwxs,o-rwx -- {} + 2>/dev/null
    find "$pasta" -xdev -mindepth 1 -type f -exec chmod ug-s,o-rwx,ug+rw,g+X -- {} + 2>/dev/null
    total=$(debkit_shr_contar "$pasta")
    resto=$(debkit_shr_pendentes "$pasta" "$gid")
    if [ "$resto" -ne 0 ]; then
        msg_erro "$(t shr.ajustar_falhou "$pasta" "$resto")"
        debkit_auditar shr_ajustar "pasta=$pasta grupo=$grupo itens=$total fora=$resto resultado=falha"
        return 1
    fi
    debkit_auditar shr_ajustar "pasta=$pasta grupo=$grupo itens=$total resultado=ok"
    msg_ok "$(t shr.ajustado "$pasta" "$total")"
}

# Linhas de acesso que a troca de grupo substitui (nomes como o Samba
# compara: sem espaços e sem diferenciar maiúsculas; "group" = force group;
# writeable/writable/write ok = o contrário de read only)
DEBKIT_SHR_ACESSO=" validusers forcegroup group writelist readlist readonly writeable writable writeok "

# Linhas que trazer para o padrão substitui: as de acesso, convidado,
# permissões dos arquivos novos, force user, admin users e invalid users
# (public = guest ok; only guest = guest only; create mode = create mask;
# directory mode = directory mask)
DEBKIT_SHR_PADRAO="$DEBKIT_SHR_ACESSO guestok public guestonly onlyguest createmask createmode directorymask directorymode forcecreatemode forcedirectorymode forceuser adminusers invalidusers "

# Filtro: na seção DEBKIT_S_NOME (sem diferenciar maiúsculas), tira as
# linhas indicadas (com as continuações "\") e põe as novas logo depois do
# cabeçalho. debkit_shr_filtro_linhas <nomes, como em DEBKIT_SHR_ACESSO> <linhas novas>
debkit_shr_filtro_linhas() {
    DEBKIT_SHR_NOVAS="$2" awk -v s="${DEBKIT_S_NOME,,}" -v acesso="$1" '
        tira { tira = /\\$/; next }
        segue { segue = /\\$/; print; next }
        /^[ \t]*\[/ {
            h = $0; sub(/^[ \t]*\[[ \t]*/, "", h); sub(/[ \t]*\].*$/, "", h); em = (tolower(h) == s); print
            if (em) printf "%s\n", ENVIRON["DEBKIT_SHR_NOVAS"]
            next
        }
        em && /^[ \t]*[^#; \t]/ && /=/ {
            p = $0; sub(/=.*/, "", p); gsub(/[ \t]/, "", p)
            if (index(acesso, " " tolower(p) " ")) { tira = /\\$/; next }
        }
        { segue = /\\$/; print }'
}

# Troca de grupo: valid users = @<grupo>, read only = no e force group
debkit_shr_filtro_grupo() {
    debkit_shr_filtro_linhas "$DEBKIT_SHR_ACESSO" \
        "$(printf '   valid users = @%s\n   read only = no\n   force group = %s' "$DEBKIT_S_GRUPO" "$DEBKIT_S_GRUPO")"
}

# Conferência: fora a seção, nada mudou; na seção, só as linhas de acesso
# mudaram, e agora são exatamente as do grupo novo
debkit_shr_conferir_grupo() {
    local outras=$'^\t(valid users|force group|read only|write list|read list) = '
    cmp -s <(debkit_shr_sem_secao "$1" "$DEBKIT_S_NOME") <(debkit_shr_sem_secao "$2" "$DEBKIT_S_NOME") \
        && cmp -s <(debkit_shr_secao_efetiva "$1" "$DEBKIT_S_NOME" | grep -vE "$outras") \
                  <(debkit_shr_secao_efetiva "$2" "$DEBKIT_S_NOME" | grep -vE "$outras") \
        && [ "$(debkit_shr_secao_efetiva "$2" "$DEBKIT_S_NOME" | grep -E "$outras" | sort)" == \
             "$(printf '\tforce group = %s\n\tread only = No\n\tvalid users = @%s' "$DEBKIT_S_GRUPO" "$DEBKIT_S_GRUPO")" ]
}

# Quem perde o acesso na troca: membros (e quem tem como principal) do
# grupo antigo que não estão no novo. debkit_shr_perdem <antigo> <novo>
debkit_shr_perdem() {
    local -a antes=()
    mapfile -t antes < <(debkit_shr_acesso "$1")
    debkit_shr_fora_do_grupo "$2" "${antes[@]}"
}

# Dos usuários indicados, os que não estão no grupo:
# debkit_shr_fora_do_grupo <grupo> <usuário>...
debkit_shr_fora_do_grupo() {
    local g="$1" u
    shift
    for u in "$@"; do
        [ -n "$u" ] || continue
        id -nG -- "$u" 2>/dev/null | tr ' ' '\n' | grep -qxF -- "$g" || echo "$u"
    done
}

# Entrada: DEBKIT_S_NOME (compartilhamento no padrão) e DEBKIT_S_GRUPO (o
# grupo novo, gerenciado). Troca as linhas de acesso no smb.conf (edição
# segura; confere o resultado e, se não bater, restaura), passa o conteúdo
# para o grupo novo e refaz as sessões de quem perde o acesso.
debkit_shr_trocar_grupo() {
    local nome="$DEBKIT_S_NOME" novo="$DEBKIT_S_GRUPO" linha pasta antigo
    local -a perdem=()
    linha=$(debkit_shr_gerenciaveis | awk -F'|' -v n="$nome" '$1 == n')
    if [ -z "$nome" ] || [ -z "$linha" ]; then
        msg_erro "$(t shr.trocar_falhou "$nome" "$(t shr.nao_gerenciavel "$nome")")"; return 1
    fi
    IFS='|' read -r _ pasta antigo <<< "$linha"
    if [ -z "$novo" ]; then msg_erro "$(t shr.trocar_falhou "$nome" "$(t shr.sem_grupo)")"; return 1; fi
    if ! debkit_grupo_gerenciado "$novo" || [[ ! "$novo" =~ ^[^[:space:],@+\&\"]+$ ]]; then
        msg_erro "$(t shr.trocar_falhou "$nome" "$(t grp.nao_gerenciado "$novo")")"; return 1
    fi
    if [ "$novo" == "$antigo" ]; then msg_erro "$(t shr.trocar_falhou "$nome" "$(t shr.mesmo_grupo "$novo")")"; return 1; fi
    mapfile -t perdem < <(debkit_shr_perdem "$antigo" "$novo")
    msg_info "$(t shr.trocando "$nome")"
    if ! debkit_smbconf_editar debkit_shr_filtro_grupo debkit_shr_conferir_grupo; then
        msg_erro "$(t shr.trocar_falhou "$nome" "$(t shr.f_smbconf)")"
        debkit_auditar shr_grupo "nome=$nome antigo=$antigo novo=$novo resultado=falha"
        return 1
    fi
    if [ "$(debkit_shr_gerenciaveis | awk -F'|' -v n="$nome" '$1 == n')" != "$nome|$pasta|$novo" ]; then
        debkit_smbconf_restaurar
        msg_erro "$(t shr.trocar_falhou "$nome" "$(t usr.f_conferencia smb.conf)")"
        debkit_auditar shr_grupo "nome=$nome antigo=$antigo novo=$novo resultado=falha"
        return 1
    fi
    debkit_auditar shr_grupo "nome=$nome antigo=$antigo novo=$novo resultado=ok"
    msg_ok "$(t shr.trocado "$nome" "$novo")"
    debkit_shr_ajustar_conteudo "$pasta" "$novo" || { debkit_samba_reconectar "${perdem[@]}"; return 1; }
    debkit_samba_reconectar "${perdem[@]}"
    return 0
}

# ── Compartilhamentos: remover ──────────────────────────────────────────────
# Filtro: tira a seção DEBKIT_S_NOME (sem diferenciar maiúsculas; todas, se
# repetida), com o comentário "# debkit: compartilhamento criado em" e as
# linhas vazias logo antes dela, e os comentários de dentro dela. Fica só o
# bloco de comentários colado no cabeçalho seguinte (depois da última linha
# vazia; ex.: o comentário do debkit da seção seguinte).
debkit_shr_filtro_remover() {
    awk -v s="${DEBKIT_S_NOME,,}" '
        function solta(   i) { for (i = 1; i <= n; i++) print b[i]; n = 0 }
        /^[ \t]*\[/ {
            h = $0; sub(/^[ \t]*\[[ \t]*/, "", h); sub(/[ \t]*\].*$/, "", h)
            if (tolower(h) == s) {
                if (em) n = 0
                else { while (n > 0 && (b[n] ~ /^[ \t]*$/ || b[n] ~ /^# debkit: compartilhamento criado em /)) n--; solta() }
                em = 1; next
            }
            if (em) { for (k = n; k > 0 && b[k] !~ /^[ \t]*$/; k--); for (i = (k > 0 ? k : 1); i <= n; i++) print b[i]; n = 0 }
            em = 0; solta(); print; next
        }
        /^[ \t]*([#;].*)?$/ { b[++n] = $0; next }
        em { n = 0; next }
        { solta(); print }
        END { if (!em) solta() }'
}

# Conferência: a seção existia, não existe mais e o resto não mudou
debkit_shr_conferir_remover() {
    grep -qxF -- "[$DEBKIT_S_NOME]" "$1" && ! grep -qixF -- "[$DEBKIT_S_NOME]" "$2" \
        && cmp -s <(debkit_shr_sem_secao "$1" "$DEBKIT_S_NOME") <(debkit_shr_sem_secao "$2" "$DEBKIT_S_NOME")
}

# Quem tem o acesso pelo grupo: membros e quem o tem como principal
debkit_shr_acesso() {
    { debkit_grupo_membros "$1"; debkit_grupo_principais "$1"; } | sed '/^$/d' | sort -u
}

# Usuários com acesso por uma lista de debkit_shr_dados ("@g" = membros e
# quem tem g como principal; "*" = todas as contas do Samba; o resto = o
# próprio usuário). debkit_shr_usuarios <lista,lista>
debkit_shr_usuarios() {
    local x
    local -a itens=()
    IFS=, read -ra itens <<< "$1"
    for x in "${itens[@]}"; do
        case "$x" in
            "")  ;;
            "*") debkit_pdbedit -L 2>/dev/null | cut -d: -f1 ;;
            @*)  debkit_shr_acesso "${x#@}" ;;
            *)   echo "$x" ;;
        esac
    done | sed '/^$/d' | sort -u
}

# A pasta do compartilhamento pode mudar (trancar ao remover)? Definida,
# sem %, existente e segura. debkit_shr_pasta_mexivel <pasta>
debkit_shr_pasta_mexivel() {
    [ -n "$1" ] && [[ "$1" != *%* ]] && debkit_shr_pasta_segura "$1"
}

# Entrada: DEBKIT_S_NOME (qualquer compartilhamento, menos [homes],
# [printers] e [print$]; decisão de 19/10/2026: inclusive os feitos à mão,
# tarefa 2.4). Tira a seção do smb.conf (edição segura; confere e, se não
# bater, restaura), deixa a pasta root:root 0700 (os arquivos ficam, só o
# root acessa; apagar dados não faz parte da função) e refaz as sessões de
# quem tinha o acesso. A pasta fora de /mnt e /srv, inexistente ou usada
# por outro compartilhamento não muda (decidido antes de mexer no smb.conf).
debkit_shr_remover() {
    local nome="$DEBKIT_S_NOME" linha pasta esc lei acesso seguro=0 rc=0
    local -a afetados=()
    linha=$(debkit_shr_dados | awk -F'|' -v n="$nome" '$1 == n')
    if [ -z "$nome" ] || [ -z "$linha" ]; then
        msg_erro "$(t shr.remover_falhou "$nome" "$(t shr.nao_existe "$nome")")"; return 1
    fi
    IFS='|' read -r _ pasta esc lei _ <<< "$linha"
    acesso="${esc:-—}${lei:+;leitura:$lei}"
    debkit_shr_pasta_mexivel "$pasta" && seguro=1
    mapfile -t afetados < <(debkit_shr_usuarios "$esc,$lei")
    msg_info "$(t shr.removendo "$nome")"
    if ! debkit_smbconf_editar debkit_shr_filtro_remover debkit_shr_conferir_remover; then
        msg_erro "$(t shr.remover_falhou "$nome" "$(t shr.f_smbconf)")"
        debkit_auditar shr_remover "nome=$nome pasta=$pasta acesso=$acesso resultado=falha"
        return 1
    fi
    if debkit_shr_secoes | grep -qixF -- "$nome"; then
        debkit_smbconf_restaurar
        msg_erro "$(t shr.remover_falhou "$nome" "$(t usr.f_conferencia smb.conf)")"
        debkit_auditar shr_remover "nome=$nome pasta=$pasta acesso=$acesso resultado=falha"
        return 1
    fi
    if [ "$seguro" -eq 0 ]; then
        debkit_auditar shr_remover "nome=$nome pasta=$pasta acesso=$acesso resultado=ok pasta=intocada"
        msg_ok "$(t shr.removido "$nome")"
        msg_info "$(t shr.pasta_intocada "${pasta:-—}")"
    else
        # chmod com 5 dígitos: tira também o setgid da pasta
        chown 0:0 -- "$pasta" 2>/dev/null; chmod 00700 -- "$pasta" 2>/dev/null
        if [ "$(stat -c '%u %g %a' -- "$pasta" 2>/dev/null)" != "0 0 700" ]; then
            msg_erro "$(t shr.trancar_falhou "$nome" "$pasta")"
            debkit_auditar shr_remover "nome=$nome pasta=$pasta acesso=$acesso resultado=pasta_falhou"
            rc=1
        else
            debkit_auditar shr_remover "nome=$nome pasta=$pasta acesso=$acesso resultado=ok"
            msg_ok "$(t shr.removido "$nome")"
            msg_info "$(t shr.pasta_mantida "$pasta")"
        fi
    fi
    debkit_samba_reconectar "${afetados[@]}" || rc=1
    return "$rc"
}

# ── Compartilhamentos: trazer para o padrão (os já existentes) ──────────────
# Os fora do padrão que podem ser trazidos para ele (a pasta pode mudar;
# inclusive os de um grupo só que o debkit não gerencia, ex.: @users):
# nome|pasta|escrita|leitura|alertas
debkit_shr_padronizaveis() {
    local l nome pasta
    local -A ger=()
    while IFS='|' read -r nome _; do ger["$nome"]=1; done < <(debkit_shr_gerenciaveis)
    while IFS= read -r l; do
        IFS='|' read -r nome pasta _ <<< "$l"
        [ -n "${ger[$nome]:-}" ] && continue
        debkit_shr_pasta_mexivel "$pasta" && echo "$l"
    done < <(debkit_shr_dados)
}

# Linhas novas do padrão (as mesmas do bloco de criar)
debkit_shr_filtro_padrao() {
    debkit_shr_filtro_linhas "$DEBKIT_SHR_PADRAO" "$(printf '   valid users = @%s\n   read only = no\n   force group = %s\n   create mask = 0660\n   directory mask = 2770' \
        "$DEBKIT_S_GRUPO" "$DEBKIT_S_GRUPO")"
}

# Conferência: fora a seção, nada mudou; na seção, só as linhas substituídas
# mudaram, e agora são exatamente as do padrão
debkit_shr_conferir_padrao() {
    local outras=$'^\t(valid users|force group|read only|write list|read list|guest ok|guest only|create mask|directory mask|force create mode|force directory mode|force user|admin users|invalid users) = '
    cmp -s <(debkit_shr_sem_secao "$1" "$DEBKIT_S_NOME") <(debkit_shr_sem_secao "$2" "$DEBKIT_S_NOME") \
        && cmp -s <(debkit_shr_secao_efetiva "$1" "$DEBKIT_S_NOME" | grep -vE "$outras") \
                  <(debkit_shr_secao_efetiva "$2" "$DEBKIT_S_NOME" | grep -vE "$outras") \
        && [ "$(debkit_shr_secao_efetiva "$2" "$DEBKIT_S_NOME" | grep -E "$outras" | LC_ALL=C sort)" == \
             "$(printf '\tcreate mask = 0660\n\tdirectory mask = 02770\n\tforce group = %s\n\tread only = No\n\tvalid users = @%s' "$DEBKIT_S_GRUPO" "$DEBKIT_S_GRUPO")" ]
}

# Entrada: DEBKIT_S_NOME (fora do padrão, com a pasta podendo mudar) e
# DEBKIT_S_GRUPO (gerenciado). Decisão de 19/10/2026 (seção 3.7, item 6):
# mexe só nas linhas que o debkit gerencia (DEBKIT_SHR_PADRAO) e mantém o
# resto da seção; passa o conteúdo para o grupo e refaz as sessões de quem
# tinha o acesso (quem perde e quem passa de leitura para escrita).
debkit_shr_padronizar() {
    local nome="$DEBKIT_S_NOME" novo="$DEBKIT_S_GRUPO" linha pasta esc lei acesso rc=0
    local -a antes=()
    linha=$(debkit_shr_padronizaveis | awk -F'|' -v n="$nome" '$1 == n')
    if [ -z "$nome" ] || [ -z "$linha" ]; then
        msg_erro "$(t shr.padrao_falhou "$nome" "$(t shr.nao_padronizavel "$nome")")"; return 1
    fi
    IFS='|' read -r _ pasta esc lei _ <<< "$linha"
    if [ -z "$novo" ]; then msg_erro "$(t shr.padrao_falhou "$nome" "$(t shr.sem_grupo)")"; return 1; fi
    if ! debkit_grupo_gerenciado "$novo" || [[ ! "$novo" =~ ^[^[:space:],@+\&\"]+$ ]]; then
        msg_erro "$(t shr.padrao_falhou "$nome" "$(t grp.nao_gerenciado "$novo")")"; return 1
    fi
    acesso="${esc:-—}${lei:+;leitura:$lei}"
    mapfile -t antes < <(debkit_shr_usuarios "$esc,$lei")
    msg_info "$(t shr.padronizando "$nome")"
    if ! debkit_smbconf_editar debkit_shr_filtro_padrao debkit_shr_conferir_padrao; then
        msg_erro "$(t shr.padrao_falhou "$nome" "$(t shr.f_smbconf)")"
        debkit_auditar shr_padrao "nome=$nome antes=$acesso grupo=$novo resultado=falha"
        return 1
    fi
    if [ "$(debkit_shr_gerenciaveis | awk -F'|' -v n="$nome" '$1 == n')" != "$nome|$pasta|$novo" ]; then
        debkit_smbconf_restaurar
        msg_erro "$(t shr.padrao_falhou "$nome" "$(t usr.f_conferencia smb.conf)")"
        debkit_auditar shr_padrao "nome=$nome antes=$acesso grupo=$novo resultado=falha"
        return 1
    fi
    debkit_auditar shr_padrao "nome=$nome antes=$acesso grupo=$novo resultado=ok"
    msg_ok "$(t shr.padronizado "$nome" "$novo")"
    debkit_shr_ajustar_conteudo "$pasta" "$novo" || rc=1
    debkit_samba_reconectar "${antes[@]}" || rc=1
    return "$rc"
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
    local gecos nome sugestao problema tipo resp escolha n i mesma=1 com_home=0
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
    # Pasta pessoal (opcional; padrão: não). Na primeira vez define a base.
    echo ""
    if confirmar "$(t home.p_criar)"; then
        if debkit_samba_garantir_base; then com_home=1; else msg_aviso "$(t home.segue_sem)"; fi
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
    if [ "$com_home" -eq 1 ]; then echo "    $(t home.r_sim "$DEBKIT_HOMES_BASE/$nome")"; else echo "    $(t usr.r_home)"; fi
    echo ""
    if ! confirmar "$(t usr.p_confirmar)"; then
        DEBKIT_U_SENHA=""; DEBKIT_U_SENHA_LINUX=""
        msg_aviso "$(t usr.cancelado)"
        pausar; return 1
    fi
    DEBKIT_U_NOME="$nome"; DEBKIT_U_GECOS="$gecos"; DEBKIT_U_TIPO="$tipo"; DEBKIT_U_GRUPOS=("${escolhidos[@]}"); DEBKIT_U_HOME="$com_home"
    debkit_usuario_criar; local rc=$?
    DEBKIT_U_SENHA=""; DEBKIT_U_SENHA_LINUX=""
    if [ "$rc" -eq 0 ] && [ "$com_home" -eq 1 ]; then echo ""; debkit_samba_oferecer_homes; fi
    pausar
    return "$rc"
}

# Tela: criar a pasta pessoal de um usuário que ainda não tem
debkit_samba_tela_home_existente() {
    local escolha nome i
    local -a lista=()
    titulo "$(t home.titulo_criar)"
    if ! debkit_samba_ambiente_pronto; then msg_erro "$(t usr.ambiente_nao_pronto)"; pausar; return 1; fi
    mapfile -t lista < <(debkit_samba_usuarios_sem_home)
    if [ ${#lista[@]} -eq 0 ]; then msg_info "$(t home.sem_candidatos)"; pausar; return 0; fi
    echo "  $(t home.titulo_usuarios)"
    for i in "${!lista[@]}"; do echo "    $((i + 1))) ${lista[$i]}"; done
    while true; do
        debkit_ler escolha "$(t home.p_usuario)" || { msg_aviso "$(t usr.cancelado)"; return 1; }
        [ -z "$escolha" ] && { msg_aviso "$(t usr.cancelado)"; return 1; }
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$((10#$escolha))" -ge 1 ] && [ "$((10#$escolha))" -le ${#lista[@]} ]; then
            nome="${lista[$((10#$escolha - 1))]}"; break
        fi
        msg_erro "$(t geral.opcao_invalida "$escolha")"
    done
    if ! debkit_samba_garantir_base; then pausar; return 1; fi
    if ! confirmar "$(t home.p_confirmar "$DEBKIT_HOMES_BASE/$nome" "$nome")"; then
        msg_aviso "$(t usr.cancelado)"; pausar; return 1
    fi
    if debkit_samba_home_existente "$nome"; then echo ""; debkit_samba_oferecer_homes; fi
    pausar
}

# Tela: base das pastas pessoais e [homes]
debkit_samba_tela_pastas_pessoais() {
    local problema
    titulo "$(t home.titulo)"
    if ! debkit_samba_ambiente_pronto; then msg_erro "$(t usr.ambiente_nao_pronto)"; pausar; return 1; fi
    if [ -z "$DEBKIT_HOMES_BASE" ]; then
        echo "  $(t home.base_nenhuma)"
        debkit_samba_escolher_base || { pausar; return 1; }
    else
        echo "  $(t home.base_atual "$DEBKIT_HOMES_BASE")"
        if ! problema=$(debkit_samba_base_problema "$DEBKIT_HOMES_BASE"); then
            msg_erro "$(t home.base_invalida_agora "$DEBKIT_HOMES_BASE" "$problema")"
        fi
    fi
    echo ""
    case "$(debkit_samba_homes_estado)" in
        ok) msg_ok "$(t homes.estado_ok)" ;;
        *)  debkit_samba_oferecer_homes ;;
    esac
    pausar
}

# Tela: escolhe o usuário, mostra o que será perdido e pede UMA confirmação (s/n)
debkit_samba_tela_excluir_usuario() {
    local nome tipo problema destino home n uid rc
    local -a nomes=() rotulos=() grupos=() usos=() sessoes=()
    titulo "$(t rmu.titulo)"
    if ! debkit_samba_ambiente_pronto; then msg_erro "$(t usr.ambiente_nao_pronto)"; pausar; return 1; fi
    while IFS='|' read -r nome _ tipo _ _ _ _; do
        if [ -z "$tipo" ] || [ "$tipo" == "admin" ] || [ "$nome" == "$(debkit_quem_roda)" ]; then continue; fi
        nomes+=("$nome"); rotulos+=("$(debkit_pad "$nome" 20) $(t "lst.t_$tipo")")
    done < <(debkit_samba_usuarios_dados)
    if [ ${#nomes[@]} -eq 0 ]; then msg_info "$(t rmu.sem_usuarios)"; pausar; return 0; fi
    echo "  $(t sen.titulo_usuarios)"
    debkit_numerar "${rotulos[@]}"
    debkit_escolher_um nome "$(t sen.p_usuario)" "${nomes[@]}" || { msg_aviso "$(t usr.cancelado)"; return 1; }
    echo ""
    if ! problema=$(debkit_usuario_exclusao_problema "$nome"); then msg_erro "$problema"; pausar; return 1; fi
    IFS=: read -r _ _ uid _ _ home _ < <(getent passwd "$nome")
    mapfile -t grupos < <(id -nG -- "$nome" 2>/dev/null | tr ' ' '\n' | grep -vxF -e "$nome" -e "$DEBKIT_GRUPO_USUARIOS")
    mapfile -t usos < <(debkit_samba_usuario_usos "$nome")
    mapfile -t sessoes < <(debkit_samba_sessoes "$nome")
    destino=$(debkit_usuario_home_destino "$nome")
    echo "  $(t rmu.titulo_perde "$nome")"
    echo "    $(t usr.r_tipo "$(t "lst.t_$(debkit_usuario_tipo "$nome")")")"
    if debkit_samba_conta_existe "$nome"; then echo "    $(t rmu.r_contas)"; else echo "    $(t rmu.r_contas_linux)"; fi
    echo "    $(t usr.r_grupos "$(debkit_juntar "${grupos[@]}")")"
    case "$destino" in
        apagar)   echo "    $(t rmu.r_home_apagar "$home")" ;;
        nenhuma)  echo "    $(t rmu.r_home_nenhuma)" ;;
        manter:*) echo "    $(t rmu.r_home_manter "$home" "${destino#manter:}")" ;;
    esac
    [ ${#sessoes[@]} -gt 0 ] && msg_aviso "$(t rmu.aviso_sessoes "${#sessoes[@]}")"
    [ ${#usos[@]} -gt 0 ] && msg_aviso "$(t rmu.aviso_usos "$DEBKIT_SMB_CONF" "$(printf '[%s] ' "${usos[@]}")")"
    msg_info "$(t rmu.procurando "$uid")"
    if [ "$destino" == "apagar" ]; then n=$(debkit_contar_arquivos -user "$uid" "$home"); else n=$(debkit_contar_arquivos -user "$uid"); fi
    if [ "$n" -ge "$DEBKIT_GRP_ARQUIVOS_MAX" ]; then msg_aviso "$(t rmu.aviso_arquivos_muitos "$n" "$uid")"
    elif [ "$n" -gt 0 ]; then msg_aviso "$(t rmu.aviso_arquivos "$n" "$uid")"
    else msg_info "$(t rmu.sem_arquivos)"
    fi
    echo ""
    if ! confirmar "$(t rmu.p_confirmar "$nome")"; then msg_aviso "$(t usr.cancelado)"; pausar; return 1; fi
    debkit_usuario_excluir "$nome"; rc=$?
    pausar
    return "$rc"
}

# Tela: lista o que está fora do padrão e corrige um a um (s/n em cada)
debkit_samba_tela_consistencia() {
    local l tipo nome feitos=0
    local -a itens=()
    titulo "$(t cns.titulo)"
    if ! debkit_samba_ambiente_pronto; then msg_erro "$(t usr.ambiente_nao_pronto)"; pausar; return 1; fi
    mapfile -t itens < <(debkit_samba_inconsistencias)
    if [ ${#itens[@]} -eq 0 ]; then msg_ok "$(t cns.tudo_ok)"; pausar; return 0; fi
    echo "  $(t cns.encontrados "${#itens[@]}")"
    for l in "${itens[@]}"; do
        IFS='|' read -r tipo nome <<< "$l"
        echo "    - $(t "cns.p_$tipo" "$nome" "$DEBKIT_GRUPO_USUARIOS")"
    done
    for l in "${itens[@]}"; do
        IFS='|' read -r tipo nome <<< "$l"
        echo ""
        echo "  $(t "cns.p_$tipo" "$nome" "$DEBKIT_GRUPO_USUARIOS")"
        confirmar "  $(t "cns.q_$tipo" "$nome" "$DEBKIT_GRUPO_USUARIOS")" || { msg_info "$(t cns.pulado)"; continue; }
        if [ "$tipo" == "so_linux" ]; then
            DEBKIT_U_SENHA=""
            debkit_ler_senha DEBKIT_U_SENHA "$(t cns.p_senha "$nome")" || { msg_info "$(t cns.pulado)"; continue; }
        fi
        "debkit_consist_$tipo" "$nome" && feitos=$((feitos + 1))
        DEBKIT_U_SENHA=""
    done
    echo ""
    msg_info "$(t cns.resumo "$feitos" "${#itens[@]}")"
    pausar
}

# ── Compartilhamentos: telas ────────────────────────────────────────────────
debkit_shr_tela_listar() {
    titulo "$(t shr.titulo_listar)"
    debkit_shr_listar
    pausar
}

# Tela: nome, descrição, pasta, o grupo (acesso total), resumo e
# UMA confirmação
debkit_shr_tela_criar() {
    local nome comentario pasta sugestao problema rc grupo cheia
    local -a grupos=()
    titulo "$(t shr.titulo_criar)"
    if ! debkit_samba_ambiente_pronto; then msg_erro "$(t usr.ambiente_nao_pronto)"; pausar; return 1; fi
    mapfile -t grupos < <(debkit_samba_grupos_comuns)
    if [ ${#grupos[@]} -eq 0 ]; then msg_info "$(t shr.crie_grupo)"; pausar; return 1; fi
    msg_info "$(t shr.dica_nome)"
    while true; do
        debkit_ler nome "$(t shr.p_nome)" || { msg_aviso "$(t usr.cancelado)"; return 1; }
        [ -z "$nome" ] && { msg_aviso "$(t usr.cancelado)"; return 1; }
        problema=$(debkit_shr_nome_problema "$nome") && break
        msg_erro "$problema"
    done
    while true; do
        debkit_ler comentario "$(t shr.p_comentario)" || { msg_aviso "$(t usr.cancelado)"; return 1; }
        problema=$(debkit_shr_comentario_problema "$comentario") && break
        msg_erro "$problema"
    done
    debkit_shr_garantir_base || { pausar; return 1; }
    sugestao="$DEBKIT_SHARES_BASE/$nome"
    echo ""
    while true; do
        debkit_ler pasta "$(t shr.p_pasta "$sugestao")" || { msg_aviso "$(t usr.cancelado)"; return 1; }
        [ -z "$pasta" ] && pasta="$sugestao"
        problema=$(debkit_shr_pasta_problema "$pasta") && break
        msg_erro "$problema"
    done
    echo ""
    msg_info "$(t shr.dica_grupo)"
    echo "  $(t grp.titulo_grupos)"
    debkit_numerar "${grupos[@]}"
    debkit_escolher_um grupo "$(t shr.p_grupo)" "${grupos[@]}" || { msg_aviso "$(t usr.cancelado)"; return 1; }
    echo ""
    echo "  $(t usr.titulo_resumo)"
    echo "    $(t shr.r_nome "$nome")"
    [ -n "$comentario" ] && echo "    $(t shr.r_comentario "$comentario")"
    if [ -d "$pasta" ]; then echo "    $(t shr.r_pasta_existe "$pasta")"; else echo "    $(t shr.r_pasta_nova "$pasta")"; fi
    echo "    $(t shr.r_grupo "$grupo")"
    cheia=0
    if [ -d "$pasta" ] && [ -n "$(ls -A -- "$pasta" 2>/dev/null)" ]; then cheia=1; msg_aviso "$(t shr.aviso_conteudo "$pasta")"; fi
    echo ""
    if ! confirmar "$(t shr.p_confirmar)"; then msg_aviso "$(t usr.cancelado)"; pausar; return 1; fi
    DEBKIT_S_NOME="$nome"; DEBKIT_S_COMENTARIO="$comentario"; DEBKIT_S_PASTA="$pasta"
    DEBKIT_S_GRUPO="$grupo"
    debkit_shr_criar; rc=$?
    if [ "$rc" -eq 0 ] && [ "$cheia" -eq 1 ]; then
        echo ""
        debkit_shr_mostrar_conteudo "$pasta" "$grupo"
        if [ "$DEBKIT_SHR_FORA_N" -gt 0 ] && confirmar "$(t shr.p_ajustar_agora "$grupo")"; then
            debkit_shr_ajustar_conteudo "$pasta" "$grupo" || rc=1
        fi
    fi
    pausar
    return "$rc"
}

# Escolhe um compartilhamento: debkit_shr_escolher <variável da linha>
# [gerenciaveis (padrão; nome|pasta|grupo) | dados | padronizaveis (as
# linhas de debkit_shr_dados)]. Retorna 1 se não há nenhum ou cancelou.
debkit_shr_escolher() {
    local -n _linha="$1"
    local fonte="${2:-gerenciaveis}" l n p g e nome
    local -a linhas=() nomes=() rotulos=()
    mapfile -t linhas < <("debkit_shr_$fonte")
    if [ ${#linhas[@]} -eq 0 ]; then
        case "$fonte" in
            dados)         msg_info "$(t shr.nenhum)" ;;
            padronizaveis) msg_info "$(t shr.nenhum_padronizavel)" ;;
            *)             msg_info "$(t shr.nenhum_gerenciavel)" ;;
        esac
        return 1
    fi
    for l in "${linhas[@]}"; do
        if [ "$fonte" == "gerenciaveis" ]; then
            IFS='|' read -r n p g <<< "$l"
            rotulos+=("$(t shr.item "$n" "$g" "$p")")
        else
            IFS='|' read -r n p e g _ <<< "$l"
            rotulos+=("$(t shr.item_acesso "$n" "$(debkit_shr_rotulo_acesso "$e" "$g")" "${p:-—}")")
        fi
        nomes+=("$n")
    done
    echo "  $(t shr.titulo_lista)"
    debkit_numerar "${rotulos[@]}"
    debkit_escolher_um nome "$(t shr.p_compartilhamento)" "${nomes[@]}" || { msg_aviso "$(t usr.cancelado)"; return 1; }
    for l in "${linhas[@]}"; do [ "${l%%|*}" == "$nome" ] && _linha="$l"; done
    return 0
}

# Mostra quantos itens há na pasta e quantos estão fora do padrão (deixa o
# número em DEBKIT_SHR_FORA_N)
debkit_shr_mostrar_conteudo() {
    local pasta="$1" grupo="$2" total
    total=$(debkit_shr_contar "$pasta")
    DEBKIT_SHR_FORA_N=$(debkit_shr_pendentes "$pasta" "$(getent group "$grupo" | cut -d: -f3)")
    if [ "$DEBKIT_SHR_FORA_N" -eq 0 ]; then
        msg_info "$(t shr.conteudo_ok "$pasta" "$total")"
    else
        msg_info "$(t shr.conteudo "$pasta" "$total" "$DEBKIT_SHR_FORA_N")"
    fi
}

# Tela: compartilhamento, grupo novo, resumo (quem perde o acesso, quem está
# conectado, o conteúdo) e UMA confirmação
debkit_shr_tela_trocar() {
    local linha nome pasta antigo novo rc g
    local -a grupos=() perdem=() todos=()
    titulo "$(t shr.trocar)"
    if ! debkit_samba_ambiente_pronto; then msg_erro "$(t usr.ambiente_nao_pronto)"; pausar; return 1; fi
    debkit_shr_escolher linha || { pausar; return 1; }
    IFS='|' read -r nome pasta antigo <<< "$linha"
    mapfile -t todos < <(debkit_samba_grupos_comuns)
    for g in "${todos[@]}"; do [ "$g" != "$antigo" ] && grupos+=("$g"); done
    echo ""
    msg_info "$(t shr.atual "$antigo" "$pasta")"
    if [ ${#grupos[@]} -eq 0 ]; then msg_info "$(t shr.sem_outro_grupo)"; pausar; return 1; fi
    echo "  $(t grp.titulo_grupos)"
    debkit_numerar "${grupos[@]}"
    debkit_escolher_um novo "$(t shr.p_novo_grupo)" "${grupos[@]}" || { msg_aviso "$(t usr.cancelado)"; return 1; }
    echo ""
    echo "  $(t usr.titulo_resumo)"
    echo "    $(t shr.r_nome "$nome")"
    echo "    $(t shr.r_troca "$antigo" "$novo")"
    mapfile -t perdem < <(debkit_shr_perdem "$antigo" "$novo")
    if [ ${#perdem[@]} -gt 0 ]; then
        msg_aviso "$(t shr.aviso_perdem "$antigo" "$novo" "$(debkit_juntar "${perdem[@]}")")"
        debkit_aviso_conectados "${perdem[@]}"
    fi
    debkit_shr_mostrar_conteudo "$pasta" "$antigo"
    msg_info "$(t shr.explica_ajuste "$novo")"
    echo ""
    if ! confirmar "$(t shr.p_confirmar_trocar "$nome" "$novo")"; then msg_aviso "$(t usr.cancelado)"; pausar; return 1; fi
    DEBKIT_S_NOME="$nome"; DEBKIT_S_GRUPO="$novo"
    debkit_shr_trocar_grupo; rc=$?
    pausar
    return "$rc"
}

# Tela: compartilhamento, quanto está fora do padrão e UMA confirmação
debkit_shr_tela_ajustar() {
    local linha nome pasta grupo rc
    titulo "$(t shr.ajustar)"
    if ! debkit_samba_ambiente_pronto; then msg_erro "$(t usr.ambiente_nao_pronto)"; pausar; return 1; fi
    debkit_shr_escolher linha || { pausar; return 1; }
    IFS='|' read -r nome pasta grupo <<< "$linha"
    echo ""
    debkit_shr_mostrar_conteudo "$pasta" "$grupo"
    if [ "$DEBKIT_SHR_FORA_N" -eq 0 ]; then pausar; return 0; fi
    msg_info "$(t shr.explica_ajuste "$grupo")"
    echo ""
    if ! confirmar "$(t shr.p_confirmar_ajustar "$nome")"; then msg_aviso "$(t usr.cancelado)"; pausar; return 1; fi
    debkit_shr_ajustar_conteudo "$pasta" "$grupo"; rc=$?
    pausar
    return "$rc"
}

# Tela: compartilhamento, resumo (pasta que fica, quem perde o acesso, quem
# está conectado) e UMA confirmação
debkit_shr_tela_remover() {
    local linha nome pasta esc lei rc
    local -a afetados=()
    titulo "$(t shr.remover)"
    if ! debkit_samba_ambiente_pronto; then msg_erro "$(t usr.ambiente_nao_pronto)"; pausar; return 1; fi
    debkit_shr_escolher linha dados || { pausar; return 1; }
    IFS='|' read -r nome pasta esc lei _ <<< "$linha"
    echo ""
    echo "  $(t usr.titulo_resumo)"
    echo "    $(t shr.r_nome "$nome")"
    if debkit_shr_pasta_mexivel "$pasta"; then
        echo "    $(t shr.r_pasta_fica "$pasta")"
    else
        echo "    $(t shr.r_pasta_intocada "${pasta:-—}")"
    fi
    mapfile -t afetados < <(debkit_shr_usuarios "$esc,$lei")
    if [ ${#afetados[@]} -gt 0 ]; then
        msg_aviso "$(t shr.aviso_perdem_lista "$(debkit_juntar "${afetados[@]}")")"
        debkit_aviso_conectados "${afetados[@]}"
    fi
    echo ""
    if ! confirmar "$(t shr.p_confirmar_remover "$nome")"; then msg_aviso "$(t usr.cancelado)"; pausar; return 1; fi
    DEBKIT_S_NOME="$nome"
    debkit_shr_remover; rc=$?
    pausar
    return "$rc"
}

# Tela: compartilhamento fora do padrão, grupo, resumo (quem perde, quem
# está conectado, as linhas do smb.conf, o conteúdo) e UMA confirmação
debkit_shr_tela_padronizar() {
    local linha nome pasta esc lei novo rc
    local -a grupos=() antes=() perdem=()
    titulo "$(t shr.padronizar)"
    if ! debkit_samba_ambiente_pronto; then msg_erro "$(t usr.ambiente_nao_pronto)"; pausar; return 1; fi
    debkit_shr_escolher linha padronizaveis || { pausar; return 1; }
    IFS='|' read -r nome pasta esc lei _ <<< "$linha"
    mapfile -t grupos < <(debkit_samba_grupos_comuns)
    echo ""
    msg_info "$(t shr.acesso_atual "$(debkit_shr_rotulo_acesso "$esc" "$lei")" "$pasta")"
    if [ ${#grupos[@]} -eq 0 ]; then msg_info "$(t shr.crie_grupo)"; pausar; return 1; fi
    echo "  $(t grp.titulo_grupos)"
    debkit_numerar "${grupos[@]}"
    debkit_escolher_um novo "$(t shr.p_grupo_padrao)" "${grupos[@]}" || { msg_aviso "$(t usr.cancelado)"; return 1; }
    echo ""
    echo "  $(t usr.titulo_resumo)"
    echo "    $(t shr.r_nome "$nome")"
    echo "    $(t shr.r_padrao "$(debkit_shr_rotulo_acesso "$esc" "$lei")" "$novo")"
    mapfile -t antes < <(debkit_shr_usuarios "$esc,$lei")
    mapfile -t perdem < <(debkit_shr_fora_do_grupo "$novo" "${antes[@]}")
    if [ ${#perdem[@]} -gt 0 ]; then
        msg_aviso "$(t shr.aviso_perdem_lista "$(debkit_juntar "${perdem[@]}")")"
    fi
    debkit_aviso_conectados "${antes[@]}"
    msg_info "$(t shr.explica_padrao "$novo" "$novo")"
    debkit_shr_mostrar_conteudo "$pasta" "$novo"
    msg_info "$(t shr.explica_ajuste "$novo")"
    echo ""
    if ! confirmar "$(t shr.p_confirmar_padrao "$nome" "$novo")"; then msg_aviso "$(t usr.cancelado)"; pausar; return 1; fi
    DEBKIT_S_NOME="$nome"; DEBKIT_S_GRUPO="$novo"
    debkit_shr_padronizar; rc=$?
    pausar
    return "$rc"
}

# ── Grupos: telas ───────────────────────────────────────────────────────────
# Escolhe UM item numerado: debkit_escolher_um <variável> <prompt> <itens...>.
# Retorna 1 se cancelar (Enter vazio ou fim da entrada).
debkit_escolher_um() {
    local -n _item="$1"
    local prompt="$2" escolha
    shift 2
    local -a _lista=("$@")
    while true; do
        debkit_ler escolha "$prompt" || return 1
        [ -z "$escolha" ] && return 1
        if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$((10#$escolha))" -ge 1 ] && [ "$((10#$escolha))" -le $# ]; then
            _item="${_lista[$((10#$escolha - 1))]}"; return 0
        fi
        msg_erro "$(t geral.opcao_invalida "$escolha")"
    done
}

# Escolhe VÁRIOS itens numerados (vírgula ou espaço; Enter = nenhum):
# debkit_escolher_varios <array> <prompt> <itens...>. Retorna 1 no fim da entrada.
debkit_escolher_varios() {
    local -n _itens="$1"
    local prompt="$2" escolha n problema
    local -a _partes=()
    shift 2
    local -a _lista=("$@")
    while true; do
        debkit_ler escolha "$prompt" || return 1
        _itens=(); problema=""
        read -ra _partes <<< "${escolha//,/ }"      # sem expandir * e ? digitados
        for n in "${_partes[@]}"; do
            if [[ "$n" =~ ^[0-9]+$ ]] && [ "$((10#$n))" -ge 1 ] && [ "$((10#$n))" -le $# ]; then
                n="${_lista[$((10#$n - 1))]}"
                [[ " ${_itens[*]} " == *" $n "* ]] || _itens+=("$n")
            else
                problema="$n"; break
            fi
        done
        [ -z "$problema" ] && return 0
        msg_erro "$(t usr.grupos_invalido "$problema")"
    done
}

# Avisa (antes da confirmação) quem está conectado ao Samba e será reconectado
debkit_aviso_conectados() {
    local -a con=()
    [ $# -gt 0 ] || return 0
    mapfile -t con < <(debkit_samba_conectados "$@")
    [ ${#con[@]} -gt 0 ] && msg_aviso "$(t ses.aviso "$(debkit_juntar "${con[@]}")")"
    return 0
}

# Lista numerada (4 espaços de recuo)
debkit_numerar() { local i=0 x; for x in "$@"; do i=$((i + 1)); echo "    $i) $x"; done; }

# Junta com ", " (ou "(nenhum)")
debkit_juntar() { if [ $# -eq 0 ]; then t usr.r_nenhum; else local IFS=,; local s="$*"; printf '%s' "${s//,/, }"; fi; }

# Mostra a tabela de grupos: nome, GID, membros e compartilhamentos que usam
debkit_samba_listar_grupos() {
    local g gid membros principais usos wg=5
    local -a grupos=()
    mapfile -t grupos < <(debkit_samba_grupos_comuns)
    if [ ${#grupos[@]} -eq 0 ]; then msg_info "$(t grp.nenhum)"; return 0; fi
    for g in "${grupos[@]}"; do [ "${#g}" -gt "$wg" ] && wg=${#g}; done
    printf '  %s%s  %s  %s%s\n' "$C_NEGRITO" "$(debkit_pad "$(t grp.c_grupo)" "$wg")" "$(debkit_pad GID 6)" "$(t grp.c_membros)" "$C_RESET"
    for g in "${grupos[@]}"; do
        gid=$(getent group "$g" | cut -d: -f3)
        membros=$(debkit_grupo_membros "$g" | paste -sd, | sed 's/,/, /g')
        principais=$(debkit_grupo_principais "$g" | sed "s/\$/ $(t grp.marca_principal)/" | paste -sd, | sed 's/,/, /g')
        [ -n "$principais" ] && membros="${membros:+$membros, }$principais"
        printf '  %s  %s  %s\n' "$(debkit_pad "$g" "$wg")" "$(debkit_pad "$gid" 6)" "${membros:-—}"
        usos=$(debkit_samba_grupo_usos "$g" | sed 's/.*/[&]/' | paste -sd' ')
        [ -n "$usos" ] && printf '  %s  %s  %s%s%s\n' "$(debkit_pad "" "$wg")" "$(debkit_pad "" 6)" "$C_CINZA" "$(t grp.usado_em "$usos")" "$C_RESET"
    done
    echo ""
    echo "  $(t grp.total "${#grupos[@]}")"
}

debkit_samba_tela_listar_grupos() {
    titulo "$(t grp.titulo_listar)"
    debkit_samba_listar_grupos
    pausar
}

# Tela: nome, membros, resumo e UMA confirmação
debkit_samba_tela_criar_grupo() {
    local nome problema rc
    local -a usuarios=() escolhidos=()
    titulo "$(t grp.titulo_criar)"
    if ! debkit_samba_ambiente_pronto; then msg_erro "$(t usr.ambiente_nao_pronto)"; pausar; return 1; fi
    msg_info "$(t grp.dica_nome)"
    while true; do
        debkit_ler nome "$(t grp.p_nome)" || { msg_aviso "$(t usr.cancelado)"; return 1; }
        [ -z "$nome" ] && { msg_aviso "$(t usr.cancelado)"; return 1; }
        problema=$(debkit_grupo_nome_problema "$nome") && break
        msg_erro "$problema"
    done
    mapfile -t usuarios < <(debkit_samba_usuarios_comuns)
    echo ""
    echo "  $(t grp.titulo_usuarios)"
    if [ ${#usuarios[@]} -eq 0 ]; then
        echo "    $(t grp.sem_usuarios)"
    else
        debkit_numerar "${usuarios[@]}"
        debkit_escolher_varios escolhidos "$(t grp.p_membros)" "${usuarios[@]}" || { msg_aviso "$(t usr.cancelado)"; return 1; }
    fi
    echo ""
    echo "  $(t usr.titulo_resumo)"
    echo "    $(t grp.r_grupo "$nome")"
    echo "    $(t grp.r_membros "$(debkit_juntar "${escolhidos[@]}")")"
    debkit_aviso_conectados "${escolhidos[@]}"
    echo ""
    if ! confirmar "$(t grp.p_confirmar_criar)"; then msg_aviso "$(t usr.cancelado)"; pausar; return 1; fi
    DEBKIT_G_NOME="$nome"; DEBKIT_G_MEMBROS=("${escolhidos[@]}")
    debkit_grupo_criar; rc=$?
    pausar
    return "$rc"
}

# Tela: escolhe o grupo, mostra os membros e adiciona ou tira
debkit_samba_tela_membros() {
    local grupo acao u rc
    local -a grupos=() atuais=() principais=() candidatos=() escolhidos=() outros=()
    titulo "$(t grp.titulo_membros)"
    if ! debkit_samba_ambiente_pronto; then msg_erro "$(t usr.ambiente_nao_pronto)"; pausar; return 1; fi
    mapfile -t grupos < <(debkit_samba_grupos_comuns)
    if [ ${#grupos[@]} -eq 0 ]; then msg_info "$(t grp.nenhum)"; pausar; return 0; fi
    echo "  $(t grp.titulo_grupos)"
    debkit_numerar "${grupos[@]}"
    debkit_escolher_um grupo "$(t grp.p_grupo)" "${grupos[@]}" || { msg_aviso "$(t usr.cancelado)"; return 1; }
    mapfile -t principais < <(debkit_grupo_principais "$grupo")
    # Membros comuns (podem sair) e outros membros (de sistema: o debkit não mexe)
    while read -r u; do
        [ -n "$u" ] || continue
        if debkit_samba_usuarios_comuns | grep -qxF -- "$u"; then atuais+=("$u"); else outros+=("$u"); fi
    done < <(debkit_grupo_membros "$grupo")
    echo ""
    echo "  $(t grp.r_membros "$(debkit_juntar "${atuais[@]}")")"
    [ ${#outros[@]} -gt 0 ] && echo "  $(t grp.r_outros "$(debkit_juntar "${outros[@]}")")"
    [ ${#principais[@]} -gt 0 ] && echo "  $(t grp.r_principais "$(debkit_juntar "${principais[@]}")")"
    echo ""
    echo "    1) $(t grp.a_entrar)"
    echo "    2) $(t grp.a_sair)"
    while true; do
        debkit_ler acao "$(t grp.p_acao)" || { msg_aviso "$(t usr.cancelado)"; return 1; }
        case "$acao" in
            "") msg_aviso "$(t usr.cancelado)"; return 1 ;;
            1|2) break ;;
            *) msg_erro "$(t geral.opcao_invalida "$acao")" ;;
        esac
    done
    DEBKIT_G_ENTRAR=(); DEBKIT_G_SAIR=()
    if [ "$acao" == 1 ]; then
        while read -r u; do
            [[ " ${atuais[*]} ${principais[*]} " == *" $u "* ]] || candidatos+=("$u")
        done < <(debkit_samba_usuarios_comuns)
    else
        candidatos=("${atuais[@]}")
    fi
    echo ""
    if [ ${#candidatos[@]} -eq 0 ]; then
        if [ "$acao" == 1 ]; then msg_info "$(t grp.sem_candidatos_entrar "$grupo")"; else msg_info "$(t grp.sem_candidatos_sair "$grupo")"; fi
        pausar; return 0
    fi
    echo "  $(t grp.titulo_usuarios)"
    debkit_numerar "${candidatos[@]}"
    debkit_escolher_varios escolhidos "$(t grp.p_usuarios)" "${candidatos[@]}" || { msg_aviso "$(t usr.cancelado)"; return 1; }
    if [ ${#escolhidos[@]} -eq 0 ]; then msg_aviso "$(t usr.cancelado)"; pausar; return 1; fi
    echo ""
    debkit_aviso_conectados "${escolhidos[@]}"
    if [ "$acao" == 1 ]; then
        DEBKIT_G_ENTRAR=("${escolhidos[@]}")
        confirmar "$(t grp.p_confirmar_entrar "$(debkit_juntar "${escolhidos[@]}")" "$grupo")" || { msg_aviso "$(t usr.cancelado)"; pausar; return 1; }
    else
        DEBKIT_G_SAIR=("${escolhidos[@]}")
        confirmar "$(t grp.p_confirmar_sair "$(debkit_juntar "${escolhidos[@]}")" "$grupo")" || { msg_aviso "$(t usr.cancelado)"; pausar; return 1; }
    fi
    debkit_grupo_alterar_membros "$grupo"; rc=$?
    pausar
    return "$rc"
}

# Tela: escolhe o grupo, recusa o principal de alguém e o usado no smb.conf,
# mostra o que será perdido (membros, arquivos) e pede UMA confirmação (s/n)
debkit_samba_tela_remover_grupo() {
    local grupo gid n rc
    local -a grupos=() membros=() usos=() principais=()
    titulo "$(t grp.titulo_remover)"
    if ! debkit_samba_ambiente_pronto; then msg_erro "$(t usr.ambiente_nao_pronto)"; pausar; return 1; fi
    mapfile -t grupos < <(debkit_samba_grupos_comuns)
    if [ ${#grupos[@]} -eq 0 ]; then msg_info "$(t grp.nenhum)"; pausar; return 0; fi
    echo "  $(t grp.titulo_grupos)"
    debkit_numerar "${grupos[@]}"
    debkit_escolher_um grupo "$(t grp.p_grupo)" "${grupos[@]}" || { msg_aviso "$(t usr.cancelado)"; return 1; }
    echo ""
    mapfile -t principais < <(debkit_grupo_principais "$grupo")
    if [ ${#principais[@]} -gt 0 ]; then
        msg_erro "$(t grp.remover_principal "$grupo" "$(debkit_juntar "${principais[@]}")")"; pausar; return 1
    fi
    mapfile -t usos < <(debkit_samba_grupo_usos "$grupo")
    if [ ${#usos[@]} -gt 0 ]; then
        msg_erro "$(t grp.remover_usado "$grupo" "$(printf '[%s] ' "${usos[@]}" | sed 's/ $//')")"; pausar; return 1
    fi
    mapfile -t membros < <(debkit_grupo_membros "$grupo")
    gid=$(getent group "$grupo" | cut -d: -f3)
    if [ ${#membros[@]} -gt 0 ]; then
        msg_aviso "$(t grp.aviso_membros "${#membros[@]}" "$(debkit_juntar "${membros[@]}")")"
    else
        msg_info "$(t grp.sem_membros)"
    fi
    debkit_aviso_conectados "${membros[@]}"
    msg_info "$(t grp.procurando "$gid")"
    n=$(debkit_grupo_contar_arquivos "$gid")
    if [ "$n" -ge "$DEBKIT_GRP_ARQUIVOS_MAX" ]; then
        msg_aviso "$(t grp.aviso_arquivos_muitos "$n" "$gid")"
    elif [ "$n" -gt 0 ]; then
        msg_aviso "$(t grp.aviso_arquivos "$n" "$gid")"
    else
        msg_info "$(t grp.sem_arquivos)"
    fi
    echo ""
    if ! confirmar "$(t grp.p_confirmar_remover "$grupo")"; then msg_aviso "$(t usr.cancelado)"; pausar; return 1; fi
    debkit_grupo_remover "$grupo"; rc=$?
    pausar
    return "$rc"
}

# Submenu de grupos
debkit_samba_menu_grupos() {
    local opcao
    while true; do
        titulo "$(t grp.titulo)"
        echo "  1) $(t grp.listar)"
        echo "  2) $(t grp.criar)"
        echo "  3) $(t grp.membros)"
        echo "  4) $(t grp.remover)"
        echo ""
        echo "  0) $(t geral.voltar)"
        echo ""
        ler_opcao opcao
        case "$opcao" in
            "") continue ;;
            1)  debkit_samba_tela_listar_grupos ;;
            2)  debkit_samba_tela_criar_grupo ;;
            3)  debkit_samba_tela_membros ;;
            4)  debkit_samba_tela_remover_grupo ;;
            0)  return 0 ;;
            *)  msg_erro "$(t geral.opcao_invalida "$opcao")"; pausar ;;
        esac
    done
}

# ── Menu ────────────────────────────────────────────────────────────────────
# Samba: Usuários, Grupos e Compartilhamentos, cada um com o seu submenu
debkit_samba_menu() {
    local opcao
    while true; do
        titulo "$(t samba.titulo)"
        echo "  1) $(t samba.usuarios)"
        echo "  2) $(t samba.grupos)"
        echo "  3) $(t samba.compartilhamentos)"
        echo ""
        echo "  0) $(t geral.voltar)"
        echo ""
        ler_opcao opcao
        case "$opcao" in
            "") continue ;;
            1)  debkit_samba_menu_usuarios ;;
            2)  debkit_samba_menu_grupos ;;
            3)  debkit_samba_menu_compartilhamentos ;;
            0)  return 0 ;;
            *)  msg_erro "$(t geral.opcao_invalida "$opcao")"; pausar ;;
        esac
    done
}

debkit_samba_menu_usuarios() {
    local opcao
    while true; do
        titulo "$(t samba.titulo_usuarios)"
        echo "  1) $(t samba.listar_usuarios)"
        echo "  2) $(t samba.criar_usuario)"
        echo "  3) $(t samba.trocar_senha)"
        echo "  4) $(t samba.criar_home)"
        echo "  5) $(t samba.excluir_usuario)"
        echo "  6) $(t samba.consistencia)"
        echo ""
        echo "  0) $(t geral.voltar)"
        echo ""
        ler_opcao opcao
        case "$opcao" in
            "") continue ;;
            1)  debkit_samba_tela_listar_usuarios ;;
            2)  debkit_samba_tela_criar_usuario ;;
            3)  debkit_samba_tela_trocar_senha ;;
            4)  debkit_samba_tela_home_existente ;;
            5)  debkit_samba_tela_excluir_usuario ;;
            6)  debkit_samba_tela_consistencia ;;
            0)  return 0 ;;
            *)  msg_erro "$(t geral.opcao_invalida "$opcao")"; pausar ;;
        esac
    done
}

# Compartilhamentos: listar, criar, trocar o grupo, ajustar as permissões,
# remover, trazer para o padrão e o [homes]
debkit_samba_menu_compartilhamentos() {
    local opcao
    while true; do
        titulo "$(t samba.titulo_compartilhamentos)"
        echo "  1) $(t shr.listar)"
        echo "  2) $(t shr.criar)"
        echo "  3) $(t shr.trocar)"
        echo "  4) $(t shr.ajustar)"
        echo "  5) $(t shr.remover)"
        echo "  6) $(t shr.padronizar)"
        echo "  7) $(t samba.pastas_pessoais)"
        echo ""
        echo "  0) $(t geral.voltar)"
        echo ""
        ler_opcao opcao
        case "$opcao" in
            "") continue ;;
            1)  debkit_shr_tela_listar ;;
            2)  debkit_shr_tela_criar ;;
            3)  debkit_shr_tela_trocar ;;
            4)  debkit_shr_tela_ajustar ;;
            5)  debkit_shr_tela_remover ;;
            6)  debkit_shr_tela_padronizar ;;
            7)  debkit_samba_tela_pastas_pessoais ;;
            0)  return 0 ;;
            *)  msg_erro "$(t geral.opcao_invalida "$opcao")"; pausar ;;
        esac
    done
}
