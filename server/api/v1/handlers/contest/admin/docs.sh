# GET/POST /contest/admin/docs?contest=<c>   (admin OU juiz-chefe)
# Documentos da prova: info sheet, caderno (com capa customizável) e folha de time limits,
# em HTML+PDF e nos dois idiomas. Ver lib/contest-docs.sh e docs/MANUAL-CONTEST.md.
#
# GET  -> {docs:[…], config:{…}, templates:{info_sheet:{<lang>:md}, cover:{<lang>:md}, (+ as chaves planas
#          antigas)}, custom:{info_sheet:{<lang>:bool}, cover:{<lang>:bool}}, cover_uploaded:{<lang>:bool},
#          problems:[{letter,name,has_pdf,has_html}]}
#          templates = o texto EDITADO do contest, senão o PADRÃO embarcado (server/etc/{info-sheet,cover}.<lang>.md)
#          — a capa também (25/09/2026: antes vinha vazia e o editor não mostrava o que a capa continha);
#          custom diz qual dos dois é.
# POST {action}:
#   config    {caderno_version?, cover_note?, errata?, info_sheet_pt?, info_sheet_en?,
#              cover_pt?, cover_en?}          — textos/campos editáveis
#   cover     {lang, pdf_b64}|{lang, remove:true}  — capa em PDF ENVIADO (vence a gerada)
#   logo      {image_b64}|{remove:true}      — LOGO do cabeçalho do caderno/editorial e da capa gerada
#                                               (PNG/JPEG/WebP/SVG, até 5 MB; reprocessado p/ PNG com altura
#                                               limitada — o molde dos cadernos da SBC, faixa de logos no topo)
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
  # para não quebrar cliente velho). ⚠ template é texto livre do admin: o conteúdo anda SEMPRE
  # por ARQUIVO (--rawfile na entrada, --slurpfile na junção) — mapa somado por --argjson teria
  # o mesmo teto de 128 KiB POR ARGUMENTO que derruba jq no exec (a armadilha clássica da casa).
  tmpm="$(mktemp -d)" || fail 500 "tmp" "tmp"
  trap 'rm -rf "$tmpm"' EXIT
  printf '{}' > "$tmpm/t.json"; printf '{}' > "$tmpm/c.json"; umap='{}'; cust='{"info_sheet":{},"cover":{}}'
  for L in $DOC_LANGS; do
    ic=true; tf="$D/info-sheet.$L.md"; [[ -s "$tf" ]] || { ic=false; tf="$(doc_default_tpl info-sheet "$L")" || tf=/dev/null; }
    jq -c --arg l "$L" --rawfile v "$tf" '.[$l] = $v' "$tmpm/t.json" > "$tmpm/t.new" \
      && mv -f "$tmpm/t.new" "$tmpm/t.json"
    cc=true; cf="$(doc_cover_md "$contest" "$L")"; [[ -s "$cf" ]] || { cc=false; cf="$(doc_default_tpl cover "$L")" || cf=/dev/null; }
    cust="$(jq -c --arg l "$L" --argjson i "$ic" --argjson c "$cc" '.info_sheet[$l] = $i | .cover[$l] = $c' <<<"$cust")"
    jq -c --arg l "$L" --rawfile v "$cf" '.[$l] = $v' "$tmpm/c.json" > "$tmpm/c.new" \
      && mv -f "$tmpm/c.new" "$tmpm/c.json"
    cu=false; [[ -s "$(doc_cover_pdf "$contest" "$L")" ]] && cu=true
    umap="$(jq -c --arg l "$L" --argjson v "$cu" '.[$l] = $v' <<<"$umap")"
  done
  printf '%s' "$out" > "$tmpm/probs.json"
  doc_index "$contest" > "$tmpm/docs.json"
  lgf="$(doc_logo_file "$contest")"
  lg="$(jq -cn --arg f "$lgf" --argjson b "$( [[ -n "$lgf" ]] && stat -c%s "$lgf" 2>/dev/null || echo 0)" \
        '{present:($f != ""), bytes:$b}')"
  emit_json 200 OK
  jq -cn --slurpfile docs "$tmpm/docs.json" --argjson cfg "$(doc_conf_get "$contest")" \
     --slurpfile probs "$tmpm/probs.json" --slurpfile tm "$tmpm/t.json" --slurpfile cm "$tmpm/c.json" \
     --argjson um "$umap" --argjson cust "$cust" --arg langs "$DOC_LANGS" --argjson lg "$lg" \
     '{success:true, docs:$docs[0], config:$cfg, problems:$probs[0], langs:($langs | split(" ")),
       templates:({info_sheet_pt:($tm[0].pt // ""), info_sheet_en:($tm[0].en // ""),
                   cover_pt:($cm[0].pt // ""), cover_en:($cm[0].en // "")}
                  + {info_sheet:$tm[0], cover:$cm[0]}),
       custom:$cust, cover_uploaded:$um, logo:$lg}'
  exit 0
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
    # exemplos em TABELA no caderno (opt-in; default = empilhados, como no site). Booleano de verdade:
    # só `true` liga — "false", 0 e lixo desligam.
    if jq -e 'has("samples_table")' "$bodyf" >/dev/null 2>&1; then
      b="$(jq -r '.samples_table == true' "$bodyf")"
      cfg="$(jq -c --argjson b "$b" '.samples_table = $b' <<<"$cfg")"
    fi
    printf '%s\n' "$cfg" > "$D/config.json.tmp" && mv -f "$D/config.json.tmp" "$D/config.json"
    # textos longos (templates) vão para arquivo próprio — nunca por --arg (ARG_MAX)
    pairs=(); for L in $DOC_LANGS; do pairs+=( "info_sheet_$L:info-sheet.$L.md:info-sheet:$L" "cover_$L:cover.$L.md:cover:$L" ); done
    for pair in "${pairs[@]}"; do
      IFS=: read -r key fn kind L <<<"$pair"
      if jq -e --arg k "$key" 'has($k)' "$bodyf" >/dev/null 2>&1; then
        jq -r --arg k "$key" '.[$k] // ""' "$bodyf" > "$D/$fn.tmp" && mv -f "$D/$fn.tmp" "$D/$fn"
        # vazio OU igual ao padrão embarcado = volta ao padrão (o editor mostra o padrão: salvar sem mexer
        # não pode congelar a cópia de hoje e deixar o contest de fora quando o padrão melhorar). "Vazio" é
        # SÓ ESPAÇO: o `jq -r` de "" grava uma quebra de linha — o `-s` de antes nunca apagava nada.
        dft="$(doc_default_tpl "$kind" "$L")" || dft=""
        if [[ -z "$(tr -d '[:space:]' < "$D/$fn")" ]] || { [[ -n "$dft" ]] && [[ "$(<"$D/$fn")" == "$(<"$dft")" ]]; }; then
          rm -f "$D/$fn"
        fi
      fi
    done
    mod_enable "$contest" documentos
    audit_log_to "$contest" docs-config ""
    ok_json '{saved:true}'
    ;;
  logo)
    # LOGO do cabeçalho (caderno, editorial, capa gerada). Reprocessado SEMPRE: vira PNG, sem metadado,
    # com altura ≤ 360 px (a faixa tem 1,6 cm; 360 px ≈ 570 dpi — sobra p/ impressão) e largura ≤ 3000.
    # Imagem é entrada hostil: o MIME é conferido pelo `file` ANTES do magick (nunca pela extensão).
    f="$D/header-logo.png"
    if jq -e '.remove == true' "$bodyf" >/dev/null 2>&1; then
      rm -f "$f"; audit_log_to "$contest" docs-logo "remove"; ok_json '{removed:true}'; exit 0
    fi
    mkdir -p "$D" 2>/dev/null
    lt="$(mktemp -d)" || fail 500 "tmp" "tmp"
    jq -r '.image_b64 // ""' "$bodyf" | sed 's/^data:[^,]*,//' | base64 -d > "$lt/in" 2>/dev/null
    [[ -s "$lt/in" ]] || { rm -rf "$lt"; fail 400 "Imagem vazia ou inválida" "image_invalid"; }
    (( $(stat -c%s "$lt/in" 2>/dev/null || echo 0) <= 5 * 1024 * 1024 )) \
      || { rm -rf "$lt"; fail 413 "Imagem muito grande (máx 5MB)" "file_large"; }
    case "$(file -b --mime-type "$lt/in" 2>/dev/null)" in
      image/png|image/jpeg|image/webp|image/svg+xml) ;;
      *) rm -rf "$lt"; fail 400 "Envie PNG, JPEG, WebP ou SVG" "image_invalid";;
    esac
    magick "$lt/in" -strip -background none -resize '3000x360>' "PNG32:$lt/out.png" >/dev/null 2>&1
    [[ -s "$lt/out.png" && "$(file -b --mime-type "$lt/out.png" 2>/dev/null)" == image/png ]] \
      || { rm -rf "$lt"; fail 400 "Não foi possível ler a imagem" "image_invalid"; }
    mv -f "$lt/out.png" "$f"; rm -rf "$lt"
    mod_enable "$contest" documentos
    audit_log_to "$contest" docs-logo "bytes=$(stat -c%s "$f" 2>/dev/null)"
    ok_json '{saved:true, bytes:$b}' --argjson b "$(stat -c%s "$f" 2>/dev/null || echo 0)"
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
      # "voltar ao gerado" num documento PUBLICADO sem PDF gerado deixaria o link dos times em 404 com a tela
      # dizendo "publicado" (auditoria do painel, 03/10/2026): gere antes ou despublique.
      if [[ "$action" == upload && -s "$f" && ! -s "$(doc_file "$contest" "$t" "$lang" pdf)" ]] \
         && jq -e --arg k "$t.$lang" '((.published // []) | index($k)) != null' <<<"$(doc_conf_get "$contest")" >/dev/null 2>&1; then
        fail 409 "Este documento está publicado e não há PDF gerado: gere o documento antes de voltar ao gerado, ou despublique" "published_no_generated"
      fi
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
    mod_enable "$contest" documentos
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
        # rc 3 = o HTML saiu mas a conversão p/ PDF FALHOU: é falha (o PDF anterior, se havia, continua o servido e o
        # índice guarda a data DELE — antes a tela dizia "gerado" agora com o PDF velho; auditoria do painel, 03/10/2026)
        e="$(doc_build "$contest" "$t" "$l")"; rc=$?
        if (( rc == 0 )) && [[ -n "$e" ]]; then
          doc_index_upsert "$contest" "$e"
          done_list="$(jq -c --argjson d "$done_list" --argjson e "$e" '$d + [$e]' <<<'null')"
        else
          why=build; (( rc == 3 )) && why=pdf
          failed="$(jq -c --argjson f "$failed" --arg t "$t" --arg l "$l" --arg w "$why" '$f + [{type:$t, lang:$l, reason:$w}]' <<<'null')"
        fi
      done
    done
    mod_enable "$contest" documentos
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
      # PDF ENVIADO conta como documento pronto — publicar sem gerar é o caso de uso dele. Tem de haver PDF: o link
      # publicado (seção Prova, notícia) é o do PDF, e só com o HTML ele dava 404 aos times (auditoria, 03/10/2026)
      [[ -n "$(doc_pdf_served "$contest" "$t" "$l")" ]] \
        || fail 409 "Gere (ou envie) o PDF do documento antes de publicar" "not_generated"
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
            && fail 409 "Antes do início, publique SEM notícia (a notícia anexa o PDF e os times a leem) — o documento aparece para a sede e os times no início da prova" "news_before_start" ;;
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

    # notícia com o PDF anexado (opcional) — reusa o formato de news.json/news-files. O anexo é o PDF SERVIDO (o
    # enviado vence o gerado, como no link); `doc` liga a notícia ao documento p/ o despublicar levá-la junto.
    news_created=false; news_removed=0
    nj="$CONTESTSDIR/$contest/news.json"
    if [[ "$action" == publish ]] && jq -e '.news == true' "$bodyf" >/dev/null 2>&1; then
      pdf="$(doc_pdf_served "$contest" "$t" "$l")"
      if [[ -s "$pdf" ]]; then
        nid="$(printf '%s%s%s' "$contest" "$EPOCHSECONDS" "$RANDOM" | md5sum | cut -c1-32)"
        nf="$CONTESTSDIR/$contest/news-files/$nid"; mkdir -p "$nf" 2>/dev/null
        fname="$t.$l.pdf"; cp -f "$pdf" "$nf/$fname"
        [[ -s "$nj" ]] || printf '[]' > "$nj"
        jq -c --arg id "$nid" --arg ti "$label" --arg tx "$(_doc_t "$l" news_doc)" --arg k "$key" \
           --arg fn "$fname" --argjson sz "$(stat -c%s "$nf/$fname" 2>/dev/null || echo 0)" --argjson dt "$EPOCHSECONDS" \
           '. + [{id:$id, title:$ti, text:$tx, date:$dt, doc:$k, file:{name:$fn, size:$sz}}]' "$nj" > "$nj.tmp" \
          && mv -f "$nj.tmp" "$nj" && news_created=true
      fi
    fi
    # DESPUBLICAR leva junto a notícia com o anexo: senão o PDF seguia baixável por ela (auditoria do painel,
    # 03/10/2026). Notícia antiga, sem `doc`, casa pelo título + nome do anexo que o publish dá.
    if [[ "$action" == unpublish && -s "$nj" ]]; then
      mapfile -t rm_ids < <(jq -r --arg k "$key" --arg ti "$label" --arg fn "$t.$l.pdf" \
        '.[] | select(.doc == $k or (.doc == null and .title == $ti and (.file.name // "") == $fn)) | .id' "$nj" 2>/dev/null)
      if (( ${#rm_ids[@]} )); then
        jq -c --arg k "$key" --arg ti "$label" --arg fn "$t.$l.pdf" \
          'map(select((.doc == $k or (.doc == null and .title == $ti and (.file.name // "") == $fn)) | not))' "$nj" > "$nj.tmp" \
          && mv -f "$nj.tmp" "$nj" && {
            for i in "${rm_ids[@]}"; do [[ "$i" =~ ^[A-Za-z0-9]+$ ]] && rm -rf "$CONTESTSDIR/$contest/news-files/$i"; done
            news_removed=${#rm_ids[@]}; }
      fi
    fi
    # QUANDO o time vê: caderno/times publicados antes do início só aparecem no início (gate de fase do /contest/doc)
    avail=now
    if [[ "$action" == publish ]]; then
      case "$t" in contest|times) [[ "$(contest_phase "$contest")" == before ]] && avail=at_start ;; esac
    fi
    [[ "$action" == publish ]] && mod_enable "$contest" documentos
    audit_log_to "$contest" "docs-$action" "type=$t lang=$l news=$news_created news_removed=$news_removed"
    ok_json '{ok:true, published:($cfgp), news:$n, news_removed:$nr, available:$av}' \
      --argjson cfgp "$(jq -c '.published // []' <<<"$cfg")" --argjson n "$news_created" \
      --argjson nr "$news_removed" --arg av "$avail"
    ;;
  *) fail 400 "action inválida" "action_invalid";;
esac
