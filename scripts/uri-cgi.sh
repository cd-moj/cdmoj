function link-prob-uri()
{
  local PROBID=$1
  echo "http://www.urionlinejudge.com.br/judge/problems/view/$PROBID"
}
function link-prob-uri-pdf()
{
  local PROBID=$1
  echo "http://www.urionlinejudge.com.br/urirepository/UOJ_${PROBID}.html"
}
