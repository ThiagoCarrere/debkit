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
    DEBKIT_CONF_TIPO[SMB_CONF]="caminho"
    DEBKIT_CONF_TIPO[SMB_BACKUP_DIR]="caminho"
    DEBKIT_CONF_TIPO[HOMES_BASE]="caminho_opcional"
    DEBKIT_CONF_ORDEM+=(SMB_CONF SMB_BACKUP_DIR HOMES_BASE)
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
    [homes.aviso_depois]="Para a pasta aparecer no Windows, ajuste o compartilhamento [homes] em \"5) Pastas pessoais\" no menu do Samba."
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
    [homes.aviso_depois]="For the folder to show up in Windows, adjust the [homes] share in \"Home folders\" in the Samba menu."
)

# shellcheck disable=SC2034  # catálogo do núcleo
MSG_pt_BR+=(
    [samba.grupos]="Grupos: criar, membros e remover"
    [grp.titulo]="Grupos"
    [grp.listar]="Listar grupos"
    [grp.criar]="Criar grupo"
    [grp.membros]="Membros: colocar ou tirar usuários"
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
    [grp.r_principais]="Grupo principal de: %s (não podem sair)"
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
    [grp.nada_a_fazer]="Nenhum usuário para colocar ou tirar."
    [grp.e_principal]="'%s' tem %s como grupo principal: não entra nem sai por aqui."
    [grp.ja_membro]="'%s' já é membro de %s."
    [grp.nao_membro]="'%s' não é membro de %s."
    [grp.entrar_e_sair]="'%s' está para entrar e sair ao mesmo tempo."
    [grp.p_grupo]="Grupo (número; Enter cancela): "
    [grp.a_entrar]="Colocar usuários no grupo"
    [grp.a_sair]="Tirar usuários do grupo"
    [grp.p_acao]="Opção (Enter cancela): "
    [grp.p_usuarios]="Usuários (números separados por vírgula ou espaço; Enter cancela): "
    [grp.sem_candidatos_entrar]="Todos os usuários comuns já estão em %s."
    [grp.sem_candidatos_sair]="%s não tem membros que possam sair."
    [grp.p_confirmar_entrar]="Colocar %s no grupo %s?"
    [grp.p_confirmar_sair]="Tirar %s do grupo %s?"
    [grp.membros_ok]="Membros de %s atualizados."
    [grp.membros_falhou]="Não foi possível mudar os membros de %s: a lista anterior foi mantida."
    [grp.membros_desfazer_falhou]="ATENÇÃO: os membros de %s não ficaram como o esperado e a lista anterior não voltou: confira à mão."
    [ses.aviso]="Conectado(s) ao Samba agora: %s. Ao terminar, a conexão será refeita para os grupos valerem na hora (arquivo aberto sem salvar pode ser afetado)."
    [ses.reconectado]="%s: %d sessão(ões) do Samba reconectada(s); o acesso já vale com os grupos novos."
    [ses.falhou]="%s: não foi possível encerrar a sessão do Samba; o acesso só muda quando ele reconectar."
    [grp.remover_principal]="%s é o grupo principal de: %s. O debkit não remove esse grupo."
    [grp.aviso_membros]="%d membro(s) perdem o acesso dado por este grupo: %s"
    [grp.sem_membros]="O grupo não tem membros."
    [grp.aviso_usos]="O grupo é usado no %s, nos compartilhamentos: %s- essas regras passarão a apontar para um grupo que não existe."
    [grp.procurando]="Procurando arquivos do grupo (GID %s) na base das pastas pessoais e nos compartilhamentos..."
    [grp.aviso_arquivos]="%d arquivo(s)/pasta(s) pertencem ao grupo. Eles ficam com o número %s e um grupo criado depois pode receber o mesmo número e herdar o acesso."
    [grp.aviso_arquivos_muitos]="%d arquivo(s)/pasta(s) ou mais pertencem ao grupo. Eles ficam com o número %s e um grupo criado depois pode receber o mesmo número e herdar o acesso."
    [grp.sem_arquivos]="Nenhum arquivo do grupo encontrado na base das pastas pessoais nem nos compartilhamentos."
    [grp.p_confirmar_remover]="Para remover, digite o nome do grupo (%s); Enter cancela: "
    [grp.removido]="Grupo %s removido."
    [grp.remover_falhou]="Não foi possível remover o grupo %s."
)
# shellcheck disable=SC2034  # catálogo do núcleo
MSG_en+=(
    [samba.grupos]="Groups: create, members and remove"
    [grp.titulo]="Groups"
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
    [grp.aviso_usos]="The group is used in %s, in the shares: %s- those rules will point to a group that does not exist."
    [grp.procurando]="Looking for files of the group (GID %s) in the home folder base and in the shares..."
    [grp.aviso_arquivos]="%d file(s)/folder(s) belong to the group. They keep the number %s, and a group created later may get the same number and inherit the access."
    [grp.aviso_arquivos_muitos]="%d or more file(s)/folder(s) belong to the group. They keep the number %s, and a group created later may get the same number and inherit the access."
    [grp.sem_arquivos]="No files of the group found in the home folder base or in the shares."
    [grp.p_confirmar_remover]="To remove, type the group name (%s); Enter cancels: "
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

# Filtro: no [global], troca o valor da(s) linha(s) "unix password sync"
# por "no" (a primeira fica no lugar, as repetidas saem); se não houver a
# linha (valor vindo de outro lugar), põe logo depois do [global]
debkit_samba_filtro_sem_sync() {
    awk '
        /^[ \t]*\[/ { if (em && !feito) { print "   unix password sync = no"; feito = 1 }
                      em = (tolower($0) ~ /^[ \t]*\[global\][ \t]*$/); print; next }
        em && tolower($0) ~ /^[ \t]*unix[ \t]*password[ \t]*sync[ \t]*=/ {
            if (!feito) { match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) "unix password sync = no"; feito = 1 }
            next }
        { print }
        END { if (em && !feito) print "   unix password sync = no" }'
}

# Conferência: a configuração em vigor depois = antes sem a linha do sync
debkit_samba_conferir_sem_sync() {
    cmp -s <(grep -vxF $'\tunix password sync = Yes' "$1") "$2" && ! grep -qxF $'\tunix password sync = Yes' "$2"
}

debkit_acao_samba_sem_sync() {
    debkit_smbconf_editar debkit_samba_filtro_sem_sync debkit_samba_conferir_sem_sync || return 1
    [ "$(debkit_samba_param "unix password sync")" == "No" ]
}

debkit_desfazer_samba_sem_sync() { debkit_smbconf_restaurar; }

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
# Conta (até GRP_ARQUIVOS_MAX) os arquivos e pastas com o GID <gid> nas
# pastas de dados. Imprime o número.
debkit_grupo_contar_arquivos() {
    local gid="$1" p
    local -a pastas=()
    mapfile -t pastas < <(debkit_samba_pastas_dados)
    for p in "${pastas[@]}"; do
        find "$p" -xdev -group "$gid" -printf '.\n' 2>/dev/null
    done | head -n "$DEBKIT_GRP_ARQUIVOS_MAX" | wc -l
}

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

# Encerra as sessões abertas dos usuários (smbcontrol <pid> shutdown; se não
# adiantar, TERM no processo, só se for um smbd) e confere que acabaram.
# Retorna 1 se alguma sessão não foi encerrada.
debkit_samba_reconectar() {
    local u pid i vivos rc=0
    local -a pids=()
    for u in "$@"; do
        mapfile -t pids < <(debkit_samba_sessoes "$u")
        [ ${#pids[@]} -gt 0 ] || continue
        for pid in "${pids[@]}"; do
            smbcontrol -s "$DEBKIT_SMB_CONF" "$pid" shutdown >/dev/null 2>&1
        done
        for (( i = 0; i < 25; i++ )); do
            vivos=""
            for pid in "${pids[@]}"; do kill -0 "$pid" 2>/dev/null && vivos+=" $pid"; done
            [ -z "$vivos" ] && break
            [ "$i" -eq 10 ] && for pid in $vivos; do
                [[ "$(cat "/proc/$pid/comm" 2>/dev/null)" == smbd* ]] && kill -TERM "$pid" 2>/dev/null
            done
            sleep 0.2
        done
        if [ -n "$vivos" ]; then
            msg_aviso "$(t ses.falhou "$u")"
            debkit_auditar samba_reconectar "usuario=$u pids=$(IFS=,; echo "${pids[*]}") resultado=falha"
            rc=1
        else
            msg_info "$(t ses.reconectado "$u" "${#pids[@]}")"
            debkit_auditar samba_reconectar "usuario=$u pids=$(IFS=,; echo "${pids[*]}") resultado=ok"
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
# debkit_grupo_remover <grupo>: só grupo gerenciado e que não é o grupo
# principal de ninguém. Os avisos (membros, smb.conf, arquivos) e a
# confirmação ficam na tela.
debkit_grupo_remover() {
    local grupo="$1" gid principais membros
    local -a lista=()
    if ! debkit_grupo_gerenciado "$grupo"; then msg_erro "$(t grp.nao_gerenciado "$grupo")"; return 1; fi
    principais=$(debkit_grupo_principais "$grupo" | paste -sd, | sed 's/,/, /g')
    if [ -n "$principais" ]; then msg_erro "$(t grp.remover_principal "$grupo" "$principais")"; return 1; fi
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

# Tela: escolhe o grupo, mostra o que será perdido (membros, smb.conf,
# arquivos) e pede UMA confirmação digitando o nome do grupo
debkit_samba_tela_remover_grupo() {
    local grupo gid n resp rc
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
    mapfile -t membros < <(debkit_grupo_membros "$grupo")
    mapfile -t usos < <(debkit_samba_grupo_usos "$grupo")
    gid=$(getent group "$grupo" | cut -d: -f3)
    if [ ${#membros[@]} -gt 0 ]; then
        msg_aviso "$(t grp.aviso_membros "${#membros[@]}" "$(debkit_juntar "${membros[@]}")")"
    else
        msg_info "$(t grp.sem_membros)"
    fi
    debkit_aviso_conectados "${membros[@]}"
    if [ ${#usos[@]} -gt 0 ]; then
        msg_aviso "$(t grp.aviso_usos "$DEBKIT_SMB_CONF" "$(printf '[%s] ' "${usos[@]}")")"
    fi
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
    debkit_ler resp "$(t grp.p_confirmar_remover "$grupo")" || { msg_aviso "$(t usr.cancelado)"; return 1; }
    if [ "$resp" != "$grupo" ]; then msg_aviso "$(t usr.cancelado)"; pausar; return 1; fi
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
debkit_samba_menu() {
    local opcao
    while true; do
        titulo "$(t samba.titulo)"
        echo "  1) $(t samba.listar_usuarios)"
        echo "  2) $(t samba.criar_usuario)"
        echo "  3) $(t samba.trocar_senha)"
        echo "  4) $(t samba.criar_home)"
        echo "  5) $(t samba.pastas_pessoais)"
        echo "  6) $(t samba.grupos)"
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
            5)  debkit_samba_tela_pastas_pessoais ;;
            6)  debkit_samba_menu_grupos ;;
            0)  return 0 ;;
            *)  msg_erro "$(t geral.opcao_invalida "$opcao")"; pausar ;;
        esac
    done
}
