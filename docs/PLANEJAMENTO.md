# gsb — Gerenciador Samba: planejamento

Documento vivo com as decisões do projeto e o porquê de cada uma.
Iniciado em 02/10/2026 por Thiago Carrere e Claude (Anthropic).

---

## 1. O que é (e o que não é)

**É** um gerenciador de **servidor de arquivos Samba** (modo *standalone*,
base de senhas `tdbsam`) para administradores Linux: usuários, grupos,
compartilhamentos, permissões de pasta e diagnóstico, por menu interativo ou
por comandos diretos.

**Não é** um controlador de domínio (Active Directory / Samba AD DC). Esse é
outro tipo de servidor; misturar os dois deixaria o gsb frágil.

## 2. Princípios (valem para todas as funções)

1. **Seguro por padrão** — nunca mexe em usuários/grupos de sistema nem em
   pastas do sistema; senha nunca aparece na tela, em log ou na linha de
   comando (vai sempre pela entrada padrão).
2. **Tudo ou nada** — cada operação valida tudo antes, mostra um resumo,
   pede UMA confirmação e, se algo falhar no meio, desfaz o que já fez.
3. **Idempotente** — repetir uma operação não estraga nada (ex.: aplicar a
   proteção SSH já aplicada só informa que já está ativa).
4. **Só mexe no que ele mesmo criou** — ver seção 4.
5. **Nada fixo do servidor no código** — o que der é detectado; o resto fica
   em `/etc/gsb/gsb.conf`, com padrões sensatos.
6. **Rastreável** — log de auditoria em `/var/log/gsb.log` (quem, quando,
   o quê; nunca senhas) e backup automático antes de qualquer alteração,
   com limpeza dos antigos.
7. **Uma execução por vez** — trava (`flock`) contra dois administradores
   alterando ao mesmo tempo.
8. **Sem dependências exóticas** — bash 4.4+, coreutils, ferramentas do
   Samba, shadow-utils (`useradd`, `chpasswd`), OpenSSH.

## 3. Segurança dos usuários do servidor de arquivos

Todo usuário criado pelo gsb:

- tem shell `nologin` e **não** tem pasta pessoal;
- tem a **mesma senha no Linux e no Samba** (mínimo configurável, padrão 4
  caracteres), e toda troca de senha é feita **nos dois juntos**;
- entra no grupo de proteção (`gsb_usuarios`), recusado por completo pelo
  SSH — inclusive túneis (`ssh -N -L`), que o `nologin` sozinho não impede
  quando o login por senha está ligado.

**Proteção SSH gerenciada pelo próprio gsb** (nada de editar o `sshd` à mão):

- arquivo próprio `/etc/ssh/sshd_config.d/gsb.conf` com
  `DenyGroups gsb_usuarios`; o `sshd_config` principal não é tocado;
- só aplica se o `sshd_config` inclui `sshd_config.d/*.conf` (padrão no
  Debian 11+); senão, avisa e não faz nada;
- valida com `sshd -t`, confere com `sshd -T` que a regra `denygroups` está
  em vigor e recarrega sem derrubar sessões abertas; se algo falhar, desfaz.
  (Nos testes, a recusa é provada com tentativa real de login.)

## 4. O gsb só gerencia o que ele cria

Decisão do projeto: o gsb **nunca** altera usuários, grupos ou
compartilhamentos que já existiam no servidor. Não existe função "adotar".

| | Como o gsb reconhece o que é dele | Consequência |
|---|---|---|
| Usuários | membros do grupo `gsb_usuarios` | trocar senha, desativar, remover etc. recusam qualquer outro |
| Grupos | prefixo próprio configurável (ex.: `gsb_vendas`) | só cria/altera/remove os seus |
| Compartilhamentos | ficam em `/etc/samba/gsb-shares.conf`, incluído no `smb.conf` por **uma** linha `include =` | os blocos do `smb.conf` do administrador nunca são editados; para desligar o gsb basta tirar essa linha |

O que não é do gsb aparece num **inventário somente leitura**.

## 5. Preparação inteligente do ambiente

"Robusto e inteligente" não é só detectar um problema e mandar o
administrador resolver: o gsb **prepara o ambiente** para funcionar. Se
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
(instalar pacotes, ativar o serviço do Samba, criar `/etc/gsb/gsb.conf`,
backups e log, criar o grupo `gsb_usuarios`, incluir a linha `include` no
`smb.conf`, aplicar a proteção SSH). Com "s", executa item por item,
conferindo cada um; se algo falhar, desfaz o que fez e explica. Nas
aberturas seguintes faz uma checagem rápida e oferece consertar o que tiver
"quebrado" (serviço parado, `include` removido...). Há também a opção de menu
**"Verificar e preparar o ambiente"**.

**Regras para qualquer mudança automática:**

- sempre pergunta antes e mostra exatamente o que vai fazer;
- instala só pelo gerenciador oficial (`apt-get`, sem perguntas
  interativas), espera se o apt estiver em uso por outro programa e, sem
  internet, explica sem deixar nada pela metade;
- registra tudo no log de auditoria;
- não mexe no que é do administrador além dos dois "ganchos" mínimos (a
  linha `include` e o arquivo próprio do SSH);
- firewall ativo bloqueando o Samba (porta 445): avisa e oferece liberar;
- fora do Debian / sem `apt`: não arrisca — lista os pacotes e explica.

**Desinstalação:** opção que remove tudo o que o gsb colocou no sistema
(linha `include`, arquivo do SSH, configuração), perguntando o que fazer com
os usuários e compartilhamentos que ele criou.

**Testes sem estragar o servidor de desenvolvimento:** `apt-get -s`
(simulação), comandos "faltando" simulados em ambiente controlado e
serviços parados com cuidado. Instalação do zero de verdade fica para uma
máquina limpa (VM).

## 6. Arquitetura

- **Um arquivo só** (`gsb.sh`), fácil de instalar e auditar, em seções:
  configuração → detecção do sistema → mensagens → utilitários → funções →
  menus → comandos diretos → início.
- **Dois modos de uso:** menu interativo e comandos diretos
  (ex.: `gsb usuario criar joao --grupos gsb_vendas`), que também permitem
  testes automáticos.
- **Distribuição:** foco em **Debian 12/13** (Ubuntu, derivado do Debian,
  tende a funcionar). O que muda entre distribuições (nomes de serviços,
  caminhos) fica isolado em um único ponto, para facilitar suporte futuro.
- **Idioma:** todas as mensagens num catálogo; português do Brasil é o
  padrão, preparado para inglês.

Estrutura do repositório:

```
/opt/gsb/
├── gsb.sh             # o programa
├── gsb.conf.exemplo   # configuração comentada
├── install.sh         # instala/atualiza (link em /usr/local/sbin/gsb)
├── tests/             # testes automáticos (usuários/shares descartáveis)
├── docs/              # planejamento e decisões
├── README.md  CHANGELOG.md  LICENSE (MIT)
```

## 7. Fases

| Fase | Conteúdo |
|---|---|
| 0. Fundação | 0.1 esqueleto (configuração, catálogo de mensagens, utilitários, trava, log, menu) ✔ · 0.2 detecção do ambiente ✔ · 0.3 preparação do ambiente, assistente de abertura (verifica a cada execução e oferece consertar) e backups ✔ · 0.4 proteção SSH · 0.5 firewall (ufw/firewalld: avisar e oferecer liberar a porta 445) |
| 1. Usuários | **criar** (item 1 do menu), listar, trocar senha (Linux + Samba), grupos, desativar/reativar, remover |
| 2. Compartilhamentos | criar, listar, permissões de pasta, remover; avaliar acesso somente leitura por grupo |
| 3. Diagnóstico | falhas de login, sessões ativas, saúde do Samba, consulta à auditoria, inventário somente leitura |
| 4. Publicação | comandos diretos completos, `install.sh`, **desinstalação**, README, mensagens em inglês, testes automáticos e CI |

## 8. Forma de trabalho

Uma função (ou tarefa) por vez:

1. implementar;
2. revisão séria, criteriosa e minuciosa;
3. testes de verdade cobrindo todas as situações possíveis, com dados
   descartáveis e limpeza ao final — sem tocar no que já existe no servidor;
4. só com tudo certo: commit (autor: Thiago Carrere; coautor: Claude).

Trabalho na branch `dev`; levar para a `main` é decisão do Thiago.

## 9. Herança do projeto swg

O gsb nasce da experiência do `swg` (menu Samba + WireGuard de uso interno).
Lições já aprendidas lá e que valem aqui:

- `smbpasswd` rodando como root **não** aplica o tamanho mínimo de senha;
- caminho relativo ou `/var/tmp`, `/var/www` etc. em operações recursivas
  podem quebrar o servidor — validar sempre (caminho completo, `realpath`,
  lista de pastas do sistema);
- `userdel -r` em usuário de sistema apaga pastas como `/var/backups` e
  `/var/www`;
- conferir o resultado real de cada operação (não confiar só no código de
  saída), e testar com login de verdade.
