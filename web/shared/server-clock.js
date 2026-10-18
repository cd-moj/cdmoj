// shared/server-clock.js — o RELÓGIO DO SERVIDOR no navegador (18/10/2026, relato do Daniel Saad na Maratona Padawan do IFB:
// duas máquinas de juízes mostravam tempos diferentes para o fim da prova — cada contagem usava o relógio do computador,
// e o do Windows estava adiantado em relação ao do Linux). Quem decide o início, o fim e o freeze é o servidor; a tela
// tem de contar pelo relógio DELE.
//
// Sem requisição a mais: toda resposta da API traz o cabeçalho `Date` (o nginx o põe em todas), e o `api.js` passa cada um
// por `noteServerDate`. O `Date` tem resolução de 1 s; cada amostra estima a diferença servidor − navegador pelo meio
// daquele segundo contra o meio da ida e volta, e vale a MEDIANA das últimas 15 (um valor fora da curva — rede lenta, um
// proxy — não puxa a estimativa). Erro típico abaixo de ~1 s: é o que uma contagem em segundos precisa.
// Funções PURAS + um estado de módulo; `noteServerDate` aceita os relógios por parâmetro (testável no gjs).

const MAX_SAMPLES = 15;
let samples = [];
let offsetMs = 0;            // servidor − navegador, em ms (0 até a 1ª resposta da API)

// noteServerDate(cabeçalho Date, t0, t1) — t0/t1 = Date.now() antes do fetch e quando os cabeçalhos chegaram
export function noteServerDate(dateHeader, t0, t1) {
  const d = Date.parse(dateHeader || '');
  if (!Number.isFinite(d) || !(t1 >= t0)) return offsetMs;
  const est = d + 500 - (t0 + t1) / 2;
  // só lixo fica de fora (50 anos): máquina de laboratório com a bateria da placa fraca anda MESES ou ANOS errada — e é
  // justamente ela que precisa da correção (a trava antiga, de 7 dias, a deixava no relógio dela; achado no Chrome headless)
  if (Math.abs(est) > 50 * 365 * 86400e3) return offsetMs;
  samples.push(est);
  if (samples.length > MAX_SAMPLES) samples.shift();
  const s = [...samples].sort((a, b) => a - b);
  offsetMs = s[Math.floor(s.length / 2)];
  return offsetMs;
}

export const serverOffsetMs = () => offsetMs;
// agora no relógio do servidor: em ms e em epoch (segundos, como os horários da API)
export const serverNowMs = () => Date.now() + offsetMs;
export const serverNow = () => Math.floor(serverNowMs() / 1000);
// só p/ testes
export function _resetServerClock() { samples = []; offsetMs = 0; }
