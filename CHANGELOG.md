# Changelog

Todas as mudanças relevantes do gsb são registradas aqui.
Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [Não lançado]

### Adicionado
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
