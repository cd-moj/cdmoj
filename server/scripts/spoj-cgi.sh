#This file is part of CD-MOJ.
#
#CD-MOJ is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#CD-MOJ is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with CD-MOJ.  If not, see <http://www.gnu.org/licenses/>.

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
