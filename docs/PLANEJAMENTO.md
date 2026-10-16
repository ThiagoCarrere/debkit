# debkit — planejamento

Documento vivo com as decisões do projeto e o porquê de cada uma.
Iniciado em 02/10/2026 por Thiago Carrere e Claude (Anthropic) com o nome
provisório "gsb" (Gerenciador Samba); renomeado para **debkit** em
15/10/2026.

---

## 1. O que é (e o que não é)

**debkit** é um kit de **módulos de administração para servidores Debian**,
com menu interativo (e, depois, comandos diretos). Um núcleo comum
(configuração, mensagens, detecção e preparação do ambiente, proteção SSH,
firewall, log, backups, testes) atende todos os módulos.

**Primeiro módulo: `samba`** (arquivo `samba.sh`) — gerenciamento de
**usuários, grupos e servidor de arquivos Samba** (modo *standalone*, base de
senhas `tdbsam`): usuários Linux + Samba, grupos, compartilhamentos,
permissões de pasta, pastas pessoais e diagnóstico. Módulos futuros
(ex.: `wireguard`) entram sem mexer nos existentes.

**Não é** um controlador de domínio (Active Directory / Samba AD DC). Esse é
outro tipo de servidor; misturar os dois deixaria o debkit frágil.

## 2. Princípios (valem para todas as funções)

1. **Seguro por padrão** — nunca mexe em usuários/grupos de sistema nem em
   pastas do sistema; senha nunca aparece na tela, em log ou na linha de
   comando (vai sempre pela entrada padrão).
2. **Tudo ou nada** — cada operação valida tudo antes, mostra um resumo,
   pede UMA confirmação e, se algo falhar no meio, desfaz o que já fez.
3. **Idempotente** — repetir uma operação não estraga nada (ex.: aplicar a
   proteção SSH já aplicada só informa que já está ativa).
4. **Gerencia tudo o que é comum, nada do que é do sistema** — ver seção 4.
5. **Nada fixo do servidor no código** — o que der é detectado (faixas de
   UID/GID do `/etc/login.defs`, pontos de montagem, serviços); o resto fica
   em `/etc/debkit/debkit.conf`, com padrões sensatos no início do script.
6. **Rastreável** — log de auditoria em `/var/log/debkit.log` (quem, quando,
   o quê; nunca senhas) e backup automático antes de qualquer alteração,
   com rotação (ver seção 6).
7. **Uma execução por vez** — trava (`flock`) contra dois administradores
   alterando ao mesmo tempo.
8. **Sem dependências exóticas** — bash 4.4+, coreutils, ferramentas do
   Samba, shadow-utils (`useradd`, `chpasswd`), OpenSSH.
9. **Nunca testar em produção** — desenvolvimento e testes só na VM de
   desenvolvimento (ver seção 9).

## 3. Contas de usuário

### 3.1 Tipos de conta (escolhidos na criação)

| | **Usuário de arquivos** (padrão) | **Usuário com acesso ao servidor** |
|---|---|---|
| Para quem | quase todos: só acessam pastas pelo Samba | casos liberados por um administrador |
| Senha Samba | sim | sim |
| Senha Linux | **bloqueada** (não existe senha Linux utilizável) | própria, definida na criação |
| Shell | `/usr/sbin/nologin` | `/bin/bash` |
| Grupo de proteção SSH (`debkit_usuarios`) | **sim** — SSH recusado, inclusive túneis | não |

- O tipo "acesso ao servidor" exige confirmação explícita, com aviso de que
  a pessoa poderá entrar no servidor por SSH/console.
- **Trocar senha:** usuário de arquivos → só a do Samba (a Linux continua
  bloqueada); com acesso ao servidor → pergunta qual (Samba, Linux ou as
  duas).
- Senha com mínimo configurável (`SENHA_MIN`, padrão 4), lida sem eco,
  repetida para conferir e passada sempre pela entrada padrão.
- Nenhum usuário acessa o servidor a não ser pelo Samba, salvo os liberados
  por um administrador (tipo acima) e os administradores (`sudo`).
- *Em aberto (trocar senha):* o `smb.conf` padrão do Debian tem `unix
  password sync = yes`. Se um usuário de arquivos trocar a senha pelo
  Windows (Ctrl+Alt+Del), o Samba roda o `passwd` e a senha do Linux deixa
  de estar bloqueada (o `nologin` e o DenyGroups continuam barrando o SSH).
  O `smbpasswd` rodado pelo root (o que o debkit usa) NÃO sincroniza -
  conferido na 1.1, que também confere ao final que a senha continua
  bloqueada. Decidir na tarefa "trocar senha" (ex: desligar o sync ou
  avisar na verificação).
- *Em aberto:* oferecer ou não "dar `sudo`" no tipo com acesso ao servidor
  (por ora, não: virar administrador continua sendo feito à mão).

### 3.2 Proteção SSH gerenciada pelo próprio debkit

Nada de editar o `sshd` à mão:

- arquivo próprio `/etc/ssh/sshd_config.d/debkit.conf` com
  `DenyGroups debkit_usuarios`; o `sshd_config` principal não é tocado;
- só aplica se o `sshd_config` inclui `sshd_config.d/*.conf` (padrão no
  Debian 11+) **antes de qualquer bloco `Match`** — depois de um `Match` a
  regra valeria só dentro dele (comprovado com `sshd -T`); senão, avisa e
  não faz nada;
- valida com `sshd -t` ANTES de recarregar (recarregar com configuração
  inválida pode derrubar o serviço), recarrega sem derrubar sessões abertas
  e confere com `sshd -T` que a regra `denygroups` está em vigor para
  todos; se algo falhar, desfaz só o que fez;
- nunca sobrescreve um arquivo que não tem a marca do debkit e recusa aplicar
  se quem roda o debkit estiver no grupo (não tranca o administrador fora).
- Provado com login real (`tests/t04b_ssh_real.sh`): antes, um usuário com
  `nologin` autenticava e abria **túnel SSH**; depois, é recusado (inclusive
  o túnel), quem está fora do grupo continua entrando e as sessões já
  abertas não caem.

### 3.3 Pasta pessoal (home)

- **Opcional na criação; padrão: não criar.**
- As homes ficam numa **base no disco de dados** (`HOMES_BASE`, ex.:
  `/mnt/dados/homes`), não em `/home`: os dados ficam todos juntos para o
  backup. Na primeira vez o debkit detecta os pontos de montagem
  (`findmnt`), sugere um, e grava a base escolhida na configuração.
- Recusa base que não esteja de fato num sistema de arquivos montado
  diferente do `/` (nunca grava no disco do sistema por engano) e as pastas
  do sistema (mesma validação do swg).
- Oferece criar o compartilhamento `[homes]` (cada usuário vê só a própria
  pasta no Windows).
- Usuário existente: opção para criar/mover a home depois.
- **Feito na 1.1b** (16/10/2026): `HOMES_BASE` (vazio = ainda não
  definida) é escolhida na primeira vez entre os discos de dados montados
  (sugestão `<disco>/homes`), validada e gravada no `debkit.conf`. A base é
  recusada se: fica no disco do sistema (`/`), numa pasta do sistema
  (`/etc`, `/var`, `/usr`, `/tmp`, `/root`, `/boot`, `/run`...), passa por
  link (ou tem `/` no fim, `//`), é tmpfs/pseudo, não guarda dono e
  permissões (vfat, exfat, ntfs) ou está montada somente leitura. É
  conferida de novo a cada uso: com o disco de dados desmontado, nada é
  criado. A pasta é `HOMES_BASE/<login>`, 700, do usuário (com `/etc/skel`
  só para quem tem acesso ao servidor); nunca usa uma pasta que já existe.
  O `[homes]` do smb.conf padrão do Debian existe mas é somente leitura: o
  debkit oferece liberar a escrita (`read only = no`, e `valid users = %S`
  se faltar) ou criar a seção, pela edição segura; `[homes]` feito à mão
  (com `path` ou `valid users` próprios) não é mexido.
- *Em aberto:* **mover** a home de um usuário que já tem pasta (mexe em
  dados; fica para uma tarefa própria).

### 3.5 Nome de login e nome completo

Decisão de 16/10/2026:

- **Login:** letras minúsculas sem acento e números, começando por letra;
  nomes compostos no padrão `nome_sobrenome` ("_" entre as partes, sem "_"
  no começo/fim nem repetido); sem pontos, hífens, espaços ou maiúsculas;
  de 2 a 32 caracteres. Recusa nomes reservados (`root`, `admin`,
  `administrator`, `administrador`, `guest`, `convidado`, `nobody`) e o que
  já existe: usuário, grupo (o usuário novo ganha um grupo pessoal com o
  mesmo nome) ou conta Samba sem usuário no Linux.
- **Nome completo** (campo GECOS), opcional: aceita acentos ("Maria Souza -
  Financeiro"); não aceita `:` `,` `=` `\` nem caracteres de controle;
  até 100 caracteres. O debkit sugere o login a partir dele (primeiro e
  último nome, sem acento: "Maria Conceição Ávila - Financeiro" →
  `maria_avila`); Enter aceita a sugestão.
- Validação sem intervalos como `[a-z]`: no bash, num idioma pt_BR, `[a-z]`
  aceita letras acentuadas (encontrado nos testes da 1.1; corrigido também
  na validação do `debkit.conf`).

### 3.4 Remover x desativar

- **Desativar** (reversível): bloqueia o acesso (flag `D` no Samba) e mantém
  tudo; reativar volta com a mesma senha.
- **Remover** (definitivo): apaga do **Linux, do Samba e a pasta pessoal, se
  houver** — sem perguntas separadas, com UMA confirmação digitando o nome
  do usuário. Antes mostra o que será perdido e sugere desativar.
  - Sessões Samba abertas: mostra e encerra (necessário para o `userdel`).
  - A home só é apagada se estiver dentro de `HOMES_BASE` ou de `/home` e
    não for de outro usuário; fora disso é mantida e o debkit avisa.
  - Arquivos do usuário nos compartilhamentos NÃO são apagados.
  - Recusa se o grupo pessoal do usuário é usado no `smb.conf`.
- **Consistência:** contas só no Linux ou só no Samba aparecem marcadas,
  com opção de corrigir (criar a senha Samba / limpar a conta Samba órfã).

## 4. O que o debkit gerencia

Decisão de 15/10/2026 (substitui a regra anterior "só gerencia o que ele
criou"): o debkit gerencia **todos** os usuários, grupos e compartilhamentos
comuns do servidor — nunca os do sistema.

| | Gerencia | Não aparece / não mexe |
|---|---|---|
| Usuários | UID entre `UID_MIN` e `UID_MAX` do `/etc/login.defs` (Debian: 1000–60000) | usuários de sistema (root, www-data, nobody...): **nem aparecem nas listas** |
| Grupos | GID entre `GID_MIN` e `GID_MAX` | grupos de sistema; **grupos pessoais** (criados junto com o usuário) não aparecem nas listas |
| Compartilhamentos | todos do `smb.conf` | `[global]`, `[homes]`*, `[printers]`, `[print$]` |

\* `[homes]` só pela função de pastas pessoais (3.3).

- **Grupo pessoal** = grupo com o mesmo nome de um usuário e que é o grupo
  principal dele. É removido junto com o usuário (se não tiver outros
  membros). Se for usado no `smb.conf`, o debkit avisa nas operações em que
  isso importa.
- **Administradores** (membros do `sudo`): aparecem marcados como
  "admin"; o debkit **não** os remove, desativa nem aplica a proteção SSH.
  Nunca age sobre o próprio administrador que está rodando o debkit.
- O `smb.conf` é editado diretamente (não há mais arquivo separado com
  `include`), sempre com: backup (seção 6) → arquivo novo em temporário →
  `testparm` e conferência de que só mudou o pretendido → troca atômica
  mantendo dono/permissões → `reload` → se falhar, restaura o backup.

## 5. Preparação inteligente do ambiente

"Robusto e inteligente" não é só detectar um problema e mandar o
administrador resolver: o debkit **prepara o ambiente** para funcionar. Se
falta algo, ele explica, pergunta e, com o consentimento, resolve sozinho,
confere o resultado e segue (ou desfaz, se algo falhar).

**Três tipos de dependência** (inteligente também é não instalar o que não
precisa):

| Tipo | Exemplos | Se faltar |
|---|---|---|
| Essencial | Samba (`smbd`, `pdbedit`, `testparm`...), `useradd`, `chpasswd`, `flock`, bash 4.4+ | oferece instalar (sem isso não funciona) |
| Condicional | servidor SSH | **não instala**: sem SSH não há o que bloquear ("proteção SSH: não necessária"); se o SSH aparecer depois, oferece aplicar a proteção |
| Desenvolvimento | `shellcheck` | **nunca** instala no servidor de quem usa |

**Assistente de primeira execução:** verifica tudo e mostra um plano único
(instalar pacotes, ativar o serviço do Samba, criar `/etc/debkit/debkit.conf`,
backups e log, criar o grupo `debkit_usuarios`, aplicar a proteção SSH).
Com "s", executa item por item, conferindo cada um; se algo falhar, desfaz o
que fez e explica. Nas aberturas seguintes faz uma checagem rápida e
oferece consertar o que tiver "quebrado" (serviço parado...). Há também a
opção de menu **"Verificar e preparar o ambiente"**.

**Regras para qualquer mudança automática:**

- sempre pergunta antes e mostra exatamente o que vai fazer;
- instala só pelo gerenciador oficial (`apt-get`, sem perguntas
  interativas), espera se o apt estiver em uso por outro programa e, sem
  internet, explica sem deixar nada pela metade;
- registra tudo no log de auditoria;
- firewall ativo (ufw/firewalld) bloqueando o Samba: oferece liberar só a porta
  445/tcp (SMB moderno; NetBIOS 137-139 fica fechado) e só para as redes
  locais do servidor, nunca para qualquer origem; regras próprias de
  nftables/iptables: só avisa (não dá para interpretar regras escritas à mão);
- fora do Debian / sem `apt`: não arrisca — lista os pacotes e explica.

**Desinstalação:** opção que remove tudo o que o debkit colocou no sistema
(arquivo do SSH, grupo de proteção, configuração), sem mexer nos usuários e
compartilhamentos.

## 6. Backups

- **`smb.conf`:** antes de QUALQUER alteração, cópia em
  `/etc/samba/conf-bkp/` (`SMB_BACKUP_DIR`) com o nome
  `smb.conf.dd-mm-aaaa-hh-mm-ss` (ex.: `smb.conf.15-10-2026-17-42-05`).
  O debkit cria a pasta se não existir (root, 700) e mantém só os **últimos
  X** backups, apagando os mais antigos.
- **X = `BACKUP_MANTER`** (padrão **30**): o valor padrão fica no início do
  script e pode ser alterado em `/etc/debkit/debkit.conf` (validado: número
  de 1 a 9999). A rotação só apaga arquivos com o padrão de nome do debkit
  (nunca outros arquivos da pasta) e só depois que o backup novo foi criado
  e conferido.
- Dois backups no mesmo segundo: o segundo ganha sufixo (`-2`), nunca
  sobrescreve. O sufixo é sempre maior que o maior já usado naquele
  segundo (um nome liberado pela rotação não é reaproveitado), e a rotação
  nunca apaga o backup recém-criado (nem com o relógio atrasado); a ordem
  da rotação é pela data do nome, não alfabética.
- Demais arquivos do sistema que o debkit alterar (ex.: arquivo SSH):
  continuam em `BACKUP_DIR` (`/var/backups/debkit`), com a mesma rotação.

## 7. Arquitetura

- **Núcleo + módulos:** um comando `debkit` (menu principal que lista os
  módulos), o núcleo em arquivo próprio (`lib/nucleo.sh`) e cada módulo em
  seu arquivo (`modulos/samba.sh`). Instalação em `/usr/local/lib/debkit/`
  com link `/usr/local/sbin/debkit` (o `debkit` acha os arquivos pela pasta
  real, seguindo o link).
- **Como um módulo se encaixa** (feito na tarefa 1.0): o arquivo em
  `modulos/` chama `debkit_modulo_registrar <nome>`, acrescenta suas chaves
  de configuração, mensagens e dependências nas tabelas do núcleo e define,
  se quiser, os ganchos `debkit_<nome>_verificar` (itens da verificação),
  `debkit_<nome>_plano` (ações da preparação, com `debkit_acao_/descrever_/
  desfazer_<id>`) e `debkit_<nome>_menu` (item do menu principal). Um módulo
  novo entra só colocando o arquivo na pasta.
- **Carregamento seguro:** o debkit roda como root, então só carrega
  arquivos de código (e pastas) que pertencem ao root (ou a quem executa) e
  não têm escrita para grupo/outros; links também são recusados.
- **Dois modos de uso:** menu interativo e comandos diretos
  (ex.: `debkit samba usuario criar joao --grupos vendas`), que também
  permitem testes automáticos.
- **Distribuição:** foco em **Debian 12/13** (Ubuntu, derivado do Debian,
  tende a funcionar). O que muda entre distribuições (nomes de serviços,
  caminhos) fica isolado em um único ponto, para facilitar suporte futuro.
- **Idioma:** todas as mensagens num catálogo; português do Brasil é o
  padrão, preparado para inglês.

Estrutura do repositório (feita na tarefa 1.0; `install.sh` vem na Fase 4):

```
debkit/
├── debkit                # ponto de entrada (menu de módulos, linha de comando)
├── lib/nucleo.sh         # núcleo comum (o que era a Fase 0 do debkit.sh)
├── modulos/samba.sh      # módulo samba
├── debkit.conf.exemplo   # configuração comentada
├── install.sh            # instala/atualiza
├── tests/                # testes automáticos (dados descartáveis)
├── docs/                 # planejamento e decisões
├── README.md  CHANGELOG.md  LICENSE (MIT)
```

## 8. Fases

| Fase | Conteúdo |
|---|---|
| 0. Fundação | 0.1 esqueleto ✔ · 0.2 detecção do ambiente ✔ · 0.3 preparação do ambiente e backups ✔ · 0.4 proteção SSH ✔ · 0.5 firewall ✔ |
| 1. Usuários e grupos | 1.0 reestruturar ✔ (núcleo + módulo `samba.sh`; tirar `include`/`SHARES_CONF`/`PREFIXO_GRUPO`; faixas do `login.defs`; backup do `smb.conf` em `conf-bkp` com rotação) · 1.1 criar usuário ✔ (tipos, nome completo, grupos; sem home) · 1.1b pasta pessoal ✔ (base no disco de dados, na criação ou depois, `[homes]`) · listar · trocar senha · grupos (criar, remover, entrar/sair) · desativar/reativar · remover · consistência Linux x Samba |
| 2. Compartilhamentos | criar, listar, permissões de pasta, remover (inclusive os já existentes); pastas pessoais e `[homes]`; avaliar acesso somente leitura por grupo |
| 3. Diagnóstico | falhas de login, sessões ativas, saúde do Samba, consulta à auditoria |
| 4. Publicação | comandos diretos completos, `install.sh`, **desinstalação**, README, mensagens em inglês, testes automáticos e CI |

## 9. Forma de trabalho

- **Ambiente:** repositório no GitHub (`debkit`) e uma **VM Debian 13 de
  desenvolvimento, com snapshot**. Todo código é escrito e testado lá.
  **Nunca** rodar o debkit nem os testes no servidor de produção (a suíte
  cria usuários, grupos e unidades systemd de teste).
- Uma função (ou tarefa) por vez:
  1. implementar;
  2. revisão séria, criteriosa e minuciosa;
  3. testes de verdade cobrindo todas as situações possíveis, com dados
     descartáveis e limpeza ao final;
  4. só com tudo certo: commit (autor: Thiago Carrere; coautor: Claude).
- Trabalho na branch `dev`; a `main` é a versão pública estável e só recebe
  a `dev` (fast-forward) quando o Thiago decidir que está estável.

## 10. Herança do projeto swg

O debkit nasce da experiência do `swg` (menu Samba + WireGuard de uso
interno, hoje `samba_wireguard.sh`). Lições já aprendidas lá e que valem aqui:

- `smbpasswd` rodando como root **não** aplica o tamanho mínimo de senha;
- caminho relativo ou `/var/tmp`, `/var/www` etc. em operações recursivas
  podem quebrar o servidor — validar sempre (caminho completo, `realpath`,
  lista de pastas do sistema);
- `userdel -r` em usuário de sistema apaga pastas como `/var/backups` e
  `/var/www`;
- remover um bloco do `smb.conf` com segurança: backup, arquivo novo,
  conferir com `testparm` que só aquela seção saiu, troca atômica, reload e
  restauração se falhar (`smb_remover_compartilhamento` do swg);
- conferir o resultado real de cada operação (não confiar só no código de
  saída), e testar com login de verdade.

## 11. Situação atual e próximos passos

*Atualizado em 16/10/2026.*

- Nome decidido: **debkit**; renomeação gsb → debkit feita (arquivos,
  variáveis, funções, grupo `debkit_usuarios`, `/etc/debkit`, testes). As
  decisões das seções 3, 4 e 6 ainda **não** estão no código.
- **Tarefa 1.0 (reestruturação) concluída** em 16/10/2026: `debkit` (ponto
  de entrada) + `lib/nucleo.sh` + `modulos/samba.sh`, com registro de
  módulos e carregamento seguro; `include`/`SHARES_CONF`/`PREFIXO_GRUPO`
  retirados (chaves antigas viram aviso e a preparação tira as linhas do
  `debkit.conf`, conferindo que nenhum outro valor muda; ela também remove o
  `include` antigo dos servidores já preparados, conferindo com o
  `testparm` que nada mais muda no Samba); faixas de UID/GID do `login.defs`; backups do `smb.conf` em
  `SMB_BACKUP_DIR` (`/etc/samba/conf-bkp`) com o nome
  `smb.conf.dd-mm-aaaa-hh-mm-ss` e rotação por data; edição segura do
  `smb.conf` (`debkit_smbconf_editar`, pronta para a Fase 2).
- Renomeação conferida na VM em 16/10/2026: a VM limpa (sem Samba) foi
  preparada pelo próprio debkit (`--preparar`: instalou o Samba, ligou o
  serviço, criou a estrutura e aplicou a proteção SSH) e a suíte completa
  passou, inclusive as provas reais.

**Fase 0 (fundação) concluída** — commits na branch `dev`:

| Tarefa | Commit |
|---|---|
| 0.1 Esqueleto | `17cd607` |
| 0.2 Detecção do ambiente | `a7748d0` |
| 0.3 Preparação do ambiente | `95abea3` |
| 0.4 Proteção SSH | `345f64d` |
| 0.5 Firewall | `18e39fc` |

**Fase 1** — commits na branch `dev`:

| Tarefa | Commit |
|---|---|
| 1.0 Reestruturação | `361c996` |
| 1.1 Criar usuário | `caa0774` |
| Correção: pacotes de domínio (winbind) | `3e16425` |
| 1.1b Pasta pessoal | (este commit) |

**Próximos passos:**

1. ✔ Repositório `debkit` no GitHub e VM Debian 13 de desenvolvimento (com
   snapshot), com o repositório clonado em `/opt/debkit` e push por chave
   de implantação (deploy key) da VM.
2. ✔ Na VM ainda sem Samba: preparar o ambiente **pelo próprio debkit**
   (`debkit --preparar`; na época, `debkit.sh`). É a prova real da tarefa 0.3: o debkit precisa
   deixar o servidor pronto sozinho. As ferramentas de desenvolvimento
   (`shellcheck`, `smbclient`, `ufw` para a prova `t05b`) são instaladas à
   mão, porque o debkit nunca as instala.
3. ✔ Na VM: rodar a suíte completa (confere a renomeação).
4. ✔ Tarefa 1.0 — reestruturar.
5. ✔ Na VM: `./debkit --preparar` removeu o `include` antigo e as chaves
   antigas do `debkit.conf` (prova real da limpeza, feita pelo Thiago).
6. ✔ Tarefa 1.1 — criar usuário (sem home): regras de nome (3.5), tipo de
   conta (3.1), grupos comuns, senha sem eco e conferida, resumo e UMA
   confirmação, desfazer completo; só com o ambiente preparado. Prova real
   (`t07b`): login no Samba funciona (senha errada é recusada), usuário de
   arquivos recusado no SSH por DenyGroups, usuário com acesso ao servidor
   entra com a senha do Linux.
7. ✔ **Achado na prova real da 1.1 (corrigido, decisão do Thiago):** a preparação instalou o
   Samba com os pacotes "recomendados" do apt: veio o `samba-ad-dc`
   (controlador de domínio) e, com ele, `winbind`, `libpam-winbind` e
   `libnss-winbind`. O `pam_winbind` entrou no PAM do sistema e aceita a
   senha do Samba na fase de autenticação do SSH ("granted access"); só a
   fase de conta barrou. Num servidor independente nada disso é necessário.
   Correção: instalar com `--no-install-recommends`; num servidor
   independente a verificação detecta esses pacotes e a preparação oferece
   removê-los (simula antes e recusa se o apt quiser levar qualquer outro
   pacote; `purge`; confere PAM, NSS, `testparm` e o serviço do Samba). Na
   VM eles acabaram removidos por um teste (ver "Cuidados" abaixo); o
   resultado foi conferido: PAM/NSS sem winbind, smbd e SSH ativos, e a
   prova `t07b` confirma que o PAM não aceita mais a senha do Samba.
8. ✔ Tarefa 1.1b — pasta pessoal (3.3). Prova real (`t09b`): com um
   disco de teste e o `[homes]` liberado pelo debkit, o usuário grava na
   própria pasta pelo Samba e outro usuário não acessa.
9. Para testar à mão na VM: adicionar um segundo disco no VirtualBox,
   formatar (ext4) e montar (ex: `/mnt/dados`) — a VM só tem o disco do
   sistema, e a pasta pessoal nunca vai para ele.
10. **Próxima tarefa:** listar usuários (Fase 1).

**Como rodar os testes (só na VM):**

```
tests/run.sh                                         # suíte normal (caixa de areia)
DEBKIT_TESTE_REAL=1 tests/run.sh t04b_ssh_real.sh    # prova com o SSH real
DEBKIT_TESTE_REAL=1 tests/run.sh t05b_ufw_real.sh    # prova com o ufw real (instalado e INATIVO)
DEBKIT_TESTE_REAL=1 tests/run.sh t07b_usuario_real.sh  # login real no Samba e no SSH (ambiente real preparado)
DEBKIT_TESTE_REAL=1 tests/run.sh t09b_home_real.sh   # [homes] real com disco de teste (smb.conf volta idêntico)
shellcheck -x debkit lib/*.sh modulos/*.sh           # cada arquivo (o -x sozinho não mostra os avisos dos carregados)
```

O `tests/run.sh` compara uma "impressão digital" do sistema real antes e
depois de cada arquivo de teste e falha se algo mudar. Situação ao fim da
Fase 0: 320 verificações na suíte normal + 27 nas provas reais, todas
passando; `shellcheck` sem avisos no `debkit.sh`. Na VM, com o servidor já
preparado pelo debkit (16/10/2026): 316 + 26, todas passando. Ao fim da
tarefa 1.0: 521 + 26, todas passando; `shellcheck` sem avisos nos três
arquivos do programa. Ao fim da 1.1: 688 + 47 (provas reais: `t04b`,
`t05b` e `t07b_usuario_real.sh`). Os testes da 1.1 criam usuários Linux
`dkt_*` reais (removidos no fim); a base de senhas do Samba da areia é
separada da real (`copiar_smb_conf` aponta `passdb backend` e as pastas
de estado para a areia). Com a correção dos pacotes de domínio: 733 + 48
(`t08_dominio.sh`). Ao fim da 1.1b: 898 + 65 (`t09_home.sh` monta discos
de teste de verdade - arquivos ext4 em loop, um somente leitura e um tmpfs
- em `/mnt/dkt-teste.*` e desmonta no fim; a impressão digital do `run.sh`
confere que nenhuma montagem sobrou).

Os testes funcionam com o servidor preparado ou não: em vez de exigir que
os arquivos reais do debkit não existam, conferem que não mudaram
(`estado_real`/`real_intacto` em `tests/lib.sh`).

**Cuidados aprendidos na Fase 0** (valem para as próximas tarefas):

- a caixa de areia dos testes precisa isolar TUDO que o debkit pode alterar
  (smb.conf, backups, grupo, `SSH_DROPIN`...): numa tarefa um teste chegou a
  criar o arquivo SSH real; daí nasceu a trava do `run.sh`;
- testar o comportamento real das ferramentas antes de codificar
  (ex.: `server role = auto`; `Include` depois de `Match` no SSH; o próprio
  `ufw allow` com o ufw inativo cria tabelas nft vazias);
- em operações sobre serviços sensíveis (SSH), validar antes de recarregar
  e desfazer só o que a operação realmente fez.

**Cuidados aprendidos na tarefa 1.0:**

- a cópia do `smb.conf` real na caixa de areia traz caminhos REAIS (o
  `include` antigo apontava para `/etc/samba/debkit-shares.conf`): a cópia
  agora sai sem essas linhas (`copiar_smb_conf`), e a ação só apaga o
  arquivo antigo se ele estiver na mesma pasta do `smb.conf` e tiver o
  cabeçalho do debkit - foi essa trava que protegeu o arquivo real quando
  um teste ainda copiava o `smb.conf` sem limpar;
- toda chave de configuração nova precisa ir também para a configuração da
  areia (`tests/lib.sh` e o `CFG` dos testes): um teste montava a
  configuração à mão sem `SMB_BACKUP_DIR` e criou `/etc/samba/conf-bkp`
  real (só com cópias da areia; apagada, e a pasta agora está na
  impressão digital do `run.sh`);
- rotação de backups com nomes reaproveitáveis: o nome liberado pela
  rotação voltava a ser usado e o backup novo era apagado logo depois de
  criado. Teste "o backup recém-criado existe" em toda rotação.

**Cuidados aprendidos na tarefa 1.1:**

- a caixa de areia não isolava o apt nem a base do dpkg: com o item novo
  de remover pacotes de domínio, um `--preparar` de teste respondendo "s"
  rodou o `apt-get purge` REAL (removeu os pacotes que já iam ser
  removidos, mas por um teste). Agora a areia usa um apt que recusa tudo
  (`DEBKIT_APT`) e uma base do dpkg vazia (`DEBKIT_DPKG_ADMIN`), e a
  impressão digital do `run.sh` inclui pacotes, PAM e `nsswitch.conf`.
  Regra: toda ação nova que mexa em algo do sistema precisa, junto, do
  isolamento na areia e de uma linha na impressão digital;
- a cópia do `smb.conf` na areia apontava a base de senhas REAL do Samba:
  agora `passdb backend` e as pastas de estado vão para a areia;
- no bash, `[a-z]` em pt_BR aceita letras acentuadas: listar as letras;
- `read -p` não mostra a pergunta quando a entrada não é um terminal:
  textos de pergunta se testam com `pty`.
