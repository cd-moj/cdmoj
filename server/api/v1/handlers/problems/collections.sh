# GET /problems/collections   (Bearer)
# Lista as coleções (curso/diretório) com contagem total e quantos já são públicos.
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
owners_emit '
  { success:true,
    collections: ( [ .problems[] | {c:.collections[], pub:.public} ]
      | group_by(.c)
      | map({ name: .[0].c, count: length, public: ([.[]|select(.pub)]|length) })
      | sort_by(-.count) ) }
'
