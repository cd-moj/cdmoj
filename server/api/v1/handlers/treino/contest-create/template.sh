# GET /treino/contest-create/template  (auth treino, pode criar) -> baixa template JSON do contest
# COMPLETO: documenta todos os campos que POST /treino/contest-create/create aceita.
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
  "_ajuda": "Template de contest do MOJ. Preencha e crie via POST /api/v1/treino/contest-create/create (JSON), OU empacote este arquivo como contest.json dentro de um .tar.gz (com uma pasta enunciados/ opcional) e envie em POST /api/v1/treino/contest-create/import como {\"tar_b64\": \"<tar.gz em base64>\"}. Datas em EPOCH (segundos). Campos com _ sao comentarios: remova-os antes de enviar. Todo campo opcional pode ser omitido.",
  "id": "meu-contest-2026",
  "name": "Meu Contest 2026",
  "mode": "icpc",
  "_mode": "icpc | obi | treino | heuristic (mode 'outro' e exclusivo de admin do treino)",
  "priority": "lista-publica",
  "_priority": "prioridade no escalonador de julgamento: prova | lista-privada | lista-publica ('super' e exclusivo de admin do treino)",
  "start": 0,
  "end": 0,
  "languages": ["c", "cpp", "py3"],
  "_languages": "whitelist de linguagens do contest (ids canonicos minusculos; [] ou omitido = todas). String legada tipo \"C CPP\" tambem e aceita",
  "showcode": false,
  "_toggles": "os campos abaixo espelham /contest/admin/settings; so mande o que quer MUDAR do default",
  "show_log": true,
  "show_editor": true,
  "show_tl": true,
  "allow_backup": true,
  "allow_print": true,
  "score_anon": false,
  "manual_verdict": false,
  "secret": false,
  "_secret": "SUPER SECRETO: fora das listagens publicas (home/arquivo/status) e o placar/visual exigem login no contest. A tela de login continua funcionando p/ quem tem o link",
  "allow_late": false,
  "_allow_late": "auto-cadastro de atrasados; mode=treino liga sozinho se voce nao mandar o campo",
  "login_ua_substring": "",
  "_login_ua_substring": "gate de login por substring do User-Agent (ex.: MOJBOX); vazio = sem gate",
  "score_full_users": [],
  "_score_full_users": "logins que veem o placar COMPLETO (sem freeze) alem de .admin/.judge",
  "locale": "pt",
  "login_start": 0,
  "_login_start": "abertura do login (EPOCH); 0/omitido = sempre aberto",
  "login_enabled": true,
  "freeze": 0,
  "_freeze": "congelamento do placar (EPOCH); 0/omitido = sem freeze",
  "admin": { "login": "professor", "password": "", "fullname": "Professor" },
  "_admin": "conta admin do contest (sufixo .admin e forcado; senha vazia = gerada). Obrigatorio na web; opcional aqui (default: <seu-login>.admin)",
  "users_from": "",
  "_users_from": "compartilhar usuarios de outro contest (ex.: treino). Alternativa: users[] abaixo",
  "users": [
    { "login": "aluno1", "password": "", "fullname": "Aluno Um", "email": "" }
  ],
  "colors": { "A": "FF0000", "B": "00FF00" },
  "_colors": "cores dos baloes por letra (RRGGBB); aceita tambem enableSonic:true",
  "regions": [ { "name": "Turma A", "regex": "^ta-" } ],
  "teams_meta": [ { "regex": "^br-", "country": "BR", "school": "UnB" } ],
  "problems": [
    { "_dica": "do banco publico: informe bank_id (id do problema no treino, com # no lugar de /)", "bank_id": "monitores#ola-no-mundo-das-regex", "name": "Ola no Mundo das RegEx", "letter": "A" },
    { "_dica": "problema NAO publico: informe source e problem_id (voce precisa ter acesso: dono/colaborador)", "source": "cdmoj", "problem_id": "secreto/meu-problema", "name": "Meu Problema", "letter": "B", "languages": ["c"], "_languages": "whitelist POR problema (opcional; vazio herda do contest)" },
    { "_dica": "enunciado personalizado: statement_file/statement_pdf_file (arquivo dentro de enunciados/ no tar) OU statement_b64/statement_pdf_b64 (conteudo em base64)", "source": "cdmoj", "problem_id": "secreto/outro", "name": "Outro Problema", "letter": "C", "statement_file": "outro.html", "statement_pdf_file": "outro.pdf" }
  ]
}
JSON
