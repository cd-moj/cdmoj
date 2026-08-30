#!/usr/bin/perl
# ingest.pl — o ingest-drain em perl (só core: JSON::PP parser real, MIME::Base64,
# rename() nativo ⇒ ATÔMICO como o python — semântica completa, sem as concessões do awk).
use strict; use warnings;
use JSON::PP; use MIME::Base64 qw(decode_base64);
my $RUN = $ENV{RUNDIR}; my $CTS = $ENV{CONTESTSDIR};
my $SPOOL = "$RUN/spool/submissions"; my $DONE = "$RUN/spool/submissions-done";
my $jp = JSON::PP->new;
opendir(my $dh, $SPOOL) or die;
my @names = sort grep { !/^\./ && (split /:/)[4] // '' eq 'result' } readdir($dh);
closedir $dh;
my $now = time;
for my $base (@names) {
  my $path = "$SPOOL/$base";
  open(my $fh, '<', $path) or next;
  my $raw = do { local $/; <$fh> };   # slurp CONFINADO: $/=undef no escopo do laço mataria o chomp do history
  close $fh;
  my $j = eval { $jp->decode($raw) } or next;
  my ($c, $sid, $login) = ($j->{contest}//'', $j->{id}//'', $j->{login}//'');
  my $verdict = $j->{verdict} // 'Judge Error';
  next if $c eq '_testrun' || $c !~ /^[A-Za-z0-9._-]+$/ || !$sid || !$login;
  my $udir = "$CTS/$c/users/$login";
  my $hf = "$udir/history";
  open($fh, '<', $hf) or next; my @lines = <$fh>; close $fh; chomp @lines;
  my $sfx = ":$sid"; my $idx = -1;
  for my $i (0..$#lines) { if (substr($lines[$i], -length($sfx)) eq $sfx) { $idx = $i; last } }
  next if $idx < 0;
  my @p = split /:/, $lines[$idx];
  next if @p < 6;
  $lines[$idx] = join(':', $p[0], $p[1], $p[2], $verdict, $p[-2], $p[-1]);
  open(my $o, '>', "$hf.tmp.pl") or next;
  print $o join("\n", @lines), "\n"; close $o;
  rename("$hf.tmp.pl", $hf) or next;
  if (my $hb = $j->{report_html_b64}) {
    if (open($o, '>', "$udir/mojlog/.$sid.tmp")) {
      print $o decode_base64($hb); close $o;
      rename("$udir/mojlog/.$sid.tmp", "$udir/mojlog/$sid.html");
    }
  }
  my %res = map { $_ => $j->{$_} } grep { $_ ne 'report_html_b64' } keys %$j;
  $res{report_html} = "mojlog/$sid.html"; $res{finalized_at} = $now;
  my $body = $jp->encode(\%res);
  for my $rf ("$udir/results/$sid.json", "$RUN/results/$sid.json") {
    open($o, '>', "$rf.tmp.pl") or next;
    print $o $body; close $o; rename("$rf.tmp.pl", $rf);
  }
  rename($path, "$DONE/$base");
}
