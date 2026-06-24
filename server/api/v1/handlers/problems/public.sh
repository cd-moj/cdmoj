# GET /problems/public   (Bearer)
# Problemas públicos (entram no treino livre): public==true. Visão de gestão (dono/autor
# por problema). A listagem anônima do treino continua em /treino/problems.
require_method GET
require_auth
source "$_DIR/lib/problems.sh"
owners_emit '{ success:true, problems: [ .problems[] | select(.public==true) ] }'
