function link-prob-spoj()
{
  local SITE=$2
  if [[ "x$SITE" == "x" ]]; then
    SITE=www
  fi

  local PROBID=$1
  echo "http://$SITE.spoj.com/problems/$PROBID"
}
function link-prob-spoj-br()
{
  link-prob-spoj $1 br
}

function link-prob-spoj-www()
{
  link-prob-spoj $1 www
}

function link-prob-spoj-br-pdf()
{
  link-prob-spoj ${1}.pdf br
}

function link-prob-spoj-www-pdf()
{
  link-prob-spoj ${1}.pdf www
}
