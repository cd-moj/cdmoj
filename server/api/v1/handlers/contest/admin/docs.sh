# GET/POST /contest/admin/docs?contest=<c>   (admin OU juiz-chefe)
# Documentos da prova: info sheet, caderno (com capa customizável) e folha de time limits,
# em HTML+PDF e nos dois idiomas. Ver lib/contest-docs.sh e docs/MANUAL-CONTEST.md.
#
# GET  -> {docs:[…], config:{…}, templates:{info_sheet_pt,info_sheet_en,cover_pt,cover_en},
#          cover_uploaded:{pt,en}, problems:[{letter,name,has_pdf,has_html}]}
# POST {action}:
#   config    {caderno_version?, cover_note?, errata?, info_sheet_pt?, info_sheet_en?,
#              cover_pt?, cover_en?}          — textos/campos editáveis
#   cover     {lang, pdf_b64}|{lang, remove:true}  — capa em PDF ENVIADO (vence a gerada)
#   generate  {types?:[…], langs?:[…]}        — default: todos os tipos, pt+en
#   publish   {type, lang, news?:bool}        — libera p/ cstaff/times (resources.json) e,
#                                               com news:true, cria a notícia com o PDF anexo
#   unpublish {type, lang}
require_auth_contest "$(param contest)"
contest="$(param contest)"
[[ -n "$contest" ]] || fail 400 "Missing contest" "contest_missing"
require_contest "$contest"
is_admin_or_chief || fail 403 "Apenas o admin ou o juiz-chefe" "admin_required"
source "$_DIR/lib/contest-create.sh"; source "$_DIR/lib/tl-store.sh"; source "$_DIR/lib/contest-docs.sh"

D="$(doc_dir "$contest")"

if [[ "$REQUEST_METHOD" == GET ]]; then
  probs="$(cc_probs_json "$contest")"
  probs="$(jq -c --arg c "$CONTESTSDIR/$contest" 'map(. + {
      has_pdf: false, has_html: false })' <<<"$probs")"
  # marca quais têm enunciado em PDF/HTML no contest (o caderno prefere o PDF)
  tmpp="$(mktemp)"; printf '%s' "$probs" > "$tmpp"
  n="$(jq -r 'length' "$tmpp")"; out='[]'
  for ((i=0; i<n; i++)); do
    sk="$(jq -r --argjson i "$i" '.[$i].statement_key // ""' "$tmpp")"
    hp=false; hh=false
    [[ -f "$CONTESTSDIR/$contest/enunciados/$sk.pdf" ]] && hp=true
    [[ -f "$CONTESTSDIR/$contest/enunciados/$sk.html" ]] && hh=true
    out="$(jq -c --argjson o "$out" --argjson i "$i" --argjson hp "$hp" --argjson hh "$hh" \
        '$o + [ (.[$i] + {has_pdf:$hp, has_html:$hh}) ]' "$tmpp")"
  done
  rm -f "$tmpp"
  tpl_pt="$(cat "$D/info-sheet.pt.md" 2>/dev/null || cat "$_DIR/../../etc/info-sheet.pt.md" 2>/dev/null)"
  tpl_en="$(cat "$D/info-sheet.en.md" 2>/dev/null || cat "$_DIR/../../etc/info-sheet.en.md" 2>/dev/null)"
  cov_pt="$(cat "$(doc_cover_md "$contest" pt)" 2>/dev/null)"
  cov_en="$(cat "$(doc_cover_md "$contest" en)" 2>/dev/null)"
  cup_pt=false; [[ -s "$(doc_cover_pdf "$contest" pt)" ]] && cup_pt=true
  cup_en=false; [[ -s "$(doc_cover_pdf "$contest" en)" ]] && cup_en=true
  body="$(jq -cn --argjson docs "$(doc_index "$contest")" --argjson cfg "$(doc_conf_get "$contest")" \
     --argjson probs "$out" --arg tp "$tpl_pt" --arg te "$tpl_en" --arg cp "$cov_pt" --arg ce "$cov_en" \
     --argjson up "$cup_pt" --argjson ue "$cup_en" \
     '{success:true, docs:$docs, config:$cfg, problems:$probs,
       templates:{info_sheet_pt:$tp, info_sheet_en:$te, cover_pt:$cp, cover_en:$ce},
       cover_uploaded:{pt:$up, en:$ue}}')"
  [[ -n "$body" ]] || fail 500 "Falha ao montar a resposta" "build_fail"
  emit_json 200 OK; printf '%s\n' "$body"; exit 0
fi

require_method POST
bodyf="$(read_body_file)"
jq -e . "$bodyf" >/dev/null 2>&1 || fail 400 "JSON inválido" "bad_json"
action="$(jq -r '.action // ""' "$bodyf")"
mkdir -p "$D" 2>/dev/null

case "$action" in
  config)
    cfg="$(doc_conf_get "$contest")"
    for k in caderno_version cover_note errata; do
      if jq -e --arg k "$k" 'has($k)' "$bodyf" >/dev/null 2>&1; then
        v="$(jq -r --arg k "$k" '.[$k] // ""' "$bodyf")"
        cfg="$(jq -c --arg k "$k" --arg v "$v" '.[$k] = $v' <<<"$cfg")"
      fi
    done
    printf '%s\n' "$cfg" > "$D/config.json.tmp" && mv -f "$D/config.json.tmp" "$D/config.json"
    # textos longos (templates) vão para arquivo próprio — nunca por --arg (ARG_MAX)
    for pair in "info_sheet_pt:info-sheet.pt.md" "info_sheet_en:info-sheet.en.md" \
                "cover_pt:cover.pt.md" "cover_en:cover.en.md"; do
      key="${pair%%:*}"; fn="${pair##*:}"
      if jq -e --arg k "$key" 'has($k)' "$bodyf" >/dev/null 2>&1; then
        jq -r --arg k "$key" '.[$k] // ""' "$bodyf" > "$D/$fn.tmp" && mv -f "$D/$fn.tmp" "$D/$fn"
        [[ -s "$D/$fn" ]] || rm -f "$D/$fn"       # vazio = volta ao default embarcado
      fi
    done
    audit_log_to "$contest" docs-config ""
    ok_json '{saved:true}'
    ;;
  cover)
    lang="$(jq -r '.lang // ""' "$bodyf")"; [[ "$lang" == pt || "$lang" == en ]] || fail 400 "lang deve ser pt|en" "lang_invalid"
    f="$(doc_cover_pdf "$contest" "$lang")"
    if jq -e '.remove == true' "$bodyf" >/dev/null 2>&1; then
      rm -f "$f"; audit_log_to "$contest" docs-cover "lang=$lang remove"; ok_json '{removed:true}'; exit 0
    fi
    jq -r '.pdf_b64 // ""' "$bodyf" | base64 -d > "$f.tmp" 2>/dev/null
    [[ -s "$f.tmp" ]] || { rm -f "$f.tmp"; fail 400 "PDF vazio ou inválido" "pdf_invalid"; }
    [[ "$(file -b --mime-type "$f.tmp" 2>/dev/null)" == application/pdf ]] \
      || { rm -f "$f.tmp"; fail 400 "O arquivo enviado não é um PDF" "pdf_invalid"; }
    mv -f "$f.tmp" "$f"
    audit_log_to "$contest" docs-cover "lang=$lang bytes=$(stat -c%s "$f" 2>/dev/null)"
    ok_json '{saved:true, bytes:$b}' --argjson b "$(stat -c%s "$f" 2>/dev/null || echo 0)"
    ;;
  generate)
    mapfile -t types < <(jq -r '(.types // ["info-sheet","contest","times"])[]' "$bodyf" 2>/dev/null)
    mapfile -t langs < <(jq -r '(.langs // ["pt","en"])[]' "$bodyf" 2>/dev/null)
    (( ${#types[@]} )) || types=(info-sheet contest times)
    (( ${#langs[@]} )) || langs=(pt en)
    done_list='[]'; failed='[]'
    for t in "${types[@]}"; do
      case "$t" in info-sheet|contest|times) ;; *) continue;; esac
      for l in "${langs[@]}"; do
        [[ "$l" == pt || "$l" == en ]] || continue
        if e="$(doc_build "$contest" "$t" "$l")" && [[ -n "$e" ]]; then
          doc_index_upsert "$contest" "$e"
          done_list="$(jq -c --argjson d "$done_list" --argjson e "$e" '$d + [$e]' <<<'null')"
        else
          failed="$(jq -c --argjson f "$failed" --arg t "$t" --arg l "$l" '$f + [{type:$t, lang:$l}]' <<<'null')"
        fi
      done
    done
    audit_log_to "$contest" docs-generate "types=${types[*]} langs=${langs[*]}"
    ok_json '{generated:$d, failed:$f, counts:{ok:($d|length), fail:($f|length)}}' \
      --argjson d "$done_list" --argjson f "$failed"
    ;;
  publish|unpublish)
    t="$(jq -r '.type // ""' "$bodyf")"; l="$(jq -r '.lang // ""' "$bodyf")"
    case "$t" in info-sheet|contest|times) ;; *) fail 400 "type inválido" "type_invalid";; esac
    [[ "$l" == pt || "$l" == en ]] || fail 400 "lang deve ser pt|en" "lang_invalid"
    key="$t.$l"
    cfg="$(doc_conf_get "$contest")"
    if [[ "$action" == publish ]]; then
      [[ -s "$(doc_file "$contest" "$t" "$l" pdf)" || -s "$(doc_file "$contest" "$t" "$l" html)" ]] \
        || fail 409 "Gere o documento antes de publicar" "not_generated"
      cfg="$(jq -c --arg k "$key" '.published = ((.published // []) + [$k] | unique)' <<<"$cfg")"
    else
      cfg="$(jq -c --arg k "$key" '.published = ((.published // []) | map(select(. != $k)))' <<<"$cfg")"
    fi
    printf '%s\n' "$cfg" > "$D/config.json.tmp" && mv -f "$D/config.json.tmp" "$D/config.json"

    # seção "Prova" do contest (resources.json): leitor já existe em /contest/resources
    res="$CONTESTSDIR/$contest/resources.json"; [[ -s "$res" ]] || printf '[]' > "$res"
    label="$(_doc_t "$l" session)"
    case "$t" in info-sheet) label="$([[ "$l" == pt ]] && printf 'Informações do ambiente' || printf 'Testing environment')";;
                 times)      label="$(_doc_t "$l" times_title)";;
                 contest)    label="$(_doc_t "$l" session)";; esac
    url="/api/v1/contest/doc?contest=$contest&type=$t&lang=$l&fmt=pdf"
    if [[ "$action" == publish ]]; then
      jq -c --arg lb "$label ($l)" --arg u "$url" \
        '(map(select(.url != $u))) + [{label:$lb, url:$u}]' "$res" > "$res.tmp" && mv -f "$res.tmp" "$res"
    else
      jq -c --arg u "$url" 'map(select(.url != $u))' "$res" > "$res.tmp" && mv -f "$res.tmp" "$res"
    fi

    # notícia com o PDF anexado (opcional) — reusa o formato de news.json/news-files
    news_created=false
    if [[ "$action" == publish ]] && jq -e '.news == true' "$bodyf" >/dev/null 2>&1; then
      pdf="$(doc_file "$contest" "$t" "$l" pdf)"
      if [[ -s "$pdf" ]]; then
        nid="$(printf '%s%s%s' "$contest" "$EPOCHSECONDS" "$RANDOM" | md5sum | cut -c1-32)"
        nf="$CONTESTSDIR/$contest/news-files/$nid"; mkdir -p "$nf" 2>/dev/null
        fname="$t.$l.pdf"; cp -f "$pdf" "$nf/$fname"
        nj="$CONTESTSDIR/$contest/news.json"; [[ -s "$nj" ]] || printf '[]' > "$nj"
        jq -c --arg id "$nid" --arg ti "$label" --arg tx "$([[ "$l" == pt ]] && printf 'Documento da prova disponível para download.' || printf 'Contest document available for download.')" \
           --arg fn "$fname" --argjson sz "$(stat -c%s "$nf/$fname" 2>/dev/null || echo 0)" --argjson dt "$EPOCHSECONDS" \
           '. + [{id:$id, title:$ti, text:$tx, date:$dt, file:{name:$fn, size:$sz}}]' "$nj" > "$nj.tmp" \
          && mv -f "$nj.tmp" "$nj" && news_created=true
      fi
    fi
    audit_log_to "$contest" "docs-$action" "type=$t lang=$l news=$news_created"
    ok_json '{ok:true, published:($cfgp), news:$n}' \
      --argjson cfgp "$(jq -c '.published // []' <<<"$cfg")" --argjson n "$news_created"
    ;;
  *) fail 400 "action inválida" "action_invalid";;
esac
