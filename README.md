<div align="center">

# debkit

**Administração segura de servidores Debian, por menu ou por comandos — começando por um servidor de arquivos Samba.**

🇧🇷 Português · 🇬🇧 [English](README.en.md)

![Debian 12/13](https://img.shields.io/badge/Debian-12%20%7C%2013-A81D33?logo=debian&logoColor=white)
![Bash](https://img.shields.io/badge/feito%20em-Bash-4EAA25?logo=gnubash&logoColor=white)
![Samba](https://img.shields.io/badge/Samba-standalone%20%2B%20tdbsam-1E73BE)
![Licença MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-blue)
[![CI](https://github.com/ThiagoCarrere/debkit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ThiagoCarrere/debkit/actions/workflows/ci.yml)

</div>

---

O **debkit** é um kit de módulos de administração para servidores Debian.
Você escolhe o que quer fazer num menu e ele cuida do resto: valida antes,
mostra o que vai acontecer, pede **uma** confirmação, confere o resultado
e **desfaz** se algo der errado no meio.

O primeiro módulo, **samba**, gerencia um servidor de arquivos completo:
usuários, grupos, pastas pessoais, compartilhamentos e permissões.

> [!NOTE]
> Fases 0 a 4 concluídas (veja o [roteiro](#roteiro)). Como em qualquer
> ferramenta que mexe no servidor, teste antes numa máquina virtual.

## Por que o debkit

Num servidor de arquivos, quase todo usuário só precisa abrir pastas pelo
Windows — e não deveria conseguir entrar no servidor. Fazer isso direito à
mão dá trabalho e é fácil esquecer um detalhe. O debkit faz por padrão:

| | Usuário de arquivos (padrão) | Usuário com acesso ao servidor |
|---|---|---|
| Pastas pelo Samba | ✅ | ✅ |
| Senha do Linux | 🔒 bloqueada | própria |
| Shell | `nologin` | `/bin/bash` |
| SSH (inclusive túneis) | ❌ recusado pelo debkit | ✅ liberado por um administrador |

## Destaques

- 🛡️ **Seguro por padrão** — senhas nunca aparecem na tela, no log ou na
  linha de comando; usuários e grupos **do sistema nunca são tocados** (nem
  aparecem nas listas); o próprio debkit se recusa a carregar código que
  outra pessoa possa alterar.
- ↩️ **Tudo ou nada** — cada operação confere o resultado real e, se algo
  falhar no meio, desfaz o que já tinha feito. Nada fica pela metade.
- ⚡ **Efeito na hora** — adicionou alguém a um grupo? A pasta já abre.
  Removeu? O acesso some na hora, inclusive de quem estava conectado (o
  debkit refaz só a sessão dessa pessoa; o Windows reconecta sozinho).
- 🧰 **Prepara o servidor sozinho** — instala o que falta, desliga o que
  atrapalha (pacotes de domínio, sincronização de senha pelo Windows),
  aplica o bloqueio SSH e, se o ufw ou o firewalld estiver bloqueando o
  Samba, libera só a porta 445 e só para as redes locais. Sempre mostrando
  o plano antes.
- 💾 **Rastreável** — backup automático (com rotação) antes de qualquer
  alteração e log de auditoria: quem fez o quê e quando.
- ⌨️ **Menu ou comandos** — tudo o que o menu faz também existe como
  comando direto, para scripts e cron, com as mesmas validações e
  confirmações (`--sim` responde por você).
- 🌐 **Português e inglês** — fala a língua do sistema.
- 🔍 **Avisa o que você não veria** — ao remover um grupo ou excluir um
  usuário, mostra quem perde acesso, onde ele é usado no `smb.conf` e
  quantos arquivos ficam no disco (o número do usuário/grupo pode ser
  reaproveitado e herdar esses arquivos).

## Como é

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  debkit - administração de servidores Debian  v0.1.0-dev
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  1) Samba: usuários, grupos e compartilhamentos

  9) Ambiente: verificar e preparar
  0) Sair
```

```
Samba
├── 1) Usuários
│     ├── Listar usuários
│     ├── Criar usuário (com pasta pessoal opcional)
│     ├── Trocar senha
│     ├── Criar pasta pessoal para um usuário existente
│     ├── Excluir usuário
│     └── Verificar e corrigir contas (Linux x Samba)
├── 2) Grupos
│     ├── Listar grupos
│     ├── Criar grupo
│     ├── Membros: adicionar ou remover usuários
│     └── Remover grupo
├── 3) Compartilhamentos
│     ├── Listar compartilhamentos
│     ├── Criar compartilhamento (vinculado a um grupo)
│     ├── Trocar o grupo de um compartilhamento
│     ├── Ajustar as permissões do conteúdo
│     ├── Remover compartilhamento (os arquivos ficam)
│     ├── Trazer um compartilhamento feito à mão para o padrão
│     └── Pastas pessoais: base e compartilhamento [homes]
└── 4) Diagnóstico
      ├── Sessões ativas: quem está conectado; desconectar uma sessão
      ├── Logins: falhas dos últimos 7 dias e último login de cada usuário
      ├── Saúde do Samba: relatório (serviço, porta, disco, alertas, atividade)
      └── Auditoria: o que foi feito, por período, afetado e tipo
```

Listar usuários (exemplo com dados fictícios):

```
  Login         Nome completo             Tipo      Samba   Pasta pessoal         Grupos
  maria_souza   Maria Souza - Financeiro  arquivos  ativa   /dados/homes/maria…   financeiro
  pedro_alves   Pedro Alves - TI          servidor  ativa   —                     ti, suporte
  rafael_dias   Rafael Dias               arquivos  ativa   —                     suporte

  3 usuário(s): 2 de arquivos, 1 com acesso ao servidor, 0 admin, 0 outro(s).
```

## O que já faz

| Área | Funções |
|---|---|
| **Ambiente** | verificação completa (sistema, Samba, SSH, firewall) e preparação guiada, com plano e confirmação; log de autenticação do Samba (logins com e sem sucesso) com rotação |
| **Proteção SSH** | arquivo próprio em `sshd_config.d` (o `sshd_config` não é tocado), validado antes de recarregar, sem derrubar sessões |
| **Usuários** | criar (dois tipos de conta, nome completo, grupos, pasta pessoal), listar, trocar senha, excluir, verificar e corrigir contas |
| **Grupos** | criar, listar, adicionar/remover membros com efeito imediato, remover |
| **Pastas pessoais** | no disco de dados (backup junto com o resto), na criação ou depois, e o compartilhamento `[homes]` |
| **Diagnóstico** | sessões ativas (quem está conectado, de qual máquina, arquivos abertos) e desconectar uma sessão; logins (falhas com o motivo e último login de cada usuário); relatório de saúde (serviço, porta, disco, alertas); consulta à auditoria (por período, afetado e tipo) |
| **Comandos diretos** | todas as ações do menu por linha de comando (`debkit samba <grupo> <ação>`), senhas pela entrada padrão, saída 0/1/2 para scripts |
| **Instalação** | `install.sh` (instala, atualiza trocando a pasta de uma vez só se a nova funcionar) e `debkit --desinstalar` (usuários e compartilhamentos ficam) |
| **Compartilhamentos** | listar (inclusive os feitos à mão, com alertas), criar vinculado a um grupo, cujos membros têm acesso total (pasta em `/mnt` ou `/srv`), trocar o grupo, ajustar as permissões do conteúdo, remover (os arquivos ficam no disco) e trazer os feitos à mão para o padrão |

## Instalação

```bash
git clone https://github.com/ThiagoCarrere/debkit.git
cd debkit
sudo ./install.sh        # instala em /opt/debkit e cria o comando "debkit"
sudo debkit              # menu: na primeira vez, prepara o servidor
```

O instalador copia só o programa para `/opt/debkit` (dono root, sem
escrita para grupo/outros: o debkit se recusa a carregar código que outra
pessoa possa alterar), cria o comando `/usr/local/sbin/debkit` e oferece
preparar o servidor. Se você clonar direto em `/opt/debkit`, ele só cria o
comando. A configuração fica em `/etc/debkit/debkit.conf` (modelo comentado
em [`debkit.conf.exemplo`](debkit.conf.exemplo)).

- **Atualizar:** `git pull` e `sudo ./install.sh` de novo (a versão nova só
  entra no lugar se funcionar).
- **Verificar sem alterar nada:** `sudo debkit --verificar`.
- **Desinstalar:** `sudo debkit --desinstalar` tira o programa e o comando;
  com `--tudo`, também a configuração, o log e os backups. Usuários, grupos,
  compartilhamentos e o `smb.conf` ficam, e a proteção SSH só sai se não
  houver usuários de arquivos.

## Comandos diretos

As mesmas ações do menu, para scripts e cron (lista completa:
`debkit samba --ajuda`):

```bash
sudo debkit samba usuario listar
printf '%s\n' "$SENHA" | sudo debkit samba usuario criar ana --nome "Ana Souza" --grupos financeiro --sim
sudo debkit samba grupo membros financeiro --adicionar pedro --sim
sudo debkit samba compartilhamento criar financeiro --grupo financeiro --sim
sudo debkit samba diagnostico saude          # sai com 1 se houver problema
sudo debkit samba diagnostico auditoria --dias 7 --tipo usuarios
```

Senhas nunca vão na linha de comando: são perguntadas (sem eco) ou lidas da
entrada padrão. Sem `--sim`, o comando mostra o resumo e pergunta, como no
menu. Saída: 0 certo, 1 recusado/cancelado/falhou, 2 uso incorreto.

## Idioma

Português ou inglês, pelo idioma do sistema (`LANG`/`LANGUAGE`). Para
fixar: `IDIOMA=pt_BR` ou `IDIOMA=en` no `debkit.conf`. Os comandos aceitam
os nomes nas duas línguas (`debkit samba user create ...`).

## Qualidade

- **Mais de 2.600 verificações automáticas** num sandbox: log,
  configuração, `smb.conf`, base de senhas do Samba e pacotes ficam
  isolados. Uma trava compara o sistema real antes e depois de cada
  arquivo de teste e reprova qualquer vazamento.
- **Provas reais** (`DEBKIT_TESTE_REAL=1`; mais de 450 verificações), com
  Samba, SSH e ufw de verdade: login, túnel SSH recusado, acesso por
  grupo, sessão aberta perdendo o acesso na hora.
- **CI a cada push:** num Debian 13 novo (container com systemd), o próprio
  debkit prepara o servidor (instala o Samba), a suíte inteira roda e o
  debkit é instalado, usado e desinstalado de verdade.
- `shellcheck` sem avisos.

```bash
sudo tests/run.sh                                        # suíte normal
sudo DEBKIT_TESTE_REAL=1 tests/run.sh t13b_grupos_real.sh   # uma prova real
```

## Roteiro

| Fase | Conteúdo | |
|---|---|---|
| 0. Fundação | detecção e preparação do ambiente, backups, proteção SSH, firewall | ✅ |
| 1. Usuários e grupos | usuários, pastas pessoais, grupos, consistência Linux x Samba | ✅ |
| 2. Compartilhamentos | criar, listar, permissões de pasta, remover, os já existentes | ✅ |
| 3. Diagnóstico | falhas de login, sessões ativas, saúde do Samba, auditoria | ✅ |
| 4. Publicação | CI, rotação do log, comandos diretos, instalador e desinstalação, português e inglês | ✅ |

As decisões e o porquê de cada uma estão no
[planejamento](docs/PLANEJAMENTO.md); as mudanças, no
[CHANGELOG](CHANGELOG.md).

## Desenvolvimento

Tudo é escrito e testado numa VM Debian 13 com snapshot. Scripts em
[`dev/`](dev/) (os da VM recusam máquina que não é virtual):

```bash
sudo dev/vmnova.sh --simular   # mostra o snapshot e o comando, sem fazer nada
sudo dev/vmnova.sh             # volta ao snapshot "limpa" do Timeshift e REINICIA
sudo dev/vmprepara.sh          # depois: instala shellcheck, smbclient e ufw (inativo)
sudo dev/ci.sh                 # a suíte num Debian 13 novo, em container (como o CI)
```

Estrutura: `debkit` (ponto de entrada), `lib/nucleo.sh` (núcleo comum) e
`modulos/*.sh` (um arquivo por módulo; novos módulos entram só colocando o
arquivo na pasta).

## Compatibilidade

Feito para **Debian 12 e 13**. Ubuntu, derivado do Debian, tende a
funcionar. Samba em modo **servidor independente** (*standalone*, base
`tdbsam`); controlador de domínio (AD DC) não é suportado.

## Autores

Desenvolvido por **Thiago Carrere** em parceria com **Claude** (Anthropic).

## Licença

[MIT](LICENSE)
