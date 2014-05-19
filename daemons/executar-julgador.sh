source #CONFDIR#/judge.conf

cd $SUBMISSIONDIR

while true; do
	if (( $(ls |wc -l) == 0 )); then
		printf "."
		sleep 3
		continue
	fi
	bash ~/opt/judge/julgador.sh
done
