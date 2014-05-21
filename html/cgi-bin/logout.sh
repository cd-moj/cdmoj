#!/bin/bash
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
