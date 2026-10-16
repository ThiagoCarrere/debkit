# debkit

Kit de **módulos de administração para servidores Debian**, com foco em
segurança, por menu interativo (e, em breve, por comandos diretos).

Primeiro módulo, **samba**: usuários, grupos, compartilhamentos, permissões
e pastas pessoais de um **servidor de arquivos Samba**.

> **Status:** em desenvolvimento — ainda não usar em produção.
> Fundação (Fase 0) concluída: verificação e preparação do ambiente, proteção
> SSH e firewall. Fase 1 (usuários e grupos) em andamento: estrutura em
> núcleo + módulos, criação de usuários e pastas pessoais prontas;
> próximo: listar usuários.
> O planejamento está em [`docs/PLANEJAMENTO.md`](docs/PLANEJAMENTO.md).

## Destaques planejados

- Usuários de servidor de arquivos **sem acesso ao servidor**: senha só no
  Samba, senha Linux bloqueada, shell `nologin` e bloqueio SSH gerenciado
  pelo próprio debkit. Acesso ao servidor só quando um administrador libera.
- Gerencia **todos** os usuários, grupos e compartilhamentos comuns, e
  **nunca** os do sistema (que nem aparecem nas listas).
- Pastas pessoais opcionais no disco de dados (backup junto com o resto).
- Toda operação valida antes, pede uma confirmação e **desfaz** se algo
  falhar; backups automáticos com rotação e log de auditoria.

## Uso (desenvolvimento)

```
sudo ./debkit --verificar   # verifica o ambiente, sem alterar nada
sudo ./debkit --preparar    # prepara o servidor (mostra o plano e pede confirmação)
sudo ./debkit               # menu
```

Os arquivos do programa precisam pertencer ao root e não ter escrita para
grupo/outros (o debkit roda como root e se recusa a carregar código que
outra pessoa possa alterar).

Estrutura: `debkit` (ponto de entrada), `lib/nucleo.sh` (núcleo comum) e
`modulos/*.sh` (um arquivo por módulo; primeiro: `samba.sh`).

## VM de desenvolvimento

Dois scripts em `dev/` (só para a VM de desenvolvimento; recusam máquina
que não é virtual):

```
sudo dev/vmnova.sh --simular   # mostra o snapshot e o comando, sem fazer nada
sudo dev/vmnova.sh             # volta ao snapshot "limpa" do Timeshift e REINICIA
sudo dev/vmprepara.sh          # depois: instala shellcheck, smbclient e ufw (inativo)
```

O `vmnova.sh` recusa se o repositório tiver mudança sem commit, commit sem
push ou estiver fora das exclusões do Timeshift, e pede para digitar
`RESTAURAR`. O `vmprepara.sh` não instala o Samba: preparar o servidor é
trabalho do próprio `./debkit --preparar`.

## Compatibilidade

Foco em **Debian 12/13**. Ubuntu, derivado do Debian, tende a funcionar.

## Autores

Desenvolvido por **Thiago Carrere** em parceria com **Claude** (Anthropic).

## Licença

[MIT](LICENSE)
