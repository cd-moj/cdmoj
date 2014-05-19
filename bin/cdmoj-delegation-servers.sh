source #CONFDIR#/judge.conf

if (( $# != 1 )); then
  printf "Uso: $0 <Number of Delegation Servers>\n"
  printf "   - Se 0, então desabilita os servidores de delegação e copia as\n"
  printf "     submissões pendentes para SUBMISSIONDIR-enviaroj/\n"
  exit 1
fi

TOTALSERVERS=$1

DIRS=$(ls -d $SUBMISSIONDIR/../cdmoj-delegation-server*|wc -l)

if (( DIRS == 0 )); then
  for((i=0;i< TOTALSERVERS;i++)); do
    mkdir -p $SUBMISSIONDIR/../cdmoj-delegation-server$i
  done

elif (( DIRS > TOTALSERVERS )); then
  for((i=TOTALSERVERS; i< DIRS; i++)); do
    mv $SUBMISSIONDIR/../cdmoj-delegation-server$i/* $SUBMISSIONDIR/../cdmoj-delegation-server0/
    rm -rf SUBMISSIONDIR/../cdmoj-delegation-server$i
  done

#para desabilitar os delegation servers as submissões pendentes devem ser
#remanejadas
elif (( TOTALSERVERS == 0 )); then
  for((i=0; i< DIRS; i++)); do
    mv $SUBMISSIONDIR/../cdmoj-delegation-server$i/* $SUBMISSIONDIR-enviaroj/
    rm -rf SUBMISSIONDIR/../cdmoj-delegation-server$i
  done

fi
