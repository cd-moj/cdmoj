#!/bin/bash
# docs/i18n.sh — a documentação de USUÁRIO em pt · en · es (docs/I18N.md, seção "Documentação").
#
# O PT (docs/<DOC>.md) é a fonte; as traduções moram em docs/en/<DOC>.md e docs/es/<DOC>.md e a 1ª
# linha de cada uma é o CARIMBO de origem:
#     <!-- i18n-source: <DOC>.md blob:<git hash-object do PT traduzido> -->
# Mudou o PT ⇒ no MESMO commit: `diff` mostra o que mudou desde o carimbo, aplique em en/ e es/ e rode
# `stamp`. O server/test/smoke-docs-i18n.sh reprova tradução atrasada (carimbo ≠ blob atual do PT).
#
#   bash docs/i18n.sh list                 os docs traduzidos (um por linha)
#   bash docs/i18n.sh status               doc × idioma: em dia | ATRASADO | FALTA
#   bash docs/i18n.sh diff <DOC>           o que mudou no PT desde o carimbo (de cada idioma)
#   bash docs/i18n.sh stamp <DOC> [en|es]  regrava o carimbo com o PT atual (depois de traduzir)
#
# Este arquivo é a LISTA ÚNICA (lida pelo build-html.sh e pelo lint); o espelho em JS é o
# DOCS_I18N de web/shared/i18n.js — paridade conferida pelo lint.
DOCS_I18N=(MANUAL-CONTEST MANUAL-TREINO MANUAL-JUIZ MANUAL-STAFF MANUAL-ANIMEITOR ENUNCIADO ESTATISTICAS-PROBLEMA CONTAS-GERIDAS MANUAL-ORGS-COLECOES MANUAL-LINGUAGENS PACOTE MANUAL-ADMIN)
DOC_LANGS_I18N=(en es)

# carimbo esperado p/ o PT de <DOC> (blob do git da ÁRVORE DE TRABALHO; vai no mesmo commit)
i18n_blob(){ git -C "$1" hash-object "$1/$2.md"; }
# blob gravado na 1ª linha da tradução (vazio se não há)
i18n_stamp_of(){ sed -n '1s/^<!-- i18n-source: [^ ]* blob:\([0-9a-f]*\) -->$/\1/p' "$1" 2>/dev/null; }

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -u
  D="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
  in_list(){ local x; for x in "${DOCS_I18N[@]}"; do [[ "$x" == "$1" ]] && return 0; done; return 1; }
  case "${1:-status}" in
    list) printf '%s\n' "${DOCS_I18N[@]}" ;;
    status)
      rc=0
      for d in "${DOCS_I18N[@]}"; do
        b="$(i18n_blob "$D" "$d")"
        for l in "${DOC_LANGS_I18N[@]}"; do
          f="$D/$l/$d.md"
          if [[ ! -f "$f" ]]; then st=FALTA; rc=1
          elif [[ "$(i18n_stamp_of "$f")" == "$b" ]]; then st="em dia"
          else st=ATRASADO; rc=1; fi
          printf '%-24s %s  %s\n' "$d" "$l" "$st"
        done
      done
      exit $rc ;;
    diff)
      d="${2:?uso: i18n.sh diff <DOC>}"; d="${d%.md}"
      in_list "$d" || { echo "$d não está na lista DOCS_I18N" >&2; exit 2; }
      for l in "${DOC_LANGS_I18N[@]}"; do
        s="$(i18n_stamp_of "$D/$l/$d.md")"
        echo "=== $l/$d.md — carimbo ${s:-(nenhum)}"
        if [[ -z "$s" ]]; then echo "(sem carimbo: traduza o documento inteiro)"; continue; fi
        [[ "$s" == "$(i18n_blob "$D" "$d")" ]] && { echo "(em dia)"; continue; }
        # blob do carimbo × PT atual. `git diff <blob> <caminho>` NÃO serve (o 2º argumento vira revisão)
        git -C "$D" cat-file -p "$s" > "${TMPDIR:-/tmp}/i18n-old.$$" 2>/dev/null \
          || { echo "blob $s não está no repositório (carimbo de um PT nunca commitado?)" >&2; exit 1; }
        git --no-pager diff --no-index --no-prefix "${TMPDIR:-/tmp}/i18n-old.$$" "$D/$d.md"
        rm -f "${TMPDIR:-/tmp}/i18n-old.$$"
      done ;;
    stamp)
      d="${2:?uso: i18n.sh stamp <DOC> [en|es]}"; d="${d%.md}"
      in_list "$d" || { echo "$d não está na lista DOCS_I18N" >&2; exit 2; }
      b="$(i18n_blob "$D" "$d")"; line="<!-- i18n-source: $d.md blob:$b -->"
      for l in ${3:-${DOC_LANGS_I18N[*]}}; do
        f="$D/$l/$d.md"; [[ -f "$f" ]] || { echo "falta $f" >&2; exit 1; }
        if head -1 "$f" | grep -q '^<!-- i18n-source: '; then
          sed -i "1s|.*|$line|" "$f"
        else
          sed -i "1i $line" "$f"
        fi
        echo "$l/$d.md ← $b"
      done ;;
    *) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  esac
fi
