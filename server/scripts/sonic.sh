
function createsonicfile()
{
  local contest=$1
  local PROB=$2
  local ID=$3
  local TIMELOGIN=$4
  local SUBMITTYPE=$5
  local RANKDIR="$CONTESTSDIR/$contest/running"
  mkdir -p $RANKDIR
  local SONIC=("<img  width=50px src='https://media.tenor.com/RvCf_01rx-YAAAAi/sonic-the-hedgehog-prey-fnf.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/0d9u7FDYIyMAAAAi/sonic.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/WIEKeqWCP5UAAAAi/srb2kart-sonic.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/VEp3WM5DV3UAAAAi/sonic.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/RyDqT7JsYxAAAAAj/sanic-dance-sanic.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/d7jgDuI-rjIAAAAj/sonic-the-hedgehog-sonic.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/FAUhgUjW2VoAAAAj/sonic.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/SI9Z-5BNjzsAAAAj/sonic-fnf.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/NIVbXrmMPNwAAAAj/sonic-advance.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/sSIORuWA99AAAAAj/sonic-the-hedgehog.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/-f39UNfUasoAAAAj/sonic-the-hedgehog.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/7pVopZZ9VagAAAAj/sonic3-sonic.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/hO325th5zlkAAAAj/fnf-sonic.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/F-OLy-dTBQIAAAAi/sonic-fortnite-dance.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/w2MnXF-FiPwAAAAj/sonic-pushing-retro-old-sth.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/42FLUDoGy58AAAAj/sonic-ring-sonic.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/BgRhHvJtmZwAAAAj/sanic-weird.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/osjfCirlN4MAAAAj/sonic-the-hedgehog.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/XDn1FGmrwlEAAAAj/sonic-the-hedgehog.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/M46uN9EhkAwAAAAj/fortnite-pixel.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/EyjY9IVeyegAAAAj/sonic-holds-on.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/IyKvqYp5DW8AAAAj/sonic-the-hedgehog.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/_bMflfsK-pkAAAAj/sonic-the-hedgehog.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/jA7VHRE-f-QAAAAj/tails-sonic-tails.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/HdPg4vrZJwwAAAAj/super-sonic-in-sonic1.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/If2ncKAUATcAAAAj/sonic-wow.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/iM7gI7yiV3MAAAAj/knuckles-dancing.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/5frl25WiIZMAAAAj/superknuckles-sonic.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/c8iSzIs3if0AAAAj/sonic-the.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/CPoRb3M0JXMAAAAj/tails-sonic-tails.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/1omfDli6KCEAAAAj/sonic-sonic-the-hedgehog.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/weesaMMiVVMAAAAj/sonic.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/e94GdKRbWkAAAAAj/sega-the-death-egg.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/8dV75SPpJWgAAAAj/sonic-the-hedgehog-sonic-mania.gif'>" )
  SONIC+=( "<img width=50px src='https://media.tenor.com/k1adCGAcWmEAAAAj/fleetway-super-sonic.gif'>" )
  #how dare you
  SONIC+=( "<img width=100px src='https://media.tenor.com/aFxaR-xnilkAAAAj/sonic-fear.gif'>" )
  #sonic for running
  SONIC+=( "<img width=100px src='https://media.tenor.com/enihTZnEU9MAAAAj/sonic-fnf.gif'>" )
  REGERARTABELA=0
  #encontrar todos as submissões aceitas dos times.
  local MAPACOUNT
  local MAPACOUNTPORPROB
  local PROBNAMEx
  local BIGRANK=""
  PROBNAMEx[$PROB]=${PROBS[2+$PROB]}
  TIME=$CONTESTSDIR/$contest/data/$TIMELOGIN
  [[ "$TIMELOGIN" =~ "admin" ]] && return
  local sonicchoose=$((RANDOM%(${#SONIC[@]}-2)))
  local REJULSTR=""
  [[ "$SUBMITTYPE" == "REJULGANDO" ]] && REJULSTR="(REJULGANDO)"
  [[  -e ~moj/contests/$contest/mojlog/$ID ]] && REJULSTR+="(JULGANDO desde $(stat -c %y ~moj/contests/$contest/mojlog/$ID))" && sonicchoose=$((${#SONIC[@]}-1))
  echo "${SONIC[$sonicchoose]} <blink>${PROBNAMEx[$PROB]}</blink> $REJULSTR - <b>$(grep $TIMELOGIN $RANKDIR/../passwd|cut -d: -f3)</b> desde $(date --date=@${ID%:??*} )<br>" > $RANKDIR/$ID
}
