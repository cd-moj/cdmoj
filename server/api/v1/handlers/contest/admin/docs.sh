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
  # templates e capas POR IDIOMA (mapa — pt/en/es; as chaves planas antigas continuam saindo
  # para não quebrar cliente velho). ⚠ template é texto livre do admin: vai por --rawfile
  # (arquivo), NUNCA por --arg — acima de 128 KiB o jq recusaria e a aba inteira morria.
  tmap='{}'; cmap='{}'; umap='{}'
  for L in $DOC_LANGS; do
    tf="$D/info-sheet.$L.md"; [[ -s "$tf" ]] || tf="$_DIR/../../etc/info-sheet.$L.md"
    [[ -s "$tf" ]] || tf=/dev/null
    tmap="$(jq -c --arg l "$L" --rawfile v "$tf" '.[$l] = $v' <<<"$tmap")"
    cf="$(doc_cover_md "$contest" "$L")"; [[ -s "$cf" ]] || cf=/dev/null
    cmap="$(jq -c --arg l "$L" --rawfile v "$cf" '.[$l] = $v' <<<"$cmap")"
    cu=false; [[ -s "$(doc_cover_pdf "$contest" "$L")" ]] && cu=true
    umap="$(jq -c --arg l "$L" --argjson v "$cu" '.[$l] = $v' <<<"$umap")"
  done
  body="$(jq -cn --argjson docs "$(doc_index "$contest")" --argjson cfg "$(doc_conf_get "$contest")" \
     --argjson probs "$out" --argjson tm "$tmap" --argjson cm "$cmap" --argjson um "$umap" \
     --arg langs "$DOC_LANGS" \
     '{success:true, docs:$docs, config:$cfg, problems:$probs, langs:($langs | split(" ")),
       templates:({info_sheet_pt:($tm.pt // ""), info_sheet_en:($tm.en // ""),
                   cover_pt:($cm.pt // ""), cover_en:($cm.en // "")}
                  + {info_sheet:$tm, cover:$cm}),
       cover_uploaded:$um}')"
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
    for k in caderno_version cover_note errata editorial_note; do
      if jq -e --arg k "$k" 'has($k)' "$bodyf" >/dev/null 2>&1; then
        v="$(jq -r --arg k "$k" '.[$k] // ""' "$bodyf")"
        cfg="$(jq -c --arg k "$k" --arg v "$v" '.[$k] = $v' <<<"$cfg")"
      fi
    done
    printf '%s\n' "$cfg" > "$D/config.json.tmp" && mv -f "$D/config.json.tmp" "$D/config.json"
    # textos longos (templates) vão para arquivo próprio — nunca por --arg (ARG_MAX)
    pairs=(); for L in $DOC_LANGS; do pairs+=( "info_sheet_$L:info-sheet.$L.md" "cover_$L:cover.$L.md" ); done
    for pair in "${pairs[@]}"; do
      key="${pair%%:*}"; fn="${pair##*:}"
      if jq -e --arg k "$key" 'has($k)' "$bodyf" >/dev/null 2>&1; then
        jq -r --arg k "$key" '.[$k] // ""' "$bodyf" > "$D/$fn.tmp" && mv -f "$D/$fn.tmp" "$D/$fn"
        [[ -s "$D/$fn" ]] || rm -f "$D/$fn"       # vazio = volta ao default embarcado
      fi
    done
    audit_log_to "$contest" docs-config ""
    ok_json '{saved:true}'
    ;;
  cover|upload)
    # cover  = a CAPA do caderno (o gerador usa no lugar da capa que ele montaria)
    # upload = o DOCUMENTO PRONTO de um tipo+idioma; vence o gerado em tudo que é servido
    lang="$(jq -r '.lang // ""' "$bodyf")"; doc_lang_ok "$lang" || fail 400 "lang deve ser um de: $DOC_LANGS" "lang_invalid"
    if [[ "$action" == upload ]]; then
      t="$(jq -r '.type // ""' "$bodyf")"
      case "$t" in info-sheet|contest|times|editorial) ;; *) fail 400 "type inválido" "type_invalid";; esac
      f="$(doc_upload_pdf "$contest" "$t" "$lang")"; what="upload type=$t"
      _rm_flag='.remove == true or .remove_upload == true'
    else
      f="$(doc_cover_pdf "$contest" "$lang")"; what="cover"; _rm_flag='.remove == true'
    fi
    if jq -e "$_rm_flag" "$bodyf" >/dev/null 2>&1; then
      rm -f "$f"; audit_log_to "$contest" docs-cover "$what lang=$lang remove"; ok_json '{removed:true}'; exit 0
    fi
    jq -r '.pdf_b64 // ""' "$bodyf" | base64 -d > "$f.tmp" 2>/dev/null
    [[ -s "$f.tmp" ]] || { rm -f "$f.tmp"; fail 400 "PDF vazio ou inválido" "pdf_invalid"; }
    # teto explícito (o nginx do subdomínio corta em 100m; aqui a mensagem é do MOJ, não 413 cru)
    if (( $(stat -c%s "$f.tmp" 2>/dev/null || echo 0) > DOC_PDF_MAX_MB * 1024 * 1024 )); then
      rm -f "$f.tmp"; fail 413 "PDF muito grande (máx ${DOC_PDF_MAX_MB}MB)" "file_large"
    fi
    [[ "$(file -b --mime-type "$f.tmp" 2>/dev/null)" == application/pdf ]] \
      || { rm -f "$f.tmp"; fail 400 "O arquivo enviado não é um PDF" "pdf_invalid"; }
    mv -f "$f.tmp" "$f"
    audit_log_to "$contest" docs-cover "$what lang=$lang bytes=$(stat -c%s "$f" 2>/dev/null)"
    ok_json '{saved:true, bytes:$b}' --argjson b "$(stat -c%s "$f" 2>/dev/null || echo 0)"
    ;;
  generate)
    mapfile -t types < <(jq -r '(.types // ["info-sheet","contest","times"])[]' "$bodyf" 2>/dev/null)
    mapfile -t langs < <(jq -r --arg d "$DOC_LANGS" '(.langs // ($d | split(" ")))[]' "$bodyf" 2>/dev/null)
    (( ${#types[@]} )) || types=(info-sheet contest times)
    (( ${#langs[@]} )) || read -r -a langs <<<"$DOC_LANGS"
    done_list='[]'; failed='[]'
    for t in "${types[@]}"; do
      case "$t" in info-sheet|contest|times|editorial) ;; *) continue;; esac
      for l in "${langs[@]}"; do
        doc_lang_ok "$l" || continue
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
    case "$t" in info-sheet|contest|times|editorial) ;; *) fail 400 "type inválido" "type_invalid";; esac
    doc_lang_ok "$l" || fail 400 "lang deve ser um de: $DOC_LANGS" "lang_invalid"
    key="$t.$l"
    cfg="$(doc_conf_get "$contest")"
    if [[ "$action" == publish ]]; then
      # PDF ENVIADO conta como documento pronto — publicar sem gerar é o caso de uso dele
      [[ -n "$(doc_pdf_served "$contest" "$t" "$l")" || -s "$(doc_file "$contest" "$t" "$l" html)" ]] \
        || fail 409 "Gere (ou envie) o documento antes de publicar" "not_generated"
      source "$_DIR/lib/contest-gate.sh"
      # EDITORIAL é a solução da prova: só publica quando o contest terminou PARA TODOS
      # (inclusive prorrogações por sede — time-overrides.json).
      if [[ "$t" == editorial ]] && ! contest_over_for_all "$contest"; then
        fail 403 "O editorial só pode ser publicado depois do FIM da prova (para todas as sedes)" "contest_running"
      fi
      # notícia com PDF anexo NÃO passa pelo gate de fase do /contest/doc: caderno/times
      # antes do início vazariam a prova por ali. Publique sem news e anexe depois do start.
      if jq -e '.news == true' "$bodyf" >/dev/null 2>&1; then
        case "$t" in contest|times)
          [[ "$(contest_phase "$contest")" == before ]] \
            && fail 409 "Antes do início, publique SEM notícia (a notícia anexa o PDF e os times a leem) — o documento já fica liberado para a sede" "news_before_start" ;;
        esac
      fi
      doc_publish "$contest" "$t" "$l" || fail 500 "Falha ao publicar" "publish_fail"
    else
      doc_unpublish "$contest" "$t" "$l" || fail 500 "Falha ao despublicar" "publish_fail"
    fi
    # config.json/resources.json são gravados por doc_publish/doc_unpublish (lib/contest-docs.sh)
    # — MESMO caminho do "encerrar evento", p/ os dois não divergirem.
    cfg="$(doc_conf_get "$contest")"
    label="$(_doc_label "$t" "$l")"

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
