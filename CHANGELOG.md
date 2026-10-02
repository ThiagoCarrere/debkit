# Changelog

Todas as mudanças relevantes do gsb são registradas aqui.
Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [Não lançado]

### Adicionado
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
