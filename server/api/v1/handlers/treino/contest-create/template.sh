# GET /treino/contest-create/template  (auth treino, pode criar) -> baixa template JSON do contest
require_method GET
require_auth_contest treino
source "$_LIBDIR/contest-create.sh"
cc_can_create "$SESSION_LOGIN" || fail 403 "Sem permissão para criar contest" "create_forbidden"
printf 'Status: 200 OK\r\n'
printf 'Content-Type: application/json; charset=utf-8\r\n'
printf 'Content-Disposition: attachment; filename="contest-template.json"\r\n'
printf '\r\n'
cat <<'JSON'
{
  "_ajuda": "Template de contest do MOJ. Preencha e crie via POST /api/v1/treino/contest-create (JSON), OU empacote este arquivo como contest.json dentro de um .tar.gz (com uma pasta enunciados/ opcional) e envie em POST /api/v1/treino/contest-create/import como {\"tar_b64\": \"<tar.gz em base64>\"}. Datas em EPOCH (segundos). Remova os campos com _ antes de enviar.",
  "id": "meu-contest-2026",
  "name": "Meu Contest 2026",
  "mode": "icpc",
  "start": 0,
  "end": 0,
  "languages": "",
  "showcode": false,
  "problems": [
    { "_dica": "do banco publico: informe bank_id (id do problema no treino, com # no lugar de /)", "bank_id": "monitores#ola-no-mundo-das-regex", "name": "Ola no Mundo das RegEx", "letter": "A" },
    { "_dica": "problema NAO publico: informe source e problem_id (voce precisa saber o id)", "source": "cdmoj", "problem_id": "secreto/meu-problema", "name": "Meu Problema", "letter": "B" },
    { "_dica": "enunciado personalizado: aponte statement_file (arquivo dentro de enunciados/ no tar) OU statement_b64 (HTML em base64)", "source": "cdmoj", "problem_id": "secreto/outro", "name": "Outro Problema", "letter": "C", "statement_file": "outro.html" }
  ]
}
JSON
