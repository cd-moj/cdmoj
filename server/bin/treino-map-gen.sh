#!/usr/bin/env bash
#
# treino-map-gen.sh — gera o mapa "probid legado -> id do newmoj" do contest treino.
#
#   treino-map-gen.sh --legacy <dir> --owners <problem-owners.json> \
#                     --statements <dir> --out <tsv> [--evidence <dir>]
#
# O history legado do treino guarda o probid como '<repo>#<slug>' (repo = o repositório
# antigo: problemas-apc, moj-problems, compiladores-problems, obi-problems, monitores,
# flia-problems, eda2-problems). No newmoj o id é '<org>#<prob>'. Este script decide, para
# CADA id distinto do history, qual é o id novo — ou que é órfão (problema não migrado).
#
# Saída (TSV, uma linha por id legado distinto):
#
#   legacy_id <TAB> prod_id|- <TAB> rule <TAB> confidence <TAB> subs <TAB> users <TAB> evidence
#
#   prod_id '-'   = órfão: a linha do history mantém o id legado (some da lista, mas a
#                   história fica; reacende sozinho se o problema for migrado depois).
#   confidence    = auto | REVIEWED | ?   — o migrador RECUSA o mapa com qualquer '?'.
#
# Regras, em ordem de confiança:
#
#   alias    — o id legado casa um alias do índice de donos. Os prefixos possíveis de um
#              REPO são {repo} U (união dos collections[] de TODOS os problemas do repo),
#              a MESMA derivação de score/problem-panorama-gen.sh (que é quem resolve isso
#              em runtime). Resolve a esmagadora maioria.  -> auto
#   casefold — mesmo org, slug igual a menos de CAIXA. O servidor recusa nome de problema
#              fora de ^[a-z0-9._-]+$, então todo slug legado com maiúscula foi minusculado
#              na migração: é renome mecânico, não coincidência.  -> auto
#   slug     — slug idêntico, org diferente (o problema mudou de org).  -> ?
#   title    — título igual. NUNCA 'auto': título igual NÃO prova mesmo problema
#              (problemas-apc#crescimento_populacional casa unicamente com
#              apc#p2_crescimento_populacional e é OUTRO problema — author/conf/enunciado/
#              generator divergem). Emite evidência p/ revisão humana.  -> ?
#   orphan   — nenhum candidato.  -> auto
#
# O veredicto sugerido de 'title'/'slug' compara o TEXTO do enunciado (legado
# var/questoes/<id>/enunciado.b64, HTML; prod docs/enunciado.md, Markdown) procurando a
# primeira frase do prod dentro do legado. É SUGESTÃO: 'apc#huaauhahhuahau', p.ex., tem o
# enunciado embutido como PNG base64 no prod e texto no legado — DIFERE sem ser órfão.
#
# Só lê. Não toca no legado, no prod, nem no store.

set -euo pipefail
export LC_ALL=C

die(){ echo "treino-map-gen: $*" >&2; exit 1; }

LEGACY=""; OWNERS=""; STATEMENTS=""; OUT=""; EVID=""; DECISIONS=""; IDS=""
while (( $# )); do
  case "$1" in
    --legacy)     LEGACY="${2:-}"; shift 2 ;;
    --owners)     OWNERS="${2:-}"; shift 2 ;;
    --statements) STATEMENTS="${2:-}"; shift 2 ;;
    --out)        OUT="${2:-}"; shift 2 ;;
    --evidence)   EVID="${2:-}"; shift 2 ;;
    --decisions)  DECISIONS="${2:-}"; shift 2 ;;
    --ids)        IDS="${2:-}"; shift 2 ;;
    -h|--help)    sed -n '2,40p' "$0"; exit 0 ;;
    *) die "opção desconhecida: $1" ;;
  esac
done
# --ids <arquivo>: mapear uma LISTA de <repo>#<slug> (um por linha) em vez de derivar do
# history — para contests cujo probid é offset (as provas), que resolvem o offset ANTES e
# só passam a lista de ids aqui. Sem --ids, o modo original (deriva do history do treino).
[[ -n "$OWNERS" && -n "$OUT" && -n "$STATEMENTS" ]] \
  || die "uso: $0 (--legacy <dir> | --ids <arquivo>) --owners <json> --statements <dir> --out <tsv> [--evidence <dir>] [--decisions <tsv>]"
if [[ -n "$IDS" ]]; then
  [[ -f "$IDS" ]] || die "sem $IDS"
else
  [[ -n "$LEGACY" ]] || die "faltou --legacy (ou --ids)"
  [[ -f "$LEGACY/controle/history" ]] || die "sem $LEGACY/controle/history"
fi
[[ -f "$OWNERS" ]]                  || die "sem $OWNERS"
[[ -d "$STATEMENTS" ]]              || die "sem $STATEMENTS"

# Repos legados cujo nome novo NÃO é alcançável pelos collections[]. Só o compiladores:
# a org é 'compiladores' e o collections diz 'problemas-compiladores', mas o history legado
# diz 'compiladores-problems#' — sem isto, as ~3.1k submissões de compiladores orfanariam.
declare -A REPO_RENAME=( [compiladores-problems]=compiladores )

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
[[ -n "$EVID" ]] && mkdir -p "$EVID"

# --- normalização de texto ---------------------------------------------------------------
# NFD + tira acento + minúscula + só [a-z0-9 ]. Determinístico dos dois lados (o legado é
# HTML gerado por pandoc, o prod é Markdown escrito à mão).
#
# O colapso de token repetido adjacente ("m m" -> "m") NÃO é cosmético: o HTML legado do
# pandoc emite a matemática DUAS vezes (MathJax: a versão visual + o fallback), então `$m$`
# vira "m m" e só no lado legado. Sem isto, todo enunciado com matemática inline dá falso
# DIFERE (foi o caso de moj-problems#J-9mdp-ifb).
NORM_PL='use Unicode::Normalize; $_=NFD($_); s/\p{NonspacingMark}//g; $_=lc($_); s/[^a-z0-9]+/ /g; 1 while s/\b(\w+) \1\b/$1/g; s/^ +| +$//g;'

norm_text(){ perl -0777 -CSD -pe "$NORM_PL"; }

# título legado -> normalizado. Tira o prefixo de letra de prova ("A: Alarme do Museu"),
# que os saet24 guardam no título e o pacote novo não.
norm_title(){ printf '%s' "${1:-}" | perl -0777 -CSD -pe 's/^\s*[A-Z]:\s+//;' | norm_text; }

# CUIDADO: nada de `local a="$1" b="...${a}..."` — o bash expande TODAS as palavras ANTES
# de rodar o `local`, então o segundo enxerga o valor ANTIGO (vazio) do primeiro. Um
# `local` por linha.
legacy_html(){ # <legacy_id> -> HTML cru do enunciado legado
  local b h
  b="$LEGACY/var/questoes/$1/enunciado.b64"
  if [[ -f "$b" ]]; then base64 -d "$b" 2>/dev/null || true; return 0; fi
  h="$LEGACY/enunciados/$1.html"
  [[ -f "$h" ]] && cat "$h"
  return 0
}
# Decodifica entidade NUMÉRICA (&#39; etc) ANTES de descartar a pontuação: sem isso o
# apóstrofo vira o literal "39" e polui o texto (foi o caso de moj-problems#saet24-Mdieta).
legacy_text(){ legacy_html "$1" \
  | perl -0777 -CSD -pe 's/<style.*?<\/style>//gsi; s/<script.*?<\/script>//gsi; s/<[^>]*>/ /g;
      s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge; s/&#([0-9]+);/chr($1)/ge;
      s/&nbsp;/ /g; s/&amp;/&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/"/g; s/&[a-zA-Z]+;/ /g;' \
  | norm_text; }
prod_text(){ # <prod_id> -> texto normalizado do enunciado do newmoj
  local id f
  id="$1"
  f="$STATEMENTS/${id%%#*}/${id#*#}/docs/enunciado.md"
  [[ -f "$f" ]] && norm_text < "$f" || true
}

# story_tokens — stdin (texto normalizado) -> um token por linha, SÓ da estória (corta na
# seção "Entrada").
#
# A agulha TEM de sair da estória. As seções Entrada/Saída são clichê e batem entre
# problemas SEM RELAÇÃO: "e composta por um unico caso de teste a primeira linha do" tem 12
# tokens e casou flia-problems#gripper-pro3 (robô PDDL) com moj-problems#grafo-nucleos-cidades
# (estradas da Nlogônia). A estória é a parte única de um enunciado; o resto é formulário.
story_tokens(){
  awk 'BEGIN{RS=" "} { if ($0=="entrada" && n>=12) exit; if ($0!=""){ print; n++ } }'
}

# Veredicto sugerido: alguma JANELA de 12 tokens do enunciado do prod aparece, literal, no
# texto legado? Três janelas (início/1º terço/2º terço), e basta uma bater.
#
# Uma janela só (a do começo) dá falso DIFERE quando as duas versões divergem logo no
# início: em moj-problems#saad-calculo-medias o HTML legado perdeu a lista de opções que o
# Markdown do prod tem, e o resto do texto bate palavra por palavra. Janelas espalhadas
# resolvem sem afrouxar o teste — continua exigindo 12 tokens CONSECUTIVOS idênticos, que é
# o que separa "mesmo problema" de "problema parecido" (crescimento_populacional segue DIFERE).
probe(){ # <legacy_id> <prod_id> -> MATCH|DIFERE|SEM-TEXTO
  local lt pw n i w
  lt="$(legacy_text "$1")"
  [[ -z "$lt" ]] && { echo "SEM-TEXTO"; return; }
  mapfile -t pw < <(prod_text "$2" | story_tokens)
  n=${#pw[@]}
  (( n < 12 )) && { echo "SEM-TEXTO"; return; }
  for i in 0 $(( n/3 )) $(( 2*n/3 )); do
    (( i + 12 > n )) && continue
    w="${pw[*]:i:12}"
    case "$lt" in *"$w"*) echo "MATCH"; return ;; esac
  done
  echo "DIFERE"
}

# --- 1) ids legados distintos + contagens ------------------------------------------------
# history legado: f1:login:probid:LANG:verdict:f6:subid  (verdict pode ter ',', nunca ':')
if [[ -n "$IDS" ]]; then
  # lista de <repo>#<slug> (um por linha); subs/users = 0 (não vêm de um history)
  grep -v '^[[:space:]]*$' "$IDS" | grep -v '^#' | sort -u \
    | awk '{ printf "%s\t0\t0\n", $1 }' > "$TMP/legacy.tsv"
else
  # history legado: f1:login:probid:LANG:verdict:f6:subid  (verdict pode ter ',', nunca ':')
  awk -F: '{ n[$3]++; k=$3 SUBSEP $2; if(!(k in seen)){seen[k]=1; u[$3]++} }
           END{ for(p in n) printf "%s\t%d\t%d\n", p, n[p], u[p] }' \
    "$LEGACY/controle/history" | sort > "$TMP/legacy.tsv"
fi
echo "ids legados distintos: $(wc -l < "$TMP/legacy.tsv")" >&2

# --- 2) índices do prod ------------------------------------------------------------------
# alias '<C>#<prob>' -> id canônico. Derivação idêntica à de score/problem-panorama-gen.sh:
# os prefixos de um REPO são {repo} U (união dos collections[] de todos os problemas dele).
jq -r '
  (.problems | group_by(.repo)
   | map({key: .[0].repo, value: (((map(.collections // []) | add) // []) | unique)})
   | from_entries) as $rp
  | .problems[] | .id as $oid | .prob as $P | .repo as $R
  | ((([$R] + (($rp[$R]) // [])) | unique)[]) as $C
  | "\($C)#\($P)\t\($oid)"' "$OWNERS" | sort -u > "$TMP/alias.tsv"
jq -r '.problems[] | "\(.id)\t\(.id)"' "$OWNERS" | sort -u >> "$TMP/alias.tsv"
declare -A ALIAS; while IFS=$'\t' read -r k v; do [[ -n "$k" ]] && ALIAS["$k"]="$v"; done < "$TMP/alias.tsv"
echo "aliases: ${#ALIAS[@]}" >&2

# slug -> ids (regra slug) e título normalizado -> ids (regra title)
declare -A BYSLUG BYTITLE
n_prod=0
while IFS=$'\t' read -r id repo prob title; do
  n_prod=$((n_prod+1))
  BYSLUG["$prob"]="${BYSLUG[$prob]:+${BYSLUG[$prob]}|}$id"
  t="$(norm_title "$title")"
  [[ -n "$t" ]] && BYTITLE["$t"]="${BYTITLE[$t]:+${BYTITLE[$t]}|}$id"
done < <(jq -r '.problems[] | [.id, .repo, .prob, (.title // "")] | @tsv' "$OWNERS")
echo "problemas no prod: $n_prod" >&2

# Índice de alias em MINÚSCULA -> p/ a regra casefold. Reusa a MESMA tabela de alias (e
# portanto a ponte repo->org via collections): 'problemas-apc#Huaauhahhuahau' tem de achar
# 'apc#huaauhahhuahau', e o repo->org aí é collections, não a tabela de renome.
declare -A ALIASLC
for k in "${!ALIAS[@]}"; do ALIASLC["${k,,}"]="${ALIAS[$k]}"; done

# Orgs alcançáveis por cada prefixo legado (p/ desempatar candidato). Um prefixo pode levar
# a mais de uma org (o collection 'mdp-unb-xii' aparece na org mdp-unb-xii E na saad-problems).
declare -A REPO_ORGS
for k in "${!ALIAS[@]}"; do
  _c="${k%%#*}"; _o="${ALIAS[$k]%%#*}"
  [[ "|${REPO_ORGS[$_c]:-}|" == *"|$_o|"* ]] || REPO_ORGS["$_c"]="${REPO_ORGS[$_c]:+${REPO_ORGS[$_c]}|}$_o"
done

# --- índice de CONTEÚDO: <prod_id> \t <1ª frase de 15 tokens> ----------------------------
# Nome (slug/título) não basta nos dois sentidos: 'moj-problems#maior_numero' tem slug E
# título idênticos aos de 'apc#maior_numero' e é OUTRO problema (o legado lê uma quantidade
# ARBITRÁRIA de números; o do apc lê QUATRO) — o certo é 'moj-problems#maior-numero-eof',
# que nem slug nem título alcançam. Quando o nome falha, procuramos o enunciado do prod
# DENTRO do texto legado. Um perl só p/ os 1102 (um por arquivo seria ~1 min).
echo "indexando enunciados do prod..." >&2
find "$STATEMENTS" -name enunciado.md -print0 \
  | perl -0 -CSD -MUnicode::Normalize -ne '
      chomp; my $f = $_;
      my ($org,$prob) = $f =~ m{([^/]+)/([^/]+)/docs/enunciado\.md$} or next;
      open my $h, "<:encoding(UTF-8)", $f or next; local $/; my $t = <$h>; close $h;
      $t = NFD($t); $t =~ s/\p{NonspacingMark}//g; $t = lc($t);
      $t =~ s/[^a-z0-9]+/ /g; 1 while $t =~ s/\b(\w+) \1\b/$1/g; $t =~ s/^ +| +$//g;
      my @w = split / /, $t;
      # só a ESTÓRIA: corta na seção "Entrada" (o resto é clichê e casa entre problemas
      # sem relação — ver story_tokens()).
      for my $j (12 .. $#w) { if ($w[$j] eq "entrada") { @w = @w[0 .. $j-1]; last } }
      my $n = @w; next if $n < 12;
      my %s;
      for my $i (0, int($n/3), int(2*$n/3)) {
        next if $i + 12 > $n;
        my $p = join(" ", @w[$i .. $i+11]);
        next if $s{$p}++;
        print "$org#$prob\t$p\n";
      }
    ' > "$TMP/phrases.tsv"
echo "frases indexadas: $(wc -l < "$TMP/phrases.tsv")" >&2

# content_search <legacy_id> -> ids do prod cujo enunciado aparece no texto legado (|-sep)
content_search(){
  local lt hits pid ph
  lt="$(legacy_text "$1")"
  [[ -z "$lt" ]] && return 0
  hits=""
  while IFS=$'\t' read -r pid ph; do
    [[ -n "$ph" ]] || continue
    [[ "|$hits|" == *"|$pid|"* ]] && continue
    case "$lt" in *"$ph"*) hits="${hits:+$hits|}$pid" ;; esac
  done < "$TMP/phrases.tsv"
  printf '%s' "$hits"
}

# --- 2b) decisões humanas (o resultado da auditoria) --------------------------------------
# TSV: legacy_id \t prod_id|- \t nota.  '#' inicia comentário.
declare -A DEC
if [[ -n "$DECISIONS" ]]; then
  [[ -f "$DECISIONS" ]] || die "sem $DECISIONS"
  while IFS=$'\t' read -r lid dprod dnote; do
    [[ -z "$lid" || "$lid" == \#* ]] && continue
    DEC["$lid"]="$dprod"$'\t'"${dnote:-sem nota}"
  done < "$DECISIONS"
  echo "decisões humanas: ${#DEC[@]}" >&2
fi

# --- 3) decide cada id -------------------------------------------------------------------
: > "$TMP/out.tsv"
while IFS=$'\t' read -r lid subs users; do
  repo="${lid%%#*}"; slug="${lid#*#}"
  rrepo="${REPO_RENAME[$repo]:-$repo}"
  rid="$rrepo#$slug"
  prod=""; rule=""; conf=""; ev=""; tiebreak=""

  # alias (usa o id já com o repo renomeado)
  if [[ -n "${ALIAS[$rid]:-}" ]]; then
    prod="${ALIAS[$rid]}"; rule="alias"; conf="auto"
    ev="alias de repo/collections"
    [[ "$rrepo" != "$repo" ]] && ev="$ev (repo renomeado $repo->$rrepo)"
  # casefold: mesmo alias a menos de caixa (o servidor recusa slug com maiúscula)
  elif [[ -n "${ALIASLC[${rid,,}]:-}" ]]; then
    prod="${ALIASLC[${rid,,}]}"; rule="casefold"; conf="auto"
    ev="slug minusculado na migracao ($slug -> ${prod#*#})"
  else
    # Nome não resolve => decide pelo ENUNCIADO. Candidatos por nome (slug idêntico noutra
    # org + título igual); se nenhum bater o texto, varre os 1102 enunciados do prod.
    ltitle="$(norm_title "$(cat "$LEGACY/var/questoes/$lid/title" 2>/dev/null || true)")"
    cands="${BYSLUG[$slug]:-}"
    [[ -n "$ltitle" && -n "${BYTITLE[$ltitle]:-}" ]] && cands="${cands:+$cands|}${BYTITLE[$ltitle]}"
    origin="nome"
    matches=""
    if [[ -n "$cands" ]]; then
      IFS='|' read -ra arr <<< "$cands"
      for c in "${arr[@]}"; do
        [[ "|$matches|" == *"|$c|"* ]] && continue
        [[ "$(probe "$lid" "$c")" == "MATCH" ]] && matches="${matches:+$matches|}$c"
      done
    fi
    if [[ -z "$matches" ]]; then
      matches="$(content_search "$lid")"; origin="conteudo"
    fi

    # Desempate: o problema que FICOU na org do repo legado ganha. O legado distingue
    # 'moj-problems#velocidade_media' de 'problemas-apc#velocidade_media' (ids separados,
    # com submissões próprias) e o prod tem os dois (moj-problems#velocidade-media e
    # apc#velocidade_media): casar cada um na SUA org preserva a distinção. Sem isto,
    # duplicata entre orgs viraria escolha arbitrária.
    if [[ "$matches" == *"|"* ]]; then
      same=""
      IFS='|' read -ra marr <<< "$matches"
      for c in "${marr[@]}"; do
        [[ "|${REPO_ORGS[$rrepo]:-}|" == *"|${c%%#*}|"* ]] && same="${same:+$same|}$c"
      done
      if [[ -n "$same" && "$same" != *"|"* ]]; then
        matches="$same"; tiebreak=" (desempate: mesma org do repo legado)"
      fi
    fi

    if [[ -z "$matches" ]]; then
      rule="orphan"; conf="auto"; prod="-"
      if [[ -n "$cands" ]]; then ev="candidatos por nome ($cands) mas NENHUM enunciado bate; varredura de conteudo tambem vazia"
      else ev="sem alias, sem slug, sem titulo e sem enunciado equivalente no prod"; fi
    elif [[ "$matches" == *"|"* ]]; then
      rule="ambiguous"; conf="?"; prod="${matches%%|*}"
      ev="AMBIGUO ($origin): varios enunciados batem -> $matches"
    else
      prod="$matches"; conf="?"
      if [[ "$origin" == "conteudo" ]]; then
        rule="content"; ev="nome NAO resolve; achado pelo ENUNCIADO$tiebreak"
      elif [[ -n "${BYSLUG[$slug]:-}" && "|${BYSLUG[$slug]}|" == *"|$prod|"* ]]; then
        rule="slug"; ev="slug exato noutra org + enunciado MATCH$tiebreak"
      else
        rule="title"; ev="titulo + enunciado MATCH$tiebreak"
      fi
    fi
  fi

  # Decisão humana MANDA. O arquivo de decisões é o registro da auditoria: as regras são
  # heurística (a de 'content' chega a casar trecho de CÓDIGO compartilhado entre enunciados
  # diferentes), então quem assina o encaixe é o revisor, não o script.
  if [[ -n "${DEC[$lid]:-}" ]]; then
    dprod="${DEC[$lid]%%$'\t'*}"; dnote="${DEC[$lid]#*$'\t'}"
    [[ "$dprod" != "$prod" ]] && ev="revisado (o script sugeria ${prod:--}): $dnote" || ev="revisado: $dnote"
    prod="$dprod"; conf="REVIEWED"
  fi

  printf '%s\t%s\t%s\t%s\t%d\t%d\t%s\n' "$lid" "${prod:--}" "$rule" "$conf" "$subs" "$users" "$ev" >> "$TMP/out.tsv"

  # evidência p/ tudo que precisa de olho humano
  if [[ -n "$EVID" && "$conf" == "?" ]]; then
    f="$EVID/$(printf '%s' "$lid" | tr '/#' '__').txt"
    { echo "legado : $lid"
      echo "candidato: ${prod:--}   (regra=$rule)"
      echo "subs=$subs users=$users"
      echo "evidencia: $ev"
      echo
      echo "--- titulo legado: $(cat "$LEGACY/var/questoes/$lid/title" 2>/dev/null || echo '(sem)')"
      [[ "$prod" != "-" ]] && echo "--- titulo prod  : $(jq -r --arg i "$prod" '.problems[]|select(.id==$i)|.title' "$OWNERS" 2>/dev/null)"
      echo
      echo "--- enunciado LEGADO (600 chars normalizados):"; legacy_text "$lid" | head -c 600; echo
      echo
      [[ "$prod" != "-" ]] && { echo "--- enunciado PROD (600 chars normalizados):"; prod_text "$prod" | head -c 600; echo; }
    } > "$f"
  fi
done < "$TMP/legacy.tsv"

sort -t$'\t' -k5,5nr -k1,1 "$TMP/out.tsv" > "$OUT"

echo >&2
echo "=== resumo por regra ===" >&2
awk -F'\t' '{r[$3]++; s[$3]+=$5} END{for(k in r) printf "  %-9s %4d ids  %6d subs\n", k, r[k], s[k]}' "$OUT" | sort >&2
echo "=== a revisar (confidence=?) ===" >&2
awk -F'\t' '$4=="?"' "$OUT" | wc -l >&2
echo "mapa: $OUT" >&2
[[ -n "$EVID" ]] && echo "evidencia: $EVID" >&2
exit 0
