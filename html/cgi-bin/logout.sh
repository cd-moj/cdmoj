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
AGORA=$(date +%s)

printf "Set-Cookie: login=$LOGIN; Path=/;  expires=$(date --date=@$AGORA)\n"
printf "Set-Cookie: hash=0000; Path=/; expires=$(date --date=@$AGORA)\n"
printf "Content-type: text/html\n\n"
cat << EOF
<script type="text/javascript">
  top.location.href = "$BASEURL"
</script>

EOF
