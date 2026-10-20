#!/usr/bin/env bash
# Testes da correção dos pacotes de domínio: a preparação instala o Samba
# sem os "recomendados" e, num servidor independente, remove samba-ad-dc /
# winbind / libpam-winbind / libnss-winbind (que deixam o PAM aceitar a
# senha do Samba em logins como o SSH). Tudo simulado: apt falso, pacotes
# "instalados" em arquivos do sandbox, PAM e nsswitch.conf do sandbox. O apt
# real nunca é chamado.
source "$(dirname "$0")/lib.sh"
sandbox

# Pacotes "instalados" = arquivos em $SANDBOX/inst; o apt falso registra os
# argumentos, simula (-s) e remove (purge) - e, como os scripts reais dos
# pacotes, tira o winbind do PAM e do nsswitch.conf do sandbox.
mkdir -p "$SANDBOX/pam.d"
cat > "$SANDBOX/fake-apt" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_DIR/apt-args"
pkgs=(); for a in "$@"; do case "$a" in -*|purge|install|update) ;; *=*) ;; DPkg::*) ;; *) pkgs+=("$a") ;; esac; done
case " $* " in
    *" -s purge "*)
        [ -n "${FAKE_SIM_RC:-}" ] && exit "$FAKE_SIM_RC"
        for p in "${pkgs[@]}" ${FAKE_SIM_EXTRA:-}; do echo "Purg $p [1.0]"; done ;;
    *" purge "*)
        [ -n "${FAKE_PURGE_RC:-}" ] && { echo "E: falha simulada"; exit "$FAKE_PURGE_RC"; }
        for p in "${pkgs[@]}"; do rm -f "$FAKE_DIR/inst/$p"; done
        if [ -z "${FAKE_DEIXA_PAM:-}" ]; then
            sed -i '/pam_winbind/d' "$FAKE_DIR"/pam.d/common-*
            sed -i -r '/(passwd|group):/ s/[[:space:]]+winbind\b//' "$FAKE_DIR/nsswitch.conf"
        fi ;;
esac
exit 0
EOF
chmod 755 "$SANDBOX/fake-apt"

instalar_dominio() {
    rm -rf "$SANDBOX/inst"; mkdir -p "$SANDBOX/inst"
    for p in "$@"; do touch "$SANDBOX/inst/$p"; done
    printf 'auth\t[success=2 default=ignore]\tpam_unix.so nullok\nauth\t[success=1 default=ignore]\tpam_winbind.so krb5_auth try_first_pass\n' > "$SANDBOX/pam.d/common-auth"
    printf 'account\t[default=bad success=ok user_unknown=ignore]\tpam_winbind.so\n' > "$SANDBOX/pam.d/common-account"
    printf '# comentario pam_winbind\nsession optional pam_unix.so\n' > "$SANDBOX/pam.d/common-session"
    printf 'passwd:         files systemd winbind\ngroup:          files systemd winbind\nhosts:          files dns\n' > "$SANDBOX/nsswitch.conf"
    : > "$SANDBOX/apt-args"
}
SIM="export FAKE_DIR='$SANDBOX'; DEBKIT_APT='$SANDBOX/fake-apt'; DEBKIT_DIR_PAM='$SANDBOX/pam.d'; DEBKIT_ARQ_NSSWITCH='$SANDBOX/nsswitch.conf';
     debkit_pacote_instalado() { [ -e \"$SANDBOX/inst/\$1\" ]; };
     debkit_tem_comando() { case \"\$1\" in dpkg-query) return 0 ;; esac; command -v \"\$1\" >/dev/null; };"
d() { bash -c "source '$DEBKIT'; debkit_conf_carregar \"\$DEBKIT_CONF_ARQUIVO\" >/dev/null; $SIM $1" 2>&1; }
verif_plano() { d "${1:-} debkit_verificar_ambiente >/dev/null; printf '%s\n' \"\${DEBKIT_VERIF[@]}\" | grep '^samba'; debkit_montar_plano; echo \"PLANO=\${DEBKIT_PLANO[*]}\""; }
executar() { d "debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(${1:-samba_pacotes_dominio}); ${2:-} debkit_executar_plano; echo RC=\$?"; }

preparar_sandbox

# ── Instalação sem os recomendados ───────────────────────────────────────────
caso "instalação do Samba sem os pacotes recomendados"
instalar_dominio
d "debkit_tem_comando() { case \"\$1\" in smbd) return 1 ;; esac; command -v \"\$1\" >/dev/null; };
   debkit_verificar_ambiente >/dev/null; DEBKIT_PLANO=(pacotes); debkit_executar_plano" >/dev/null
contem "install -y --no-install-recommends samba" "$(cat "$SANDBOX/apt-args")"

# ── Detecção ─────────────────────────────────────────────────────────────────
caso "detecção: os 4 pacotes instalados num servidor independente"
instalar_dominio samba-ad-dc winbind libpam-winbind libnss-winbind
saida=$(verif_plano)
contem "Pacotes de domínio instalados sem necessidade num servidor independente: samba-ad-dc winbind libpam-winbind libnss-winbind" "$saida"
contem "samba_pacotes_dominio" "$(grep '^PLANO=' <<< "$saida")"
caso "detecção: só alguns instalados"
instalar_dominio winbind
saida=$(verif_plano)
contem "independente: winbind." "$saida"; contem "samba_pacotes_dominio" "$saida"
caso "detecção: nenhum instalado - nada no plano"
instalar_dominio
saida=$(verif_plano)
nao_contem "Pacotes de domínio" "$saida"; nao_contem "samba_pacotes_dominio" "$saida"
caso "detecção: servidor membro de domínio - não oferece remover (lá o winbind pode ser necessário)"
instalar_dominio winbind libpam-winbind
saida=$(verif_plano "debkit_samba_papel_efetivo() { echo 'member server'; };")
nao_contem "Pacotes de domínio" "$saida"; nao_contem "samba_pacotes_dominio" "$saida"
caso "detecção: fora do Debian - avisa, mas não entra no plano"
instalar_dominio winbind
printf 'ID=rocky\nID_LIKE="rhel fedora"\n' > "$SANDBOX/os-release"
saida=$(verif_plano "DEBKIT_ARQ_OS_RELEASE='$SANDBOX/os-release';")
contem "Pacotes de domínio" "$saida"; nao_contem "samba_pacotes_dominio" "$(grep '^PLANO=' <<< "$saida")"
caso "winbind no PAM/NSS: comentário não conta"
instalar_dominio
igual "PAM NSS" "$(d 'debkit_samba_winbind_no_sistema')"
sed -i '/pam_winbind/d' "$SANDBOX/pam.d/common-auth" "$SANDBOX/pam.d/common-account"
igual "NSS" "$(d 'debkit_samba_winbind_no_sistema')" "só o comentário sobrou no PAM"

# ── Remoção ──────────────────────────────────────────────────────────────────
caso "remoção: simula, remove e confere (PAM e NSS sem winbind, Samba de pé)"
instalar_dominio samba-ad-dc winbind libpam-winbind libnss-winbind
saida=$(executar)
contem "RC=0" "$saida"
args=$(cat "$SANDBOX/apt-args")
contem "-s purge samba-ad-dc winbind libpam-winbind libnss-winbind" "$args" "simulou antes"
contem "-o DPkg::Lock::Timeout=120 purge -y samba-ad-dc winbind libpam-winbind libnss-winbind" "$args" "purge com espera pelo apt"
igual "" "$(ls "$SANDBOX/inst")" "nenhum pacote de domínio instalado"
igual "" "$(d 'debkit_samba_winbind_no_sistema')" "winbind fora do PAM e do NSS"
contem "passwd:         files systemd" "$(cat "$SANDBOX/nsswitch.conf")" "o resto do nsswitch.conf fica"
contem "acao=samba_pacotes_dominio resultado=ok" "$(cat "$SANDBOX/debkit.log")" "auditoria"
caso "remoção: idempotente"
nao_contem "samba_pacotes_dominio" "$(verif_plano)"

caso "remoção: o apt removeria outro pacote junto - recusa sem remover nada"
instalar_dominio winbind libpam-winbind
saida=$(FAKE_SIM_EXTRA="samba" executar)
contem "RC=1" "$saida"; contem "removeria também outros pacotes (samba)" "$saida"
nao_contem " purge -y" "$(cat "$SANDBOX/apt-args")" "purge de verdade não foi chamado"
igual "libpam-winbind winbind" "$(ls "$SANDBOX/inst" | sort | tr '\n' ' ' | sed 's/ $//')" "nada removido"

caso "remoção: simulação falha - não remove nada"
instalar_dominio winbind
saida=$(FAKE_SIM_RC=100 executar)
contem "RC=1" "$saida"; contem "Não foi possível simular a remoção" "$saida"
nao_contem " purge -y" "$(cat "$SANDBOX/apt-args")"

caso "remoção: o purge falha - mostra o motivo"
instalar_dominio winbind
saida=$(FAKE_PURGE_RC=100 executar)
contem "RC=1" "$saida"; contem "A remoção falhou" "$saida"; contem "E: falha simulada" "$saida"

caso "remoção: winbind continua no PAM depois - a conferência acusa"
instalar_dominio winbind libpam-winbind
saida=$(FAKE_DEIXA_PAM=1 executar)
contem "RC=1" "$saida"; contem "winbind ainda no PAM NSS" "$saida"

caso "remoção: Samba parou depois - a conferência acusa"
instalar_dominio winbind
saida=$(executar samba_pacotes_dominio "DEBKIT_SVC_SAMBA=smbd; debkit_servico_ativo() { return 1; };")
contem "RC=1" "$saida"; contem "serviço smbd parado" "$saida"

caso "remoção feita e passo seguinte falha: avisa que os pacotes não voltam"
instalar_dominio winbind libpam-winbind
saida=$(executar "samba_pacotes_dominio grupo" "groupadd() { return 1; };")
contem "RC=1" "$saida"; contem "Os pacotes removidos não foram reinstalados: winbind libpam-winbind" "$saida"

caso "--preparar pela linha de comando (apt falso via ambiente)"
instalar_dominio winbind
# A linha de comando não aceita simulações por função: só confere que o
# item aparece no plano mostrado e que "n" não remove nada
saida=$(printf 'n\n' | bash -c "source '$DEBKIT'; $SIM main --preparar" 2>&1)
contem "Remover os pacotes de domínio desnecessários: winbind" "$saida"; contem "Nada foi alterado" "$saida"
igual "winbind" "$(ls "$SANDBOX/inst")" "nada removido"

# Regressão do incidente da 1.1: um --preparar de teste respondendo "s"
# chegou a remover os pacotes REAIS (o sandbox não isolava apt/dpkg). Agora a
# base do dpkg do sandbox diz "winbind instalado" e o apt do sandbox recusa:
# a tentativa fica anotada e nada real é tocado.
caso "sandbox: --preparar com 's' nunca chama o apt real"
printf 'Package: winbind\nStatus: install ok installed\nArchitecture: amd64\nVersion: 1:1.0\nMaintainer: x\nDescription: x\n' > "$SANDBOX/dpkg/status"
pac_antes=$(dpkg-query -W -f='${binary:Package}=${db:Status-Abbrev} ' samba winbind 2>/dev/null)
saida=$(printf 's\n' | bash "$DEBKIT" --preparar 2>&1); cod=$?
contem "Remover os pacotes de domínio desnecessários: winbind" "$saida" "a base do sandbox é a consultada"
igual 1 "$cod" "falha (apt bloqueado)"
contem "apt-get -s purge winbind" "$(cat "$SANDBOX/apt-bloqueado.log" 2>/dev/null)" "tentativa anotada no apt do sandbox"
igual "$pac_antes" "$(dpkg-query -W -f='${binary:Package}=${db:Status-Abbrev} ' samba winbind 2>/dev/null)" "pacotes reais iguais"
: > "$SANDBOX/dpkg/status"

real_intacto
resumo
