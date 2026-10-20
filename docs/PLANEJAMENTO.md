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
- **Decisão de 16/10/2026 (Thiago): desligar a sincronização.** A
  preparação oferece mudar para `unix password sync = no` (edição segura do
  `smb.conf`, com backup e conferência). Trocar a senha pelo Windows passa
  a mudar só a do Samba; a senha Linux do usuário de arquivos fica sempre
  bloqueada. Quem tem acesso ao servidor troca a senha Linux pelo debkit
  ("trocar senha" pergunta: Samba, Linux ou as duas) ou com `passwd`.
  Motivo, registrado antes da decisão: o `smb.conf` padrão do Debian tem `unix
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

Decisão de 19/10/2026 (Thiago): na prática o ciclo é criar → adicionar a
um ou mais grupos → excluir quando a pessoa sai. **Desativar/reativar sai
da Fase 1** (contas desativadas só poluiriam as listagens); fica registrado
abaixo para o caso de um dia fazer falta. A próxima tarefa é **remover**.

- **Desativar** (reversível): bloqueia o acesso (flag `D` no Samba) e mantém
  tudo; reativar volta com a mesma senha.
- **Remover / Excluir** (definitivo; feito em 19/10/2026): apaga do **Linux,
  do Samba e a pasta pessoal, se houver** — sem perguntas separadas, com
  UMA confirmação **s/n** (decisão do Thiago: não digitar o login). Antes
  mostra o que será perdido (tipo, contas, grupos, pasta pessoal).
  - Não exclui administradores (`sudo`) nem quem está rodando o debkit.
  - Sessões Samba abertas: mostra e encerra (necessário para o `userdel`).
    Outros processos do usuário (ex.: SSH aberto): **recusa** e não mata
    (o `userdel` também recusaria - testado).
  - Ordem: sessões → `userdel` (nunca `-r`; se falhar, nada foi apagado) →
    conta Samba → pasta pessoal → grupo pessoal que sobrar vazio (o
    `userdel` não o apaga se for o principal de outro usuário - testado).
  - A home só é apagada se for `<HOMES_BASE ou /home>/<pasta>`, pasta de
    verdade (não link), do próprio usuário e de mais ninguém; fora disso é
    mantida e o debkit avisa.
  - Arquivos do usuário nos compartilhamentos NÃO são apagados: o debkit
    mostra quantos são, porque ficam com o UID e um usuário criado depois
    pode receber o mesmo UID e virar dono deles (comprovado no `t14`).
  - Recusa se o grupo pessoal do usuário é usado no `smb.conf`; avisa se
    o login é citado nos compartilhamentos.
  - Achado na prova real: com `map to guest = Bad User` (padrão do Debian),
    entrar com o nome de quem foi excluído vira sessão de convidado
    (`nobody`) em vez de ser recusado. Sem compartilhamento `guest ok` não
    dá acesso a nada; **decidir na Fase 2** (ex.: a preparação mudar para
    `map to guest = Never`).
- **Consistência** (feito em 19/10/2026; Samba → Usuários → 6): lista o
  que está fora do padrão e corrige um a um, com s/n em cada:
  - conta só no Samba → apaga a conta Samba órfã;
  - usuário só no Linux → cria a conta Samba (pede a senha; a do Linux não
    muda - se mudar junto, volta);
  - shell sem login fora do grupo de proteção (o SSH ainda autentica e abre
    túnel, regra 3.2) → põe no `debkit_usuarios`;
  - usuário de arquivos com senha do Linux utilizável (regra 3.1) →
    bloqueia (`!`, como na criação).
  Prova real (`t15b`): o `nologin` fora do grupo abria sessão SSH; depois
  da correção, o SSH recusa.

### 3.6 Grupos

Decisão de 19/10/2026 (Thiago):

- **Ao criar um usuário:** grupo pessoal (mesmo nome, grupo principal;
  padrão do Debian com `USERGROUPS_ENAB yes` - ninguém entra no `users`),
  `debkit_usuarios` só se for usuário de arquivos, e os grupos escolhidos.
- **Nome do grupo:** as mesmas regras do login (3.5), recusando os nomes
  reservados, o que já existe como grupo ou usuário e nomes começando por
  `debkit`. O `groupadd` sozinho aceita `Dkt.G` (testado): quem controla o
  nome é o debkit.
- **Criar:** confere o nome, cria o grupo comum (GID na faixa do
  `login.defs`), oferece adicionar membros, resumo e UMA confirmação; confere
  no fim o grupo e os membros (se algo falhar, desfaz).
- **Grupos gerenciados:** só os comuns (GID na faixa), sem os grupos
  pessoais, o `debkit_usuarios` (depende do tipo da conta: mexer nele
  liberaria ou trancaria o SSH), os grupos de sistema (`sudo`, `users`...)
  e os grupos citados no sudoers (`%grupo`, `%#gid`, também no
  `sudoers.d`): entrar neles daria sudo. Também não cria grupo com nome já
  citado no sudoers. (Achado na revisão da tarefa.)
- **Adicionar e remover membros** (termos da tela, decisão do Thiago em
  19/10/2026): tela por grupo (escolhe o grupo, vê os membros, adiciona ou
  remove). Membros: os usuários comuns, inclusive admins. A lista
  é trocada de uma vez (`gpasswd -M`, que recusa tudo se um nome não
  existe) e conferida; se não conferir, volta a anterior.
- **Efeito na hora (decisão de 19/10/2026, Thiago: sempre automático):** o
  Samba lê os grupos só quando a sessão começa e o Windows reaproveita a
  sessão para todas as pastas - sem nada, quem entra no grupo não abre a
  pasta nova e quem sai continua acessando até reconectar. Ao criar,
  mudar membros ou remover um grupo, o debkit encerra as sessões abertas
  SÓ dos usuários afetados (`smbstatus -p` → `smbcontrol <pid> shutdown`;
  se não adiantar, TERM no processo, só se for um `smbd`) e confere que
  acabaram; o Windows reconecta sozinho, com os grupos novos. Antes da
  confirmação a tela avisa quem está conectado (arquivo aberto sem salvar
  pode ser afetado). Não precisa recarregar o Samba (ele consulta os
  grupos no Linux a cada sessão nova). Prova real (`t13b`), com sessão
  aberta: entrar → acessa na hora; sair e remover → a sessão aberta para
  de gravar na hora.
- **Remover:** o `groupdel` apaga grupo com membros sem avisar e recusa o
  grupo principal de um usuário (testado). O debkit:
  - recusa se for o grupo principal de algum usuário;
  - mostra os membros (perdem o acesso);
  - **avisa** se o grupo é usado no `smb.conf` (mostra os compartilhamentos)
    e se há arquivos do grupo na base das pastas pessoais e nos caminhos
    dos compartilhamentos (mostra quantos: o GID pode ser reaproveitado por
    um grupo novo, que herdaria o acesso);
  - pede UMA confirmação **s/n** (decisão do Thiago em 19/10/2026: digitar
    o nome ficaria cansativo; o mesmo vale para excluir usuário).

### 3.7 Compartilhamentos (Fase 2)

Decisão de 19/10/2026 (Thiago):

1. **Convidado:** a preparação muda para `map to guest = never` (o padrão
   do Debian, `bad user`, faz quem não existe - ex.: um usuário excluído -
   virar convidado em vez de ser recusado). O debkit não cria
   compartilhamento para convidado (`guest ok`). ✔ (tarefa 2.0)
2. **Acesso por grupo (revisto no mesmo dia):** cada compartilhamento é
   vinculado a **um único grupo**, cujos membros têm **acesso total** (ex.:
   `compras` → `gp_compras`). Não existe compartilhamento sem grupo. Para
   dar acesso a alguém, a pessoa entra no grupo; não há permissão por
   usuário nem somente leitura (na prática, todos do setor precisam de acesso total aos
   arquivos do setor; era assim no script de partida). Um grupo pode ter
   mais de um compartilhamento. Pasta `root:<grupo>` `2770`; no smb.conf,
   `valid users = @<grupo>`, `read only = no`, `force group`. Sem pacote
   extra (ACL).
3. **Onde ficam as pastas:** só dentro de **`/mnt` ou `/srv`** (os lugares
   usuais para dados), numa base configurável ou numa pasta já existente,
   nunca pasta do sistema.
4. **Nome:** **só minúsculas** sem acento, números, `-` e `_`, começando
   por letra, de 2 a 32 caracteres; recusa os reservados (`global`,
   `homes`, `printers`, `print$`, `ipc$`) e os que já existem.
5. **Remover:** tira do `smb.conf`; a pasta e os arquivos ficam (o debkit
   mostra onde), mas a pasta volta para `root:root`: só o root acessa.
   Apagar dados não faz parte da função.
6. **Já existentes (feitos à mão):** aparecem na listagem; os que não
   seguem o padrão (um grupo com acesso total) têm alerta. Na 2.4, o
   debkit oferece trazer para o padrão ou removê-los, mexendo só nas
   linhas que gerencia e mantendo o resto da seção.
7. **Efeito na hora:** como nos grupos (prova real com sessão aberta).

Ordem: 2.0 convidado → 2.1 criar + listar → 2.2 permissões → 2.3 remover
→ 2.4 existentes.

**Como ficou a 2.1 (criar + listar):** base `SHARES_BASE` (definida na
primeira criação; sugestão `<disco de dados em /mnt>/compartilhamentos` ou
`/srv/samba`); pasta padrão `<base>/<nome>` ou outra dentro de `/mnt`/`/srv`
(real, sem link, a de cima existindo, sem se misturar com a base das
pastas pessoais nem com a pasta de outro compartilhamento). Bloco no
smb.conf: `valid users = @<grupo>`, `read only = no`, `force group`,
`create mask = 0660`, `directory mask = 2770`. Conferência: fora a seção
nova nada muda, e a seção em vigor é igual ao `testparm` do bloco sozinho.
Pasta que já existe tem dono e permissões ajustados (o conteúdo, na
2.2); se algo falhar, a pasta nova é apagada ou a existente volta como era
(`chmod` com 5 dígitos: em pasta, `755` manteria o setgid). A listagem
mostra todos (inclusive os feitos à mão), com quem acessa calculado como o
Samba faz (quem só lê aparece marcado), e alerta pasta inexistente,
`guest ok`, falta de `valid users` e o que está fora do padrão. Prova real
(`t17b`): os membros do grupo gravam (e um altera e apaga o arquivo do
outro), e quem está fora do grupo é recusado.

**Como ficou a 2.2 (grupo e permissões; Compartilhamentos → 3 e 4):**

1. **Quais são gerenciáveis:** os que estão no padrão (um grupo gerenciado
   com acesso total, pasta existente dentro de `/mnt`/`/srv`, sem se
   misturar com as pastas pessoais nem com outro compartilhamento),
   inclusive os feitos à mão. Os outros ficam para a 2.4.
2. **Trocar o grupo:** o resumo mostra quem perde o acesso (membros do
   antigo que não estão no novo), quem está conectado e o conteúdo; UMA
   confirmação s/n. No smb.conf (edição segura) só as linhas de acesso da
   seção mudam (`valid users`, `read only`, `force group`; tira
   `write list`/`read list`/`writeable`...); a conferência compara o resto
   e restaura se não bater. Depois o conteúdo passa para o grupo novo e as
   sessões de quem perdeu o acesso são refeitas.
3. **Ajustar o conteúdo:** pasta `root:<grupo>` `2770`; dentro, tudo com o
   grupo, rw para o grupo (pastas com setgid; executável continua
   executável), nada para outros, sem setuid/setgid em arquivo. Os donos
   não mudam; não segue links nem sai do disco. Mostra quantos itens estão
   fora do padrão; tudo certo = não pergunta. Seguro rodar de novo.
4. **Criar numa pasta com arquivos:** depois de criar, mostra o conteúdo
   fora do padrão e oferece ajustar.
5. **Remover grupo usado no smb.conf:** recusado (troque o grupo ou remova
   o compartilhamento antes); antes era só um aviso.

Prova real (`t18b`): depois da troca, os membros do grupo novo gravam e os
do antigo são recusados, inclusive com a sessão aberta.

**Como ficou a 2.3 (remover; Compartilhamentos → 5; Pastas pessoais virou
6):** só os que estão no padrão (os outros ficam para a 2.4). O resumo
mostra a pasta que fica, quem perde o acesso (membros e quem tem o grupo
como principal) e quem está conectado; UMA confirmação s/n. No smb.conf
(edição segura) sai a seção inteira (todas, se repetida; sem diferenciar
maiúsculas), com o comentário `# debkit: compartilhamento criado em` e os
comentários de dentro dela; fica o bloco de comentários colado no
cabeçalho seguinte. A conferência exige que só a seção tenha saído. Depois
a pasta passa a `root:root` `0700` (os arquivos não mudam) e as sessões de
quem tinha o acesso são refeitas. Se a pasta não mudar, o compartilhamento
já saiu e o debkit avisa para conferir à mão. Criar de novo com a mesma
pasta devolve a pasta ao grupo. Prova real (`t19b`): a sessão aberta perde
o acesso na hora, conexão nova é recusada, os arquivos ficam e outro
compartilhamento continua funcionando.

**Como ficou a 2.4 (os já existentes; Compartilhamentos → 6 "Trazer para
o padrão"; Pastas pessoais virou 7):**

1. **Quais podem ser trazidos para o padrão:** os que não estão no padrão
   (vários grupos, usuários, somente leitura, sem `valid users`, `guest
   ok`, um grupo que o debkit não gerencia, ex.: `@users`) e cuja pasta
   pode mudar: existe dentro de `/mnt`/`/srv`, sem se misturar com as
   pastas pessoais nem com outro compartilhamento. Os outros (pasta fora
   de `/mnt`/`/srv`, inexistente, com `%` ou de outro compartilhamento) só
   podem ser removidos.
2. **Trazer para o padrão:** escolhe um grupo gerenciado; o resumo mostra
   o acesso de antes e o novo, quem perde o acesso, quem está conectado, as
   linhas do smb.conf e o conteúdo; UMA confirmação s/n. Na seção, saem as
   linhas que o debkit gerencia - acesso (`valid users`, `write list`,
   `read list`, `read only` e sinônimos, `force group`), convidado (`guest
   ok`/`public`, `guest only`), permissões dos arquivos novos (`create
   mask`/`mode`, `directory mask`/`mode`, `force create mode`, `force
   directory mode`), `force user`, `admin users` e `invalid users` - e
   entram as do padrão (as mesmas de criar). O resto da seção fica (ex.:
   `comment`, `browseable`, `veto files`). A conferência exige que só
   essas linhas mudem. Depois o conteúdo passa para o grupo e as sessões
   de todos que tinham o acesso são refeitas (quem perde e quem passa de
   leitura para escrita; "qualquer usuário" = todas as contas do Samba).
3. **Remover** (a tela Remover lista todos, inclusive os feitos à mão):
   a pasta só passa a `root:root` `0700` se puder mudar (item 1); senão
   fica como está e o debkit avisa. A decisão é tomada antes de mexer no
   smb.conf (com duas seções na mesma pasta, remover uma não tranca a
   pasta da outra).

Prova real (`t20b`): três compartilhamentos escritos à mão no smb.conf
real; trazer um para o padrão corta na hora a sessão aberta de quem perde
o acesso, e o grupo passa a gravar e alterar os arquivos que já existiam;
remover outro que divide a pasta com o terceiro não muda a pasta, e o
terceiro continua funcionando.

### 3.8 Diagnóstico (Fase 3)

Decisão de 20/10/2026 (Thiago):

1. **Menu:** Samba → **4) Diagnóstico**, ao lado de Usuários, Grupos e
   Compartilhamentos.
2. **Sessões ativas:** quem está conectado agora (usuário, IP/máquina,
   compartilhamentos abertos, arquivos travados) e **desconectar** a
   sessão de um usuário (s/n, com auditoria; o Windows reconecta sozinho
   se a pessoa ainda tiver acesso).
3. **Logins (falhas e sucessos):** o debkit **liga o log de autenticação
   do Samba** na preparação (com backup e conferência, como o `map to
   guest`): `log level = 1 auth_json_audit:3@/var/log/samba/debkit-auth.json`.
   Mostra as últimas falhas (senha errada, usuário inexistente, conta
   desativada), por usuário e IP, e o último login de cada usuário.
4. **Saúde do Samba:** um relatório só - serviços, smb.conf válido,
   portas, espaço em disco das pastas, alertas dos compartilhamentos e das
   contas.
5. **Consulta à auditoria:** o log do debkit (`/var/log/debkit.log`) com
   filtro por data, usuário afetado e tipo de ação.

Prova feita na VM (Samba 4.22, servidor independente, 20/10/2026): com o
`log level` acima, cada tentativa vira uma linha JSON no arquivo próprio,
com `status` (`NT_STATUS_WRONG_PASSWORD`, `NT_STATUS_OK`,
`NT_STATUS_NO_SUCH_USER`), `clientAccount`, `remoteAddress` e
`workstation`. Por padrão (sem isso) o Samba não registra falha de login.

**Como ficou a 3.0 (log de autenticação; item da preparação):**

1. **smb.conf:** no `[global]`, `log level = <nível do administrador, ou 0>
   auth_json_audit:3@<AUTH_LOG>`. Outra configuração da mesma classe sai;
   `debug level` (sinônimo) sai; o resto do `log level` fica. O `testparm`
   **não mostra** o `log level` (nem com `-v`): o valor é lido do arquivo e
   a conferência exige que a configuração em vigor fique idêntica.
2. **Rotação:** o `max log size` do Samba **não gira** o arquivo de uma
   classe (provado: 25 KB com limite de 1 KiB). Regra própria em
   `/etc/logrotate.d/debkit-samba-auth`: semanal, 12 semanas, compactada.
   Não precisa de `postrotate`: cada conexão nova reabre o log (provado;
   `smbcontrol smbd reopen-logs` não existe no 4.22). O `logrotate -d`
   confere a regra. Se a regra mudar à mão, a preparação recria (com
   backup).
3. **Configuração:** `AUTH_LOG` e `AUTH_LOGROTATE` no `debkit.conf`;
   `logrotate` entra nas dependências essenciais.
4. **Desfazer:** smb.conf do backup; a regra nova é apagada (ou a antiga
   volta).

Prova real (`t21b`): ligado pelo debkit no smb.conf real, o smbd passa a
registrar a classe (`smbcontrol smbd debuglevel`); senha errada, usuário
inexistente e sucesso aparecem com o IP; `logrotate -f` gira e o login
seguinte cai no arquivo novo. Os testes espelham no sandbox o estado do
servidor real (`copiar_smb_conf` aponta a linha e a regra para o sandbox).
A VM real foi preparada pelo próprio debkit em 20/10/2026.

**Como ficou a 3.1 (sessões ativas; Samba → 4) Diagnóstico → 1):** uma
linha por sessão (um processo do smbd = uma máquina): usuário, IP, desde
quando (a conexão mais antiga), quantos arquivos abertos e os
compartilhamentos (sem o `IPC$`). Lido do texto do `smbstatus` (`-p`,
`-S`, `-L`), sem dependência nova; nomes com espaços (compartilhamento,
pasta, arquivo) são lidos a partir da direita. **Desconectar** é por
sessão, não por usuário (a mesma pessoa em duas máquinas: só a escolhida
cai): o resumo mostra os compartilhamentos e os arquivos abertos (até 10)
e avisa que alterações não salvas podem ser perdidas; UMA confirmação s/n.
O PID tem de estar entre as sessões do Samba naquele momento (senão é
recusado); `smbcontrol <pid> shutdown` e, se não adiantar, TERM só se o
processo for um smbd (a mesma rotina da reconexão dos grupos, agora por
PID). Auditado (`sessao_desconectar`). Prova real (`t22b`): duas sessões,
uma com arquivo aberto; a desconectada acaba na hora, a outra continua, e
as sessões de fora do teste não mudam.

Ordem: 3.0 log de autenticação (preparação e verificação) → 3.1 sessões
ativas → 3.2 logins → 3.3 saúde → 3.4 auditoria.

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
| 1. Usuários e grupos | 1.0 reestruturar ✔ (núcleo + módulo `samba.sh`; tirar `include`/`SHARES_CONF`/`PREFIXO_GRUPO`; faixas do `login.defs`; backup do `smb.conf` em `conf-bkp` com rotação) · 1.1 criar usuário ✔ (tipos, nome completo, grupos; sem home) · 1.1b pasta pessoal ✔ (base no disco de dados, na criação ou depois, `[homes]`) · listar ✔ · trocar senha ✔ · grupos ✔ (criar, remover, entrar/sair) · menu em submenus ✔ · excluir usuário ✔ · consistência Linux x Samba ✔ · ~~desativar/reativar~~ (adiado, 3.4) |
| 2. Compartilhamentos | decisões na seção 3.7 · 2.0 `map to guest = never` ✔ · 2.1 criar + listar ✔ · 2.2 grupo e permissões (trocar o grupo, ajustar o conteúdo) ✔ · 2.3 remover ✔ · 2.4 os já existentes ✔ |
| 3. Diagnóstico | decisões na seção 3.8 · 3.0 log de autenticação ✔ · 3.1 sessões ativas ✔ · 3.2 logins (falhas e sucessos) · 3.3 saúde do Samba · 3.4 consulta à auditoria |
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

*Atualizado em 20/10/2026 (3.1).*

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
| 1.1b Pasta pessoal | `df06673` |
| Scripts da VM de desenvolvimento | `7e20a14` |
| Listar usuários | `8ff61b1` |
| Trocar senha (+ unix password sync desligado) | `64ab68c` |
| Grupos (criar, membros, remover) | `aa7f084` |
| Grupos: efeito na hora (reconexão automática) | `5d77706` |
| Menu do Samba em submenus | `32fda5b` |
| Excluir usuário; grupos com s/n e "adicionar/remover" | `8842b1e` |
| Verificar e corrigir contas (consistência) | `bef38c8` |
| 2.0 map to guest = never (+ decisões da Fase 2) | `01658d6` |
| 2.1 Compartilhamentos: criar e listar | `b976033` |
| Compartilhamentos: um grupo só, com acesso total | `92ebf2f` |
| 2.2 Compartilhamentos: trocar o grupo e ajustar o conteúdo | `b11457a` |
| 2.3 Compartilhamentos: remover | `fc4a104` |
| 2.4 Compartilhamentos já existentes: trazer para o padrão ou remover | `a3d072e` |
| Fase 3 decidida | `372c835` |
| 3.0 Log de autenticação do Samba (preparação) | `ce832a9` |
| Testes: "caixa de areia" vira sandbox | `7e5f8dd` |
| 3.1 Sessões ativas (ver e desconectar) | `2ebdf36` |

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
10. ✔ Scripts da VM de desenvolvimento: `dev/vmnova.sh` (volta ao
    snapshot "limpa" e reinicia, com travas: só VM, repositório commitado,
    enviado e fora dos snapshots, digitar RESTAURAR, `--simular`) e
    `dev/vmprepara.sh` (instala shellcheck, smbclient e ufw inativo; não
    instala o Samba). Testes em `t10_dev.sh` com Timeshift e apt falsos.
11. ✔ Listar usuários (menu Samba, opção 1): só contas comuns; login, nome
    completo, tipo (arquivos / servidor / admin = membro do sudo / nologin =
    shell sem login FORA do grupo de proteção), Samba (ativa / desativada /
    sem conta / só no Samba), pasta pessoal e grupos comuns; total por
    tipo e alertas (conta só no Samba, só no Linux, e nologin fora do grupo
    de proteção - o SSH ainda autentica e abre túnel, como a prova da 0.4
    mostrou). Colunas alinhadas por caracteres (acentos). O menu do Samba
    passou a ser: 1 listar, 2 criar usuário, 3 pasta pessoal de usuário
    existente, 4 pastas pessoais.
12. ✔ Trocar senha (menu Samba, opção 3; criar pasta pessoal e pastas
    pessoais passaram a 4 e 5). Usuário de arquivos (e nologin): só a do
    Samba, conferindo depois que a do Linux não mudou (se mudou, volta);
    com acesso ao servidor: Samba, Linux ou as duas (Linux primeiro; se o
    Samba falhar, a do Linux volta ao hash anterior pela entrada padrão do
    `chpasswd -e`); admin: só a do Samba (a do Linux, à mão com `passwd`).
    A preparação desliga o `unix password sync` (edição segura: troca o
    valor na própria linha do `[global]`; conferência: a configuração em
    vigor perde só essa linha). Prova real na VM: `--preparar` mudou uma
    única linha do smb.conf; `t07b` confirma a senha nova no Samba e no
    SSH e a antiga recusada.
13. ✔ README do GitHub repaginado (19/10/2026): apresentação, tabela dos
    tipos de conta, destaques, telas com dados fictícios, o que já faz,
    instalação para teste, qualidade (testes), roteiro e compatibilidade.
14. ✔ Grupos (menu Samba, opção 6: listar, criar, membros, remover;
    decisões na seção 3.6). Prova real na VM (`t13b`): o grupo dá o acesso
    a um compartilhamento `valid users = @grupo`; entrar, sair e remover
    valem na hora, inclusive com a sessão aberta (o debkit refaz a sessão
    dos usuários afetados); o smb.conf real volta idêntico. Achado na revisão: grupos citados no sudoers ficam
    fora (entrar neles daria sudo).
15. ✔ Menu do Samba em submenus (decisão de 19/10/2026, Thiago: estava
    tudo misturado): Samba → 1) Usuários (listar, criar, trocar senha,
    criar pasta pessoal) · 2) Grupos (listar, criar, membros, remover) ·
    3) Compartilhamentos (por enquanto só pastas pessoais/`[homes]`; o
    resto na Fase 2). Desativar/reativar adiado (3.4).
16. ✔ Excluir usuário (Samba → Usuários → 5; regras na seção 3.4).
    Prova real (`t14b`): a sessão aberta no Samba é encerrada e o usuário
    some do Linux e da base real; com SSH aberto a exclusão é recusada.
17. ✔ `map to guest`: decidido e feito na tarefa 2.0 (seção 3.7).
18. ✔ Consistência Linux x Samba (Samba → Usuários → 6; seção 3.4).
    **Fase 1 concluída.**
19. ✔ Fase 2 decidida (seção 3.7). Tarefa 2.0: a preparação muda para
    `map to guest = never` (filtro genérico de parâmetro do `[global]`,
    também usado pelo `unix password sync`). Prova real na VM: o
    `--preparar` mudou uma única linha do smb.conf; `t16b` confirma nome
    inexistente e usuário excluído recusados.
20. ✔ 2.1 criar + listar compartilhamentos (Samba → Compartilhamentos → 1
    e 2; detalhes na seção 3.7).
21. ✔ Revisão do modelo (decisão do Thiago): um grupo só por
    compartilhamento, com acesso total; sem somente leitura (seção 3.7).
    A tela Criar pergunta um grupo.
22. ✔ 2.2 grupo e permissões (Samba → Compartilhamentos → 3 e 4; seção
    3.7). Remover grupo usado no smb.conf passa a ser recusado.
23. ✔ 2.3 remover compartilhamento (Samba → Compartilhamentos → 5; seção
    3.7).
24. ✔ 2.4 os já existentes (Samba → Compartilhamentos → 6 e 5; seção 3.7).
    **Fase 2 concluída.**
25. ✔ Fase 3 decidida (seção 3.8).
26. ✔ 3.0 log de autenticação do Samba (item da preparação; seção 3.8).
27. ✔ 3.1 sessões ativas (Samba → 4) Diagnóstico → 1; seção 3.8).
28. **Próxima tarefa:** 3.2 logins (falhas e últimos logins, pelo log de
    autenticação da 3.0).

**VM limpa de novo:** `dev/vmnova.sh` → (reinicia) → `dev/vmprepara.sh` →
`./debkit --preparar` → testes.

**Como rodar os testes (só na VM):**

```
tests/run.sh                                         # suíte normal (sandbox)
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
`dkt_*` reais (removidos no fim); a base de senhas do Samba do sandbox é
separada da real (`copiar_smb_conf` aponta `passdb backend` e as pastas
de estado para o sandbox). Com a correção dos pacotes de domínio: 733 + 48
(`t08_dominio.sh`). Ao fim da 1.1b: 898 + 65 (`t09_home.sh` monta discos
de teste de verdade - arquivos ext4 em loop, um somente leitura e um tmpfs
- em `/mnt/dkt-teste.*` e desmonta no fim; a impressão digital do `run.sh`
confere que nenhuma montagem sobrou). Com os scripts da VM e a listagem:
994 + 65. Com trocar senha: 1082 + 78. Com grupos: 1278 + 106
(`t13_grupos.sh` e a prova real `t13b_grupos_real.sh`). Com a reconexão
automática: 1303 + 116, com usuários e grupos de demonstração na VM (o
`t07` confere cada grupo comum real, então o total varia com eles). A VM
pode guardar dados de demonstração (nomes sem `dkt_`); os testes não
dependem de o servidor estar sem grupos (o `t09` cria o próprio). Com excluir
usuário: 1412 + 139 (`t14_excluir.sh` e a prova real `t14b_excluir_real.sh`).
Com a consistência: 1474 + 154 (`t15_consistencia.sh` e
`t15b_consistencia_real.sh`). Com a tarefa 2.0: 1505 + 162 (`t16_convidado.sh` e
`t16b_convidado_real.sh`). Com a tarefa 2.1: 1651 + 194 (`t17_compartilhar.sh` e
`t17b_compartilhar_real.sh`; pastas de teste em `/srv/dkt-teste.*`, que a
impressão digital do `run.sh` confere). Com um grupo só por
compartilhamento: 1658 + 188 (sem os casos de somente leitura; o `t17` usa
só as seções padrão da cópia do smb.conf, para os compartilhamentos de
demonstração não interferirem). Com a tarefa 2.2: 1794 + 225 (`t18_permissoes.sh` e
`t18b_permissoes_real.sh`). Com a tarefa 2.3: 1865 + 251 (`t19_remover.sh` e
`t19b_remover_real.sh`). Com a tarefa 2.4: 1967 + 279 (`t20_existentes.sh` e
`t20b_existentes_real.sh`, que escreve compartilhamentos à mão no smb.conf
real e o devolve idêntico). Com a tarefa 3.0: 2011 + 302 (`t21_log_auth.sh` e
`t21b_log_auth_real.sh`). Com a tarefa 3.1: 2058 + 326 (`t22_sessoes.sh` e
`t22b_sessoes_real.sh`). Os testes também acusam se alguém usar o debkit na VM enquanto rodam (o
log e a trava reais mudam): não usar o debkit durante a suíte.

Os testes funcionam com o servidor preparado ou não: em vez de exigir que
os arquivos reais do debkit não existam, conferem que não mudaram
(`estado_real`/`real_intacto` em `tests/lib.sh`).

**Cuidados aprendidos na Fase 0** (valem para as próximas tarefas):

- o sandbox dos testes precisa isolar TUDO que o debkit pode alterar
  (smb.conf, backups, grupo, `SSH_DROPIN`...): numa tarefa um teste chegou a
  criar o arquivo SSH real; daí nasceu a trava do `run.sh`;
- testar o comportamento real das ferramentas antes de codificar
  (ex.: `server role = auto`; `Include` depois de `Match` no SSH; o próprio
  `ufw allow` com o ufw inativo cria tabelas nft vazias);
- em operações sobre serviços sensíveis (SSH), validar antes de recarregar
  e desfazer só o que a operação realmente fez.

**Cuidados aprendidos na tarefa 1.0:**

- a cópia do `smb.conf` real no sandbox traz caminhos REAIS (o
  `include` antigo apontava para `/etc/samba/debkit-shares.conf`): a cópia
  agora sai sem essas linhas (`copiar_smb_conf`), e a ação só apaga o
  arquivo antigo se ele estiver na mesma pasta do `smb.conf` e tiver o
  cabeçalho do debkit - foi essa trava que protegeu o arquivo real quando
  um teste ainda copiava o `smb.conf` sem limpar;
- toda chave de configuração nova precisa ir também para a configuração da
  sandbox (`tests/lib.sh` e o `CFG` dos testes): um teste montava a
  configuração à mão sem `SMB_BACKUP_DIR` e criou `/etc/samba/conf-bkp`
  real (só com cópias do sandbox; apagada, e a pasta agora está na
  impressão digital do `run.sh`);
- rotação de backups com nomes reaproveitáveis: o nome liberado pela
  rotação voltava a ser usado e o backup novo era apagado logo depois de
  criado. Teste "o backup recém-criado existe" em toda rotação.

**Cuidados aprendidos na tarefa 1.1:**

- o sandbox não isolava o apt nem a base do dpkg: com o item novo
  de remover pacotes de domínio, um `--preparar` de teste respondendo "s"
  rodou o `apt-get purge` REAL (removeu os pacotes que já iam ser
  removidos, mas por um teste). Agora o sandbox usa um apt que recusa tudo
  (`DEBKIT_APT`) e uma base do dpkg vazia (`DEBKIT_DPKG_ADMIN`), e a
  impressão digital do `run.sh` inclui pacotes, PAM e `nsswitch.conf`.
  Regra: toda ação nova que mexa em algo do sistema precisa, junto, do
  isolamento no sandbox e de uma linha na impressão digital;
- a cópia do `smb.conf` no sandbox apontava a base de senhas REAL do Samba:
  agora `passdb backend` e as pastas de estado vão para o sandbox;
- no bash, `[a-z]` em pt_BR aceita letras acentuadas: listar as letras;
- `read -p` não mostra a pergunta quando a entrada não é um terminal:
  textos de pergunta se testam com `pty`.

**Cuidados aprendidos na tarefa de grupos:**

- um teste chegou a ter `gpasswd -M dkt_a daemon` (trocaria os membros do
  grupo de sistema `daemon`), pego na revisão antes de rodar: agora a
  impressão digital do `run.sh` inclui os grupos que não são `dkt_*`
  (`/etc/group` e `/etc/gshadow`) - qualquer mudança neles reprova;
- `groupdel` apaga grupo com membros sem avisar e `groupadd` aceita nomes
  como `Dkt.G`: as travas são do debkit;
- grupo comum citado no sudoers dá sudo a quem entra: fica fora das telas.
