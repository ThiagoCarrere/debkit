# Changelog

Todas as mudanças relevantes do gsb são registradas aqui.
Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [Não lançado]

### Adicionado
- **Firewall (tarefa 0.5):** grupo "Firewall" na verificação. Com ufw ou
  firewalld ativo que não libera o Samba, o plano de preparação oferece
  liberar só a porta 445/tcp (NetBIOS 137-139 fica fechado) e só para as
  redes locais do servidor (rotas "scope link", inclusive vindas do DHCP;
  sem docker/bridges/link-local), uma regra por rede com o comentário
  "gsb: Samba", conferindo depois e desfazendo exatamente as regras criadas
  se algo falhar. Reconhece liberações já existentes (política allow, 445
  sozinha/em lista, perfil Samba, serviço samba do firewalld). Regras
  próprias de nftables/iptables: só aviso.
- **Proteção SSH (tarefa 0.4):** item do plano de preparação que cria
  `/etc/ssh/sshd_config.d/gsb.conf` com `DenyGroups gsb_usuarios` (com
  marca de autoria; nunca sobrescreve arquivo alheio), valida com
  `sshd -t` ANTES de recarregar, recarrega sem derrubar sessões e confirma
  no `sshd -T` que a regra vale para todos. Recusa aplicar se quem roda o
  gsb estiver no grupo. Detecta `Include` depois de bloco `Match` (que
  deixaria a proteção ineficaz) e mostra o estado da proteção. Desfazer
  mexe só no que a operação fez. Função de remoção (para a desinstalação).
- Testes: trava em `tests/run.sh` que compara uma "impressão digital" do
  sistema real antes e depois de cada arquivo de teste; prova com login
  real em `tests/t04b_ssh_real.sh` (só com `GSB_TESTE_REAL=1`).
- **Preparação do ambiente (tarefa 0.3):** `gsb --preparar`, menu
  "9) Ambiente: verificar e preparar" e assistente ao abrir o menu.
  Monta um plano só com o que falta (instalar pacotes via apt-get com
  espera pelo apt e mantendo configurações existentes; ligar o Samba;
  criar `/etc/gsb/gsb.conf`, backups 700, log 640, grupo de sistema
  `gsb_usuarios`, `gsb-shares.conf` e a linha `include` no `smb.conf`),
  pede UMA confirmação, confere cada passo e, se algo falhar, desfaz o que
  é do gsb (pacotes e serviço são mantidos e isso é informado). Bloqueios
  que o gsb não resolve sozinho são explicados. Rotina de backups com
  limpeza das cópias antigas. Auditoria do plano e de cada ação.
- **Detecção do ambiente (tarefa 0.2):** `gsb --verificar` e menu
  "9) Ambiente", somente leitura. Verifica sistema (os-release lido sem
  executar), systemd, 22 dependências essenciais (tabela única por
  distribuição, com o pacote Debian de cada uma), Samba (serviço,
  `smb.conf` válido, modo efetivo - recusa controlador de domínio - e base
  `tdbsam`), SSH (serviço, se o `sshd_config` inclui o arquivo do gsb,
  login por senha) e ferramentas de desenvolvimento. Calcula os pacotes que
  faltam, sem repetição.
- **Esqueleto do gsb.sh (tarefa 0.1):** configuração em `/etc/gsb/gsb.conf`
  lida com segurança (não executada, chaves e valores validados, recusa
  arquivo com permissão insegura), catálogo de mensagens pt_BR/en, menu,
  trava contra execução simultânea, log de auditoria (início/fim de sessão
  com o motivo), limpeza de temporários e `--ajuda`/`--versao`.
- `gsb.conf.exemplo` comentado.
- Testes automáticos em `tests/` (`tests/run.sh`), em caixa de areia.
- Planejamento do projeto (`docs/PLANEJAMENTO.md`), README inicial e
  licença MIT.
- Planejamento: preparação inteligente do ambiente (dependências,
  assistente de primeira execução, desinstalação).
