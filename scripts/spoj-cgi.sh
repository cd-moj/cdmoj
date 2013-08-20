function link-prob-spoj()
{
  local SITE=$1
  local PROBID=$2
  echo "http://$SITE.spoj.com/problems/$2"
}
function link-prob-spoj-br()
{
  link-prob-spoj br $1
}

function link-prob-spoj-www()
{
  link-prob-spoj www $1
}
