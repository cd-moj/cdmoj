# lib/users-convert.sh — CONVERTER um contest COMPARTILHADO (USERS_FROM, contas do Treino Livre) em contas
# PRÓPRIAS do contest. (28/09/2026 — relato: "criar com usuários compartilhados não dá para desfazer e nada
# avisa; é catastrófico para provas".)
#
# Decisões do Ribas: a qualquer momento (antes da prova: confirmação simples; durante/depois: o id do
# contest digitado), com PRÉVIA; senha NOVA (nunca a do treino — o incidente de 18/08 vazou senhas do
# treino por etiqueta); histórico preservado; cada TIME vira UMA conta (o `time-<slug>`, senha única) e os
# membros deixam de entrar com as contas individuais.
#
# Invariantes:
#   I1 a população sai SÓ do que existe no contest — dirs em users/, o roster, as SESSÕES VIVAS e o
#      var/access.log — e cada candidato é conferido na fonte POR CAMINHO. Nunca varrer o treino.
#      As sessões vivas são fonte PRIMÁRIA: quem está logado e ainda não submeteu levaria 401 na próxima
#      requisição depois da conversão (a conta dele deixa de existir p/ o contest) e não conseguiria voltar.
#   I2 senha só aparece na resposta que a gerou (releitura: /contest/badges, como qualquer conta própria).
#   I3 da fonte só se copia `fullname`.
#   I4 toda linha do placar continua (membro de time com history vira conta local DESABILITADA — a linha
#      fica, o login não). Linha NOVA só entra zerada, p/ quem ganha conta sem ter dir (veio da sessão ou
#      do access.log) — como em qualquer contest de contas próprias; a prévia conta (new_scoreboard_rows).
#   I5 nada é gravado na prévia; o PONTO DE COMMIT é tirar USERS_FROM do conf (depois dele só vêm a
#      varredura dos atrasados, as sessões e o resumo). Com var/users-convert.pending presente e
#      USERS_FROM ainda no conf, repetir completa o que faltou: conta já convertida não ganha outra
#      senha e sai na resposta como `resumed` (a senha dela está nas etiquetas).
# CUSTO: nada de processo POR CONTA — a classificação usa arrays associativos (builtins) e a escrita vai
# em lote (um jq p/ as contas novas, um xargs jq p/ as que já existem). Medido no smoke: 2000 contas.
#
#   uc_collect <c> <work>                 -> <work>/{ind,teams,memhist,memlost,orphan,admin,names,resumed}.tsv
#   uc_plan_id <work> <c>                 -> id da prévia (muda se a população ou o conf mudarem)
#   uc_report  <c> <work>                 -> JSON da prévia (contagens, amostras, avisos em códigos)
#   uc_apply   <c> <work> <logout 0|1>    -> grava; credenciais em <work>/creds.jsonl; ecoa "sessões\tarquivo"

UC_ROLE_RE='\.(admin|judge|cjudge|staff|cstaff|mon|animeitor)$'

_uc_genpass_n(){  # <n> — N senhas legíveis (palavra + 4 dígitos), um shuf só
  local n="$1" wl="${PASSWORD_WORDLIST:-}"
  if [[ -s "$wl" ]]; then
    shuf -rn "$n" "$wl" 2>/dev/null | tr -cd 'a-z0-9\n' \
      | awk -v s="$RANDOM$BASHPID" 'BEGIN{srand(s)} {w=$0; if (w == "") w = "moj"; printf "%s%04d\n", w, int(rand()*10000)}'
  else
    head -c $(( n * 8 + 64 )) /dev/urandom | base64 -w0 | tr -dc 'a-z0-9' | fold -w6 | head -n "$n" \
      | awk -v s="$RANDOM$BASHPID" 'BEGIN{srand(s)} {printf "%s%04d\n", $0, int(rand()*10000)}'
  fi
}

uc_collect(){
  local c="$1" w="$2" src d sd reg al l orig team lp
  src="$(_users_source "$c")"; [[ "$src" != "$c" ]] || return 1
  d="$CONTESTSDIR/$c/users"; sd="$CONTESTSDIR/$src/users"; reg="$CONTESTSDIR/$c/registrations.json"
  mkdir -p "$w"; : > "$w/cand"
  # roster: times (login, nome, membros)
  if [[ -s "$reg" ]]; then
    jq -r '(.teams // {}) | to_entries[] | [.key, ((.value.name // .key) | gsub("[\t\n\r]"; " ")), ((.value.members // []) | join(","))] | join("\t")' \
      "$reg" 2>/dev/null > "$w/teams.tsv"
  else : > "$w/teams.tsv"; fi
  # contas locais: login (o do DIR quando o campo falta — ele é implícito no store), tem senha?, tipo da
  # conversão (vazio = nunca convertida)
  find "$d" -mindepth 2 -maxdepth 2 -name account.json -print0 2>/dev/null \
    | xargs -0 -r jq -r '[(if (.login // "") == "" then (input_filename | split("/") | .[-2]) else .login end),
                          (((.password // "") != "") | tostring),
                          (if .converted_at != null then (.converted_kind // "individual") else "" end)] | join("\t")' 2>/dev/null \
    > "$w/local.tsv"
  # fontes da população (I1): dirs, sessões vivas, access.log, roster
  find "$d" -mindepth 1 -maxdepth 1 -type d -printf '%f\td\n' 2>/dev/null >> "$w/cand"
  declare -F sess_files_of >/dev/null || source "$_LIBDIR/session-index.sh"
  sess_files_of "$c" | xargs -0 -r grep -h '^LOGIN=' 2>/dev/null | sed "s/^LOGIN=//; s/'//g" | awk 'NF{print $0"\ts"}' >> "$w/cand"
  [[ -s "$CONTESTSDIR/$c/var/access.log" ]] && cut -f2 "$CONTESTSDIR/$c/var/access.log" | sort -u | awk 'NF{print $0"\ta"}' >> "$w/cand"
  # o roster: inscrito individual e membro de time (quem entra pelo alias do time nem sempre tem dir)
  [[ -s "$reg" ]] && jq -r '(.entries // {}) | keys[] | . + "\tr"' "$reg" 2>/dev/null >> "$w/cand"
  awk -F'\t' '{o[$1]=o[$1] $2} END{for (l in o) print l"\t"o[l]}' "$w/cand" | sort > "$w/cand.agg"
  # classificação em memória (builtins — sem processo por login)
  local -A LP=() TK=() MO=() CV=()
  while IFS=$'\t' read -r l lp orig; do [[ -n "$l" ]] && { LP[$l]="$lp"; CV[$l]="$orig"; }; done < "$w/local.tsv"
  while IFS=$'\t' read -r l _ orig; do
    [[ -n "$l" ]] || continue; TK[$l]=1
    local m; IFS=',' read -ra _uc_m <<<"$orig"; for m in "${_uc_m[@]}"; do [[ -n "$m" ]] && MO[$m]="$l"; done
  done < "$w/teams.tsv"
  : > "$w/ind.tsv"; : > "$w/memhist.tsv"; : > "$w/memlost.tsv"; : > "$w/orphan.tsv"; : > "$w/resumed.tsv"
  for l in "${!TK[@]}"; do [[ -n "${CV[$l]:-}" ]] && printf '%s\t%s\n' "$l" "${CV[$l]}" >> "$w/resumed.tsv"; done
  while IFS=$'\t' read -r l orig; do
    valid_id "$l" || continue
    [[ "$l" =~ $UC_ROLE_RE ]] && continue
    [[ -n "${TK[$l]:-}" ]] && continue                          # time: vai pelo teams.tsv
    if [[ "${LP[$l]:-}" == true ]]; then                          # já tem senha local (conta própria, bloqueio)
      [[ -n "${CV[$l]:-}" ]] && printf '%s\t%s\n' "$l" "${CV[$l]}" >> "$w/resumed.tsv"   # (retomada)
      continue
    fi
    team="${MO[$l]:-}"
    if [[ -n "$team" ]]; then
      if [[ -s "$d/$l/history" ]]; then printf '%s\t%s\n' "$l" "$team" >> "$w/memhist.tsv"
      else printf '%s\t%s\n' "$l" "$team" >> "$w/memlost.tsv"; fi
      continue
    fi
    if [[ -f "$sd/$l/account.json" ]]; then
      printf '%s\t%s\n' "$l" "$orig" >> "$w/ind.tsv"
    else
      printf '%s\t%s\n' "$l" "$orig" >> "$w/orphan.tsv"        # sem conta na fonte: nada a converter
    fi
  done < "$w/cand.agg"
  # admin: o do treino que administra (SHARED_ADMIN/derivado) ganha conta LOCAL se ainda não tem uma com senha
  al="$(shared_admin_login "$c")"; : > "$w/admin.tsv"
  if [[ -n "$al" ]] && valid_id "$al" && [[ "${LP[$al]:-}" != true ]]; then printf '%s\n' "$al" > "$w/admin.tsv"; fi
  # nomes: só da fonte, por caminho (I3)
  { cut -f1 "$w/ind.tsv"; cut -f1 "$w/memhist.tsv"; cat "$w/admin.tsv"; } | while IFS= read -r l; do
    [[ -f "$sd/$l/account.json" ]] && printf '%s\0' "$sd/$l/account.json"
  done | xargs -0 -r jq -r '[(.login // ""), ((.fullname // "") | gsub("[\t\n\r]"; " "))] | join("\t")' 2>/dev/null > "$w/names.tsv"
  # já convertidos (retomada)
  awk -F'\t' '$3!=""{print $1}' "$w/local.tsv" > "$w/done.txt"
  return 0
}

uc_plan_id(){  # <work> <c>
  { cat "$1/ind.tsv" "$1/teams.tsv" "$1/memhist.tsv" "$1/admin.tsv" 2>/dev/null
    stat -c %Y "$CONTESTSDIR/$2/conf" 2>/dev/null; } | sha1sum | cut -c1-16
}

uc_report(){
  local c="$1" w="$2" phase sess superad reg_on=false pid src
  declare -F contest_phase >/dev/null || source "$_LIBDIR/contest-gate.sh"
  phase="$(contest_phase "$c")"
  declare -F sess_files_of >/dev/null || source "$_LIBDIR/session-index.sh"
  sess="$(sess_files_of "$c" | tr -cd '\0' | wc -c)"
  src="$(_users_source "$c")"; superad="$(conf_value "$src" SUPERADMINS)"; superad="${superad//\\/}"
  [[ -s "$CONTESTSDIR/$c/registrations.json" ]] && reg_on=true
  pid="$(uc_plan_id "$w" "$c")"
  jq -n --arg c "$c" --arg phase "$phase" --argjson sess "${sess:-0}" --arg pid "$pid" \
        --argjson reg "$reg_on" --arg superad "$superad" \
        --rawfile ind "$w/ind.tsv" --rawfile teams "$w/teams.tsv" --rawfile mh "$w/memhist.tsv" \
        --rawfile ml "$w/memlost.tsv" --rawfile orph "$w/orphan.tsv" --rawfile adm "$w/admin.tsv" \
        --rawfile res "$w/resumed.tsv" '
    def rows($s): $s | split("\n") | map(select(length > 0) | split("\t"));
    (rows($ind)) as $I | (rows($teams)) as $T | (rows($mh)) as $MH | (rows($ml)) as $ML | (rows($orph)) as $O
    | (rows($res)) as $R
    | ($adm | gsub("\n"; "")) as $A
    | {contest:$c, phase:$phase, plan_id:$pid, sessions_live:$sess, registration:$reg,
       counts:{individuals:($I|length), teams:($T|length), members_with_history:($MH|length),
               members_losing_login:($ML|length), orphans:($O|length), admin_created:($A != ""),
               new_scoreboard_rows:([$I[] | select(.[1] | test("d") | not)] | length),
               resumed:($R|length),
               from:{dir:([$I[] | select(.[1] | test("d"))] | length),
                     session:([$I[] | select(.[1] | test("s"))] | length),
                     access_log:([$I[] | select(.[1] | test("a"))] | length),
                     registration:([$I[] | select(.[1] | test("r"))] | length)}},
       samples:{individuals:([$I[] | .[0]] | .[0:50]),
                teams:([$T[] | {login:.[0], name:.[1], members:(.[2] | split(","))}] | .[0:50]),
                members_with_history:([$MH[] | {login:.[0], team:.[1]}] | .[0:50]),
                members_losing_login:([$ML[] | {login:.[0], team:.[1]}] | .[0:50])},
       admin:(if $A != "" then $A else null end),
       warnings:([ (if $phase != "before" then "live" else empty end),
                   (if ($T|length) > 0 then "team_members_lose_login" else empty end),
                   (if ($MH|length) > 0 then "member_history_disabled" else empty end),
                   (if ([$I[] | select(.[1] | test("d") | not)] | length) > 0 then "new_scoreboard_rows" else empty end),
                   "never_entered_excluded",
                   (if $reg then "registration_closes" else empty end),
                   (if ($superad | length) > 0 then "superadmins_lose_access" else empty end),
                   (if $A != "" then "admin_local_created" else empty end) ])}'
}

# uc_apply <c> <work> <logout_all> — PRÉ: uc_collect fresco; o chamador segura os locks.
uc_apply(){
  local c="$1" w="$2" logout="${3:-0}" d="$CONTESTSDIR/$1/users" src t="$EPOCHSECONDS" n l k team name pw
  src="$(_users_source "$c")"; [[ "$src" != "$c" ]] || return 1
  touch "$CONTESTSDIR/$c/var/users-convert.pending"
  local -A NM=() DONE=()
  while IFS=$'\t' read -r l name; do [[ -n "$l" ]] && NM[$l]="$name"; done < "$w/names.tsv"
  while IFS= read -r l; do [[ -n "$l" ]] && DONE[$l]=1; done < "$w/done.txt"
  n=$(( $(wc -l < "$w/ind.tsv") + $(wc -l < "$w/teams.tsv") + $(wc -l < "$w/admin.tsv") + 5 ))
  _uc_genpass_n "$n" > "$w/pw"
  # o PLANO: login \t senha \t nome \t tipo \t time — já convertido (retomada) não entra (I2)
  : > "$w/plan.tsv"     # resumed.tsv: a coleta já pôs as contas; os times retomados entram abaixo
  {
    exec {UCP}< "$w/pw"
    while IFS=$'\t' read -r l _; do
      [[ -n "$l" ]] || continue
      [[ -n "${DONE[$l]:-}" ]] && continue
      IFS= read -r pw <&"$UCP"; printf '%s\t%s\t%s\tindividual\t\n' "$l" "$pw" "${NM[$l]:-$l}"
    done < "$w/ind.tsv"
    while IFS=$'\t' read -r team name _; do
      [[ -n "$team" ]] || continue
      [[ -n "${DONE[$team]:-}" ]] && continue                    # retomada: a coleta já listou
      IFS= read -r pw <&"$UCP"; printf '%s\t%s\t%s\tteam\t\n' "$team" "$pw" "$name"
    done < "$w/teams.tsv"
    while IFS=$'\t' read -r l team; do
      [[ -n "$l" ]] || continue
      printf '%s\t!%s\t%s\tmember_disabled\t%s\n' "$l" "$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12)" "${NM[$l]:-$l}" "$team"
    done < "$w/memhist.tsv"
    if [[ -s "$w/admin.tsv" ]]; then
      l="$(head -1 "$w/admin.tsv")"; IFS= read -r pw <&"$UCP"; printf '%s\t%s\t%s\tadmin\t\n' "$l" "$pw" "${NM[$l]:-$l}"
    fi
    exec {UCP}<&-
  } > "$w/plan.tsv"
  # time do roster sem conta materializada (raro): materializa antes (o apply só reescreve a senha)
  while IFS=$'\t' read -r team _; do
    [[ -n "$team" && ! -f "$d/$team/account.json" ]] && declare -F reg_materialize_team >/dev/null && reg_materialize_team "$c" "$team"
  done < "$w/teams.tsv"
  # dirs + history (sem zerar nenhum) em lote
  cut -f1 "$w/plan.tsv" | while IFS= read -r l; do printf '%s\0%s\0%s\0' "$d/$l/submissions" "$d/$l/mojlog" "$d/$l/results"; done \
    | xargs -0 -r mkdir -p 2>/dev/null
  cut -f1 "$w/plan.tsv" | while IFS= read -r l; do [[ -f "$d/$l/history" ]] || : > "$d/$l/history"; done
  # contas NOVAS: um jq p/ todas (login \t json)
  : > "$w/new.tsv"; : > "$w/upd.tsv"
  while IFS=$'\t' read -r l _; do
    [[ -f "$d/$l/account.json" ]] && printf '%s\n' "$l" >> "$w/upd.tsv" || printf '%s\n' "$l" >> "$w/new.tsv"
  done < "$w/plan.tsv"
  jq -Rnr --arg src "$src" --argjson t "$t" --rawfile new "$w/new.tsv" '
      ($new | split("\n") | map(select(length > 0)) | map({(.):true}) | add // {}) as $N
      | inputs | split("\t") | select($N[.[0]])
      | "\(.[0])\t" + ({login:.[0], password:.[1], fullname:.[2], email:"", created_at:$t, updated_at:$t,
                        status:"active", uname_changes:[], converted_from:$src, converted_at:$t, converted_kind:.[3]}
                       + (if .[4] != "" then {converted_member_of:.[4]} else {} end) | tojson)' \
    < "$w/plan.tsv" > "$w/new.json.tsv"
  # contas que JÁ existem (overlay de inscrição, time materializado): um xargs jq com o plano por arquivo
  jq -Rn '[inputs | split("\t") | {key:.[0], value:{p:.[1], k:.[3], tm:.[4]}}] | from_entries' < "$w/plan.tsv" > "$w/plan.map.json"
  while IFS= read -r l; do printf '%s\0' "$d/$l/account.json"; done < "$w/upd.tsv" \
    | xargs -0 -r jq -r --slurpfile M "$w/plan.map.json" --arg src "$src" --argjson t "$t" '
        (if (.login // "") == "" then (input_filename | split("/") | .[-2]) else .login end) as $l
        | ($M[0][$l]) as $m | select($m != null)
        | "\($l)\t" + (.login = $l | .password = $m.p | del(.shared_overlay) | .converted_from = $src | .converted_at = $t
                           | .converted_kind = $m.k | .updated_at = $t
                           | (if $m.tm != "" then .converted_member_of = $m.tm else . end) | tojson)' \
      > "$w/upd.json.tsv" 2>/dev/null
  local j
  cat "$w/new.json.tsv" "$w/upd.json.tsv" | while IFS=$'\t' read -r l j; do
    [[ -n "$l" && -n "$j" ]] || continue
    printf '%s\n' "$j" > "$d/$l/account.json.tmp" && mv -f "$d/$l/account.json.tmp" "$d/$l/account.json"
  done
  # inscrição: o roster é arquivado — o gate barraria o login direto do time (reg_kind_of(time-*) = none),
  # e ela só existe p/ contas do treino
  local arch=""
  if [[ -f "$CONTESTSDIR/$c/registrations.json" ]]; then
    arch="var/registrations.converted-$t.json"
    mv -f "$CONTESTSDIR/$c/registrations.json" "$CONTESTSDIR/$c/$arch"
  fi
  # PONTO DE COMMIT (I5): daqui em diante o contest é de contas próprias
  declare -F cc_del_conf_var >/dev/null || source "$_LIBDIR/contest-create.sh"
  cc_del_conf_var "$c" SHARED_ADMIN; cc_del_conf_var "$c" USERS_FROM
  # a inscrição usa as contas do treino (pré-requisito do módulo, lib/modules.sh): sem elas, o módulo DESLIGA junto — o
  # roster já foi arquivado acima; ligado, gravar a janela de novo recriaria um roster que barra todo aluno (07/10/2026)
  local moff=""
  declare -F mod_on >/dev/null || source "$_LIBDIR/modules.sh"
  if mod_on "$c" inscricoes; then
    local _ucm=",$(mod_raw "$c"),"; _ucm="${_ucm//,inscricoes,/,}"; mod_set "$c" "$_ucm"; moff="inscricoes"
  fi
  # credenciais (a resposta): o plano + os retomados (sem senha) + os atrasados (dir criado pelo /submit
  # entre a coleta e o commit — ganham conta agora)
  jq -Rc 'split("\t") | {login:.[0], fullname:.[2], kind:.[3]}
          + (if .[3] == "member_disabled" then {team:.[4]} else {password:.[1]} end)' < "$w/plan.tsv" > "$w/creds.jsonl"
  awk -F'\t' 'NF{printf "{\"login\":\"%s\",\"kind\":\"%s\",\"resumed\":true}\n", $1, $2}' "$w/resumed.tsv" >> "$w/creds.jsonl"
  local late; local -A MEM=()
  while IFS=$'\t' read -r _ _ l; do local m; IFS=',' read -ra _uc_m <<<"$l"; for m in "${_uc_m[@]}"; do [[ -n "$m" ]] && MEM[$m]=1; done; done < "$w/teams.tsv"
  while IFS= read -r late; do
    [[ -f "$d/$late/account.json" || -n "${MEM[$late]:-}" ]] && continue     # membro de time: entra pelo time
    valid_id "$late" && ! [[ "$late" =~ $UC_ROLE_RE ]] && [[ -f "$CONTESTSDIR/$src/users/$late/account.json" ]] || continue
    pw="$(_uc_genpass_n 1)"; name="$(jq -r '.fullname // ""' "$CONTESTSDIR/$src/users/$late/account.json" 2>/dev/null)"
    jq -cn --arg l "$late" --arg p "$pw" --arg n "${name:-$late}" --arg src "$src" --argjson t "$t" \
      '{login:$l, password:$p, fullname:$n, email:"", created_at:$t, updated_at:$t, status:"active", uname_changes:[],
        converted_from:$src, converted_at:$t, converted_kind:"individual"}' > "$d/$late/account.json"
    jq -cn --arg l "$late" --arg p "$pw" --arg n "${name:-$late}" '{login:$l, password:$p, fullname:$n, kind:"individual", late:true}' >> "$w/creds.jsonl"
  done < <(find "$d" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null)
  # sessões: MANTIDAS (o login não muda; a conta passou a ser local). logout_all derruba as de não-papel.
  local nsess=0
  if [[ "$logout" == 1 ]]; then
    mapfile -t _uc_lg < <(jq -r 'select(.kind == "individual" or .kind == "team") | .login' "$w/creds.jsonl")
    (( ${#_uc_lg[@]} )) && nsess="$(remove_contest_sessions "$c" "${_uc_lg[@]}")"
  fi
  rm -f "$CONTESTSDIR/$c/var/users-convert.pending"
  jq -c 'del(.password)' "$w/creds.jsonl" | jq -cs . > "$w/creds.nopw.json"
  jq -cn --arg by "${SESSION_LOGIN:-}" --argjson t "$t" --arg src "$src" --arg arch "$arch" --argjson ns "${nsess:-0}" \
     --arg moff "$moff" --slurpfile cr "$w/creds.nopw.json" \
     '{converted_at:$t, by:$by, from:$src, registrations_archived:(if $arch != "" then $arch else null end),
       modules_off:(if $moff != "" then [$moff] else [] end), sessions_removed:$ns, accounts:$cr[0]}' > "$CONTESTSDIR/$c/var/users-convert.json"
  declare -F _score_dirty >/dev/null && _score_dirty "$c"
  declare -F score_kick_rebuild >/dev/null && score_kick_rebuild "$c" >/dev/null 2>&1
  # separador \x1f (não é "espaço" p/ o IFS): com TAB, campo vazio no meio colapsava e os campos trocavam de lugar
  printf '%s\x1f%s\x1f%s' "${nsess:-0}" "$arch" "$moff"
}
