#!/bin/bash
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

source common.sh

mkdir -p $CACHEDIR/webCat && printf "HTTP/1.1 200 OK\n\n<!doctype html><h2>Erez's netcat chat server!!</h2><form>Username:<br><input type=\"text\" name=\"username\"><br>Message:<br><input type=\"text\" name=\"message\"><div><button>Send data</button></div><button http-equiv=\"refresh\" content=\"0; url=$BASEURL:80\">Refresh</button></form>" > $CACHEDIR/webCat/webpage
while [ 1 ]
do
    [[ $(head -1 $CACHEDIR/webCat/r) =~ "GET /?username" ]] && USER=$(head -1 $CACHEDIR/webCat/r | sed 's@.*username=@@' | sed 's@&message.*@@') && MSG=$(head -1 $CACHEDIR/webCat/r | sed 's@.*message=@@' | sed 's@HTTP.*@@')
    [ ${#USER} -gt 1 ] && [ ${#MSG} -gt 1 ] && [ ${#USER} -lt 30 ] && [ ${#MSG} -lt 280 ] && printf "\n%s\t%s\n" "$USER" "$MSG" && printf "<h1>%s\t%s" "$USER" "$MSG" >> $CACHEDIR/webCat/webpage
    cat $CACHEDIR/webCat/webpage | timeout 1 nc -l 1234 > $CACHEDIR/webCat/r
    unset USER && unset MSG
done