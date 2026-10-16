# CLAUDE.md

Regras de trabalho do debkit para o Claude Code. Decisões do projeto, fases
e situação atual: [`docs/PLANEJAMENTO.md`](docs/PLANEJAMENTO.md) (ler antes
de começar; a seção 11 diz onde paramos).

## Onde trabalhar

- Desenvolver e testar **só na VM Debian 13 de desenvolvimento** (com
  snapshot). **Nunca** rodar o `debkit` nem a suíte de testes num
  servidor de produção: a suíte cria usuários, grupos e unidades systemd de
  teste, e as provas reais (`DEBKIT_TESTE_REAL=1`) recarregam o SSH e mexem
  no ufw.
- Se houver dúvida se a máquina é a VM, perguntar antes de executar
  qualquer coisa.
- VM limpa de novo: `dev/vmnova.sh` (restaura o snapshot "limpa" e reinicia;
  exige tudo commitado e enviado) e, depois, `dev/vmprepara.sh` (ferramentas
  de desenvolvimento). O Samba quem instala é o `./debkit --preparar`.

## Repositório público: nada de dados reais

O repositório é **público** (github.com/ThiagoCarrere/debkit). Antes de
**todo** commit e push, revisar o diff procurando dados reais do ambiente:

- IPs, redes, interfaces, hostnames, domínios;
- nomes de usuários, grupos e compartilhamentos reais;
- trechos de `smb.conf`, `sshd_config`, `ip route`, `testparm`, `sshd -T`
  copiados de um servidor de verdade;
- senhas, chaves, tokens.

Ao usar a saída real de um comando como exemplo em teste ou documento, trocar
os valores por valores fictícios. (Já aconteceu: as redes reais de um
servidor entraram nos testes de firewall e o histórico precisou ser
reescrito e o repositório recriado.)

## Git

- Trabalho na branch `dev` (commit e push só na `dev`). A `main` é a versão
  pública estável: só recebe a `dev` (fast-forward) quando o Thiago pedir.
- Autor dos commits: Thiago Carrere; coautor: Claude.
- Forma de trabalho (uma tarefa por vez, revisão minuciosa, testes de
  verdade, só então commit): seção 9 do planejamento.
