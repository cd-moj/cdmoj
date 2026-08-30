# ingest.rb — o ingest-drain em ruby (JSON core em C, File.rename atômico,
# unpack1("m") p/ base64 — semântica completa, paridade com o python).
require 'json'
RUN = ENV['RUNDIR']; CTS = ENV['CONTESTSDIR']
SPOOL = "#{RUN}/spool/submissions"; DONE = "#{RUN}/spool/submissions-done"
now = Time.now.to_i
Dir.children(SPOOL).select { |n| !n.start_with?('.') && n.split(':')[4] == 'result' }.sort.each do |base|
  path = "#{SPOOL}/#{base}"
  j = JSON.parse(File.read(path)) rescue next
  c = j['contest'].to_s; sid = j['id'].to_s; login = j['login'].to_s
  verdict = j['verdict'] || 'Judge Error'
  next if c == '_testrun' || c !~ /\A[A-Za-z0-9._-]+\z/ || sid.empty? || login.empty?
  udir = "#{CTS}/#{c}/users/#{login}"
  hf = "#{udir}/history"
  lines = File.read(hf).split("\n") rescue next
  sfx = ":#{sid}"
  idx = lines.index { |l| l.end_with?(sfx) }
  next unless idx
  p = lines[idx].split(':')
  next if p.size < 6
  lines[idx] = [p[0], p[1], p[2], verdict, p[-2], p[-1]].join(':')
  File.write("#{hf}.tmp.rb", lines.join("\n") + "\n"); File.rename("#{hf}.tmp.rb", hf)
  if (hb = j['report_html_b64'])
    File.binwrite("#{udir}/mojlog/.#{sid}.tmp", hb.unpack1('m'))
    File.rename("#{udir}/mojlog/.#{sid}.tmp", "#{udir}/mojlog/#{sid}.html")
  end
  res = j.reject { |k, _| k == 'report_html_b64' }
  res['report_html'] = "mojlog/#{sid}.html"; res['finalized_at'] = now
  body = JSON.generate(res)
  ["#{udir}/results/#{sid}.json", "#{RUN}/results/#{sid}.json"].each do |rf|
    File.write("#{rf}.tmp.rb", body); File.rename("#{rf}.tmp.rb", rf)
  end
  File.rename(path, "#{DONE}/#{base}")
end
