# gsb — Gerenciador Samba

Gerenciador de **servidor de arquivos Samba** para Linux, com foco em
segurança: usuários, grupos, compartilhamentos e permissões por um menu
interativo (e, em breve, por comandos diretos).

> **Status:** em desenvolvimento — ainda não usar em produção.
> Fundação (Fase 0) concluída: verificação e preparação do ambiente, proteção
> SSH e firewall. Próximo: gerenciamento de usuários (Fase 1).
> O planejamento está em [`docs/PLANEJAMENTO.md`](docs/PLANEJAMENTO.md).

## Destaques planejados

- Usuários de servidor de arquivos com a **mesma senha no Linux e no
  Samba**, sem acesso ao servidor (shell `nologin` + bloqueio SSH gerenciado
  pelo próprio gsb).
- **Só gerencia o que ele cria**: nunca altera usuários, grupos ou
  compartilhamentos que já existiam no servidor.
- Toda operação valida antes, pede uma confirmação e **desfaz** se algo
  falhar; backups automáticos e log de auditoria.

## Compatibilidade

Foco em **Debian 12/13**. Ubuntu, derivado do Debian, tende a funcionar.

## Autores

Desenvolvido por **Thiago Carrere** em parceria com **Claude** (Anthropic).

## Licença

[MIT](LICENSE)
