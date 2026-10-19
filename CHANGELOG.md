# Changelog

Todas as mudanças relevantes do debkit são registradas aqui.
Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [Não lançado]

### Alterado
- **Menu do Samba em submenus:** 1) Usuários (listar, criar, trocar senha,
  criar pasta pessoal), 2) Grupos (listar, criar, membros, remover) e
  3) Compartilhamentos (por enquanto, pastas pessoais e `[homes]`).
- **Reestruturação (tarefa 1.0):** o `debkit.sh` virou o ponto de entrada
  `debkit` + o núcleo `lib/nucleo.sh` + o módulo `modulos/samba.sh`. Rodar
  com `./debkit` (ou pelo link `/usr/local/sbin/debkit`, quando instalado).
  O menu principal lista os módulos ("1) Samba", por enquanto em
  construção); o título passa a ser "debkit - administração de servidores
  Debian".
- O debkit não usa mais um arquivo próprio de compartilhamentos incluído no
  `smb.conf`: as chaves `SHARES_CONF` e `PREFIXO_GRUPO` saíram (no
  `debkit.conf` viram um aviso "não é mais usada", sem impedir o uso, e a
  preparação oferece tirar essas linhas - com backup, sem mexer no resto
  do arquivo e conferindo que nenhum outro valor muda), a
  preparação não cria mais o `debkit-shares.conf` nem a linha `include`, e
  em servidores já preparados ela oferece remover essa linha (só se o
  arquivo não tem compartilhamentos; conferindo com o `testparm` que nada
  mais muda no Samba) e o arquivo antigo vazio.
- Backups com o nome `<arquivo>.dd-mm-aaaa-hh-mm-ss` (sufixo `-2`, `-3`...
  no mesmo segundo); a rotação ordena pela data do nome e só apaga arquivos
  com esse padrão. Ao desfazer a proteção SSH, o arquivo volta com 644 (o
  backup é 600).

### Corrigido
- **Segurança:** a preparação instalava o Samba com os pacotes
  "recomendados" do apt, que trazem o `samba-ad-dc` e o `winbind`; o
  `pam_winbind` entrava no PAM e aceitava a senha do Samba na autenticação
  de logins como o SSH. Agora instala com `--no-install-recommends` e, num
  servidor independente, a verificação detecta `samba-ad-dc`, `winbind`,
  `libpam-winbind` e `libnss-winbind` e a preparação oferece removê-los
  (simulação antes, recusa se o apt quiser remover mais; conferência do
  PAM, do NSS e do Samba depois).
- Testes: a caixa de areia agora isola o apt e a base do dpkg (um teste
  chegou a remover pacotes reais) e a impressão digital confere pacotes,
  PAM e `nsswitch.conf`.
- Validação de nomes e caminhos do `debkit.conf` aceitava letras
  acentuadas (no bash, `[a-z]` em pt_BR casa com "ã", "é"...).
- A mensagem de falha ao ativar o serviço do Samba mostrava
  "veja: systemctl status " sem o nome do serviço.
- Projeto renomeado de **gsb** para **debkit** (kit de módulos para Debian;
  o gerenciador Samba vira o módulo `samba`): arquivos, variáveis `DEBKIT_*`,
  funções `debkit_*`, grupo `debkit_usuarios`, `/etc/debkit`, testes.
- Planejamento revisado (docs/PLANEJAMENTO.md): o debkit passa a gerenciar
  todos os usuários/grupos/compartilhamentos comuns; tipos de conta; senha
  Linux bloqueada por padrão; home opcional no disco de dados; remoção
  completa; backups do `smb.conf` em `/etc/samba/conf-bkp/` com rotação.
- Testes: passam também num servidor já preparado pelo debkit. A
  conferência "nada fora da caixa de areia" agora exige que os arquivos
  reais do debkit não mudem (antes exigia que não existissem), e o `t03`
  procura o `include` pelo caminho exato da areia.

### Adicionado
- **Verificar e corrigir contas** (Samba → Usuários → 6): lista e corrige,
  uma a uma com s/n, conta só no Samba (apaga a órfã), usuário só no Linux
  (cria a conta Samba), shell sem login fora do grupo de proteção (põe no
  grupo: o SSH passa a recusar) e usuário de arquivos com senha do Linux
  utilizável (bloqueia).
- **Excluir usuário** (Samba → Usuários → 5): apaga do Linux, do Samba e
  a pasta pessoal (só se for da base das pastas pessoais ou de `/home`, do
  próprio usuário), com uma confirmação s/n depois de mostrar o que será
  perdido. Encerra as sessões do Samba; recusa administradores, quem roda
  o debkit, usuário com processos fora do Samba (ex.: SSH aberto) e grupo
  pessoal usado no `smb.conf`. Avisa os arquivos que ficam nos
  compartilhamentos (UID pode ser reaproveitado) e as citações do login no
  `smb.conf`.
- **Grupos** (menu Samba, opção 6): listar (GID, membros, grupo principal
  e uso no Samba), criar (nome com as regras do login, sem reservados,
  `debkit*`, nomes já usados ou citados no sudoers; membros na criação;
  tudo ou nada), adicionar e remover membros (lista trocada de uma vez com
  `gpasswd -M` e conferida; se não conferir, volta a anterior) e remover
  (recusa grupo principal de alguém; avisa os membros, o uso no `smb.conf`
  e os arquivos do grupo nas pastas de dados; confirmação s/n). Ficam de fora os grupos de sistema, os pessoais, o
  `debkit_usuarios` e os citados no sudoers (entrar neles daria sudo).
  Efeito na hora: as sessões abertas no Samba só dos usuários afetados são
  refeitas (o Windows reconecta sozinho, já com os grupos novos), com
  aviso antes da confirmação. Prova real com sessão aberta.
- **Trocar senha** (menu Samba, opção 3; as opções seguintes passaram a 4
  e 5): usuário de arquivos só a do Samba (a do Linux continua bloqueada e
  é conferida); com acesso ao servidor: Samba, Linux ou as duas, tudo ou
  nada (a do Linux volta se o Samba falhar); admin: só a do Samba. Senha
  sempre pela entrada padrão; auditoria sem senha.
- Preparação: desliga o `unix password sync` do smb.conf (com ele, trocar
  a senha pelo Windows definia a senha do Linux), pela edição segura com
  conferência de que só essa linha muda.
- **Listar usuários** (menu Samba, opção 1; as demais opções passaram a 2-4):
  só contas comuns, com nome completo, tipo (arquivos, servidor, admin =
  membro do sudo, nologin fora do grupo de proteção), estado no Samba
  (ativa, desativada, sem conta, só no Samba), pasta pessoal e grupos
  comuns; total por tipo e alertas de consistência e de segurança (shell
  sem login fora do grupo de proteção ainda permite túnel SSH). Colunas
  alinhadas mesmo com acentos.
- Scripts da VM de desenvolvimento: `dev/vmnova.sh` (volta ao snapshot
  "limpa" do Timeshift e reinicia; só em máquina virtual, com repositório
  commitado, enviado e fora dos snapshots; confirmação digitando RESTAURAR;
  `--simular`) e `dev/vmprepara.sh` (instala as ferramentas de
  desenvolvimento sem os recomendados e confere o ufw inativo). Testes em
  `tests/t10_dev.sh` com Timeshift e apt falsos.
- **Pasta pessoal (tarefa 1.1b):** opcional na criação do usuário (padrão:
  não) e para usuário existente sem pasta (menu Samba, opção 2). A base
  (`HOMES_BASE`) é escolhida na primeira vez entre os discos de dados
  montados e gravada no `debkit.conf` (`debkit_conf_definir`: backup, só a
  chave muda, troca atômica); recusa disco do sistema, pastas do sistema,
  links, tmpfs, sistemas sem dono/permissões e montagem somente leitura, e
  é conferida a cada uso (disco desmontado = nada é criado). Pasta
  `HOMES_BASE/<login>` 700 do usuário (com `/etc/skel` só para acesso ao
  servidor), desfeita se algo falhar. Compartilhamento `[homes]`: o debkit
  oferece liberar a escrita do `[homes]` do Debian (somente leitura) ou
  criar a seção, com conferência do que muda; opção 3 do menu Samba mostra
  a base e o estado do `[homes]`.
- **Criar usuário (tarefa 1.1):** menu "1) Samba" → "1) Criar usuário".
  Nome completo opcional (com acentos) e sugestão de login a partir dele;
  login no padrão `nome_sobrenome` (minúsculas sem acento, números e `_`,
  2 a 32 caracteres; recusa reservados e o que já existe no Linux/Samba);
  tipo "usuário de arquivos" (padrão: só Samba, shell `nologin`, senha
  Linux bloqueada, grupo de proteção SSH) ou "usuário com acesso ao
  servidor" (confirmação explícita, `/bin/bash`, senha Linux igual ou
  própria); grupos comuns (sem os de sistema e os pessoais); senha sem
  eco, repetida, com `SENHA_MIN`, sempre pela entrada padrão; resumo e UMA
  confirmação; conferência do resultado real e desfazer completo se algo
  falhar; auditoria sem senhas. Só com o ambiente preparado. Sem pasta
  pessoal por enquanto (tarefa 1.1b).
- Comandos do Samba (`smbpasswd`, `pdbedit`) sempre com o `SMB_CONF` do
  debkit; a base `tdbsam:<arquivo>` também é aceita na verificação.
- Carregamento seguro dos arquivos do programa: núcleo, módulos e suas
  pastas só são carregados se pertencem ao root (ou a quem executa), sem
  escrita para grupo/outros e sem links.
- Registro de módulos com ganchos (verificação, plano de preparação, menu):
  um módulo novo entra só colocando o arquivo em `modulos/`.
- Faixas das contas comuns lidas do `/etc/login.defs` (`UID_MIN`/`UID_MAX`,
  `GID_MIN`/`GID_MAX`, sem executar o arquivo; padrão do Debian se ausente
  ou inválido, com aviso), mostradas na verificação; UID/GID 0 nunca conta.
- Módulo samba: backups do `smb.conf` em `SMB_BACKUP_DIR`
  (`/etc/samba/conf-bkp`, criada com 700) e edição segura do `smb.conf`
  (backup, arquivo novo em temporário, `testparm`, conferência do que mudou
  na configuração em vigor, troca atômica mantendo dono/permissões, reload e
  restauração se falhar).
- Testes da tarefa 1.0 (`tests/t06_estrutura.sh`); a caixa de areia copia o
  `smb.conf` real sem o `include` antigo e isola também `SMB_BACKUP_DIR`.
- **Firewall (tarefa 0.5):** grupo "Firewall" na verificação. Com ufw ou
  firewalld ativo que não libera o Samba, o plano de preparação oferece
  liberar só a porta 445/tcp (NetBIOS 137-139 fica fechado) e só para as
  redes locais do servidor (rotas "scope link", inclusive vindas do DHCP;
  sem docker/bridges/link-local), uma regra por rede com o comentário
  "debkit: Samba", conferindo depois e desfazendo exatamente as regras criadas
  se algo falhar. Reconhece liberações já existentes (política allow, 445
  sozinha/em lista, perfil Samba, serviço samba do firewalld). Regras
  próprias de nftables/iptables: só aviso.
- **Proteção SSH (tarefa 0.4):** item do plano de preparação que cria
  `/etc/ssh/sshd_config.d/debkit.conf` com `DenyGroups debkit_usuarios` (com
  marca de autoria; nunca sobrescreve arquivo alheio), valida com
  `sshd -t` ANTES de recarregar, recarrega sem derrubar sessões e confirma
  no `sshd -T` que a regra vale para todos. Recusa aplicar se quem roda o
  debkit estiver no grupo. Detecta `Include` depois de bloco `Match` (que
  deixaria a proteção ineficaz) e mostra o estado da proteção. Desfazer
  mexe só no que a operação fez. Função de remoção (para a desinstalação).
- Testes: trava em `tests/run.sh` que compara uma "impressão digital" do
  sistema real antes e depois de cada arquivo de teste; prova com login
  real em `tests/t04b_ssh_real.sh` (só com `DEBKIT_TESTE_REAL=1`).
- **Preparação do ambiente (tarefa 0.3):** `debkit --preparar`, menu
  "9) Ambiente: verificar e preparar" e assistente ao abrir o menu.
  Monta um plano só com o que falta (instalar pacotes via apt-get com
  espera pelo apt e mantendo configurações existentes; ligar o Samba;
  criar `/etc/debkit/debkit.conf`, backups 700, log 640, grupo de sistema
  `debkit_usuarios`, `debkit-shares.conf` e a linha `include` no `smb.conf`),
  pede UMA confirmação, confere cada passo e, se algo falhar, desfaz o que
  é do debkit (pacotes e serviço são mantidos e isso é informado). Bloqueios
  que o debkit não resolve sozinho são explicados. Rotina de backups com
  limpeza das cópias antigas. Auditoria do plano e de cada ação.
- **Detecção do ambiente (tarefa 0.2):** `debkit --verificar` e menu
  "9) Ambiente", somente leitura. Verifica sistema (os-release lido sem
  executar), systemd, 22 dependências essenciais (tabela única por
  distribuição, com o pacote Debian de cada uma), Samba (serviço,
  `smb.conf` válido, modo efetivo - recusa controlador de domínio - e base
  `tdbsam`), SSH (serviço, se o `sshd_config` inclui o arquivo do debkit,
  login por senha) e ferramentas de desenvolvimento. Calcula os pacotes que
  faltam, sem repetição.
- **Esqueleto do debkit.sh (tarefa 0.1):** configuração em `/etc/debkit/debkit.conf`
  lida com segurança (não executada, chaves e valores validados, recusa
  arquivo com permissão insegura), catálogo de mensagens pt_BR/en, menu,
  trava contra execução simultânea, log de auditoria (início/fim de sessão
  com o motivo), limpeza de temporários e `--ajuda`/`--versao`.
- `debkit.conf.exemplo` comentado.
- Testes automáticos em `tests/` (`tests/run.sh`), em caixa de areia.
- Planejamento do projeto (`docs/PLANEJAMENTO.md`), README inicial e
  licença MIT.
- Planejamento: preparação inteligente do ambiente (dependências,
  assistente de primeira execução, desinstalação).
