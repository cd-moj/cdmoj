# POST /problems/publish  — **DEPRECADO**: alias de /problems/validate.
# O nome era enganoso: esta rota NUNCA publicou nada (não toca no flag `public` — quem publica é o
# /problems/set-public, que checa a trava `public_allowed` da org). Ela roda o portão de qualidade
# (validação estática + índice) e pede calibração. Mantido só para clientes antigos.
source "$_DIR/handlers/problems/validate.sh"
