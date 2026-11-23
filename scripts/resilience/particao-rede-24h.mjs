#!/usr/bin/env node
// SCRUM-26 — Ensaio de partição de rede de 24h com buffer FIFO (17.280 pacotes).
//
// Fluxo: sobe um projeto Compose isolado -> confirma o link -> corta a rota gRPC no
// Toxiproxy durante a navegação -> acumula N pacotes em disco (geração acelerada) ->
// congela a coleta e fotografa o SQLite do barco (manifesto) -> religa o barco na
// cadência real -> restaura o link e mede a drenagem -> aguarda a fila SQS esvaziar ->
// audita o PostgreSQL pacote a pacote -> grava relatório JSON/Markdown.
//
// Uso: node scripts/resilience/particao-rede-24h.mjs --help

import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  AUDIT_SQL, evaluateCriteria, extractDeliveredIds, kibToMib, manifestToCsv, maxTimestamp, parseArgs,
  parseProcStatus, summarizeDrain, verifyDeliveryOrder, verifyManifest,
} from './lib/partition-audit.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const PROJECT = 'ferry-scrum26';
const COMPOSE = ['compose', '-p', PROJECT, '-f', 'docker-compose.local.yml', '-f', 'docker-compose.partition.yml'];
const BOAT_URL = `http://127.0.0.1:${process.env.PARTITION_BOAT_PORT ?? '3102'}`;
const TOXIPROXY_URL = `http://127.0.0.1:${process.env.PARTITION_TOXIPROXY_PORT ?? '8474'}`;
const PROXY = 'central-grpc';
const QUEUE_URL = 'http://localhost:4566/000000000000/ferry-db-writer-queue';
const DLQ_URL = `${QUEUE_URL}-dlq`;
const REAL_INTERVAL_MS = 5000;
const DB_USER = process.env.POSTGRES_USER ?? 'ferry';
const DB_NAME = process.env.TELEMETRY_DB ?? 'ferry_telemetry';

const HELP = `Ensaio de partição de rede de 24h (SCRUM-26)

  node scripts/resilience/particao-rede-24h.mjs [opções]

  --packets N              pacotes retidos durante a partição (padrão 17280 = 24h a cada 5s)
  --interval-ms N          cadência acelerada de coleta na partição (padrão 20ms)
  --mode blackhole|refuse  blackhole descarta bytes (zona sem sinal); refuse recusa conexões
  --boat-mem-growth-mib N  crescimento máx. de RSS do barco após encher a janela de RAM (padrão 64)
  --central-mem-ratio R    pico de RSS da Central/worker como fração do mem_limit (padrão 0.8)
  --drain-timeout-min N    tempo máx. de drenagem (padrão 90)
  --report-dir DIR         destino dos relatórios (padrão reports/scrum-26)
  --no-build               reaproveita imagens já construídas
  --keep                   mantém o projeto ${PROJECT} ativo ao final (inspeção manual)
`;

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const startedAt = Date.now();
const elapsed = () => `${((Date.now() - startedAt) / 1000).toFixed(0).padStart(5)}s`;
const log = (message) => console.log(`[${elapsed()}] ${message}`);

let intervalMs = 0; // cadência corrente injetada no Compose

function run(command, args, { input, allowFail = false, quiet = false } = {}) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(command, args, {
      cwd: ROOT,
      env: { ...process.env, PARTITION_TELEMETRY_INTERVAL_MS: String(intervalMs) },
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    const out = [];
    const err = [];
    child.stdout.on('data', (chunk) => out.push(chunk));
    child.stderr.on('data', (chunk) => { err.push(chunk); if (!quiet && process.env.DEBUG) process.stderr.write(chunk); });
    child.on('error', reject);
    child.on('close', (code) => {
      const stdout = Buffer.concat(out).toString('utf8');
      const stderr = Buffer.concat(err).toString('utf8');
      if (code !== 0 && !allowFail) {
        reject(new Error(`${command} ${args.join(' ').slice(0, 160)} falhou (${code}):\n${stderr.slice(-2000)}`));
      } else resolvePromise({ code, stdout, stderr });
    });
    child.stdin.end(input ?? '');
  });
}

const compose = (args, options) => run('docker', [...COMPOSE, ...args], options);

async function waitFor(label, probe, { timeoutMs, everyMs = 2000 }) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const value = await probe();
      if (value) return value;
    } catch (error) { lastError = error; }
    await sleep(everyMs);
  }
  throw new Error(`Tempo esgotado aguardando ${label}${lastError ? `: ${lastError.message}` : ''}`);
}

async function http(url, init) {
  const response = await fetch(url, { ...init, signal: AbortSignal.timeout(5000) });
  if (!response.ok) throw new Error(`${init?.method ?? 'GET'} ${url} -> ${response.status}`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

const boatStatus = () => http(`${BOAT_URL}/telemetry/buffer/status`);
const boatLatest = () => http(`${BOAT_URL}/telemetry/latest`);
const toxiproxy = (path, method = 'GET', body) => http(`${TOXIPROXY_URL}${path}`, {
  method, headers: { 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined,
});

async function cutLink(mode) {
  if (mode === 'refuse') {
    await toxiproxy(`/proxies/${PROXY}`, 'POST', { enabled: false });
    return;
  }
  for (const stream of ['upstream', 'downstream']) {
    await toxiproxy(`/proxies/${PROXY}/toxics`, 'POST', {
      name: `blackhole-${stream}`, type: 'timeout', stream, toxicity: 1, attributes: { timeout: 0 },
    });
  }
}

async function restoreLink(mode) {
  if (mode === 'refuse') {
    await toxiproxy(`/proxies/${PROXY}`, 'POST', { enabled: true });
    return;
  }
  for (const stream of ['upstream', 'downstream']) {
    await toxiproxy(`/proxies/${PROXY}/toxics/blackhole-${stream}`, 'DELETE');
  }
}

async function procMemory(service) {
  const { stdout } = await compose(['exec', '-T', service, 'cat', '/proc/1/status'], { quiet: true });
  return parseProcStatus(stdout);
}

async function containerHealth(service) {
  const { stdout: id } = await compose(['ps', '-a', '-q', service]);
  const { stdout } = await run('docker', ['inspect', id.trim()]);
  const [info] = JSON.parse(stdout);
  const limit = info.HostConfig?.Memory ?? 0;
  return {
    oomKilled: Boolean(info.State?.OOMKilled),
    restarts: Number(info.RestartCount ?? 0),
    running: Boolean(info.State?.Running),
    health: info.State?.Health?.Status ?? null,
    limitMib: limit > 0 ? Math.round(limit / 1048576) : null,
  };
}

async function queueDepth(queueUrl) {
  const { stdout } = await compose(['exec', '-T', 'localstack', 'awslocal', 'sqs', 'get-queue-attributes',
    '--queue-url', queueUrl, '--attribute-names', 'ApproximateNumberOfMessages',
    'ApproximateNumberOfMessagesNotVisible', '--output', 'json'], { quiet: true });
  const attributes = JSON.parse(stdout).Attributes ?? {};
  return Number(attributes.ApproximateNumberOfMessages ?? 0) +
    Number(attributes.ApproximateNumberOfMessagesNotVisible ?? 0);
}

// Lê o SQLite com o barco parado (o worker do buffer usa locking_mode=EXCLUSIVE).
const MANIFEST_SCRIPT = `
const { DatabaseSync } = require('node:sqlite');
const db = new DatabaseSync(process.env.BUFFER_BACKUP_PATH || '/app/data/telemetry-buffer.sqlite');
for (const row of db.prepare('SELECT ordinal, payload FROM pending ORDER BY ordinal').iterate()) {
  const p = JSON.parse(row.payload);
  process.stdout.write(JSON.stringify({
    ordinal: Number(row.ordinal), message_id: p.message_id, boat_id: p.boat_id,
    sequence_number: p.sequence_number, timestamp_coleta: p.timestamp_coleta,
    latitude: p.navegacao?.latitude ?? null, longitude: p.navegacao?.longitude ?? null,
    velocidade_nos: p.navegacao?.velocidade_nos ?? null, rumo_graus: p.navegacao?.rumo_graus ?? null,
  }) + '\\n');
}
db.close();
`;

async function extractManifest() {
  const { stdout } = await compose(['run', '--rm', '--no-deps', '-T', 'ferry-boat',
    'node', '--disable-warning=ExperimentalWarning', '-e', MANIFEST_SCRIPT]);
  return stdout.split('\n').filter((line) => line.startsWith('{')).map((line) => JSON.parse(line));
}

async function auditDatabase(manifest) {
  const args = ['exec', '-T', 'postgres', 'psql', '-U', DB_USER, '-d', DB_NAME,
    '-v', 'ON_ERROR_STOP=1', '-q', '-A', '-t'];
  for (const sql of AUDIT_SQL) args.push('-c', sql);
  const { stdout } = await compose(args, { input: manifestToCsv(manifest) });
  const line = stdout.trim().split('\n').filter(Boolean).at(-1);
  return JSON.parse(line);
}

function downsample(samples, max = 600) {
  if (samples.length <= max) return samples;
  const step = samples.length / max;
  return Array.from({ length: max }, (_, index) => samples[Math.floor(index * step)]);
}

function markdownReport(result) {
  const { options, criteria, evidence } = result;
  const lines = [
    '# SCRUM-26 — Ensaio de partição de rede de 24h',
    '',
    `- Execução: ${result.startedAt} (${result.durationMinutes} min)`,
    `- Resultado: **${criteria.ok ? 'APROVADO' : 'REPROVADO'}**`,
    `- Parâmetros: ${options.packets} pacotes, coleta acelerada a cada ${options.intervalMs}ms ` +
      `(${Math.round(REAL_INTERVAL_MS / options.intervalMs)}x), partição \`${options.mode}\``,
    '',
    '| Critério | Resultado | Evidência |',
    '| :--- | :---: | :--- |',
    ...criteria.criteria.map((item) => `| ${item.title} | ${item.ok ? 'OK' : 'FALHOU'} | ${item.detail} |`),
    '',
    '## Linha do tempo',
    '',
    `- Partição: ${evidence.partition.cutAt} -> restauração ${evidence.partition.restoredAt}`,
    `- Acúmulo: ${evidence.accumulation.seconds}s até ${evidence.manifest.size} pacotes ` +
      `(seq ${evidence.manifest.firstSequence}..${evidence.manifest.lastSequence})`,
    `- Circuit breaker do barco na partição: ${evidence.accumulation.circuitStatesSeen.join(', ') || 'n/d'}; ` +
      `CLOSED com ACK ${evidence.drain.circuitClosedAfterSeconds ?? 'n/d'}s após a restauração`,
    `- Drenagem: ${evidence.drain.seconds}s (${evidence.drain.packetsPerSecond} pacotes/s)`,
    `- Fila SQS: pico ${evidence.sqs.peakDepth} mensagens; esvaziada em ${evidence.sqs.seconds}s após a drenagem`,
  ];
  if (evidence.audit.samples?.length) {
    lines.push('', '## Amostras divergentes', '', '```json', JSON.stringify(evidence.audit.samples, null, 2), '```');
  }
  if (evidence.manifest.clockRegressions.length) {
    lines.push('', '## Observação: retrocessos do relógio de parede na origem', '',
      'O `timestamp_coleta` vem de `Date.now()` no barco; ressincronizações do relógio podem ' +
        'fazê-lo recuar alguns ms. A ordem FIFO segue a sequência, e a auditoria confirma ' +
        'que cada carimbo chegou idêntico à Central.', '',
      ...evidence.manifest.clockRegressions.map((r) => `- sequence_number=${r.sequence_number}: ${r.deltaMs} ms`));
  }
  if (evidence.manifest.problems.length) {
    lines.push('', '## Problemas no manifesto do buffer', '', ...evidence.manifest.problems.map((p) => `- ${p}`));
  }
  return lines.join('\n') + '\n';
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) { console.log(HELP); return 0; }
  intervalMs = options.intervalMs;
  const evidence = {};

  // 1. Ambiente isolado e limpo (somente volumes do projeto ferry-scrum26).
  log(`Preparando projeto ${PROJECT} (coleta acelerada a cada ${intervalMs}ms)...`);
  await compose(['down', '-v', '--remove-orphans'], { allowFail: true });
  await compose(['up', '-d', ...(options.build ? ['--build'] : [])]);

  try {
    await waitFor('Toxiproxy', () => toxiproxy('/version').then(() => true), { timeoutMs: 120_000 });
    await toxiproxy('/reset', 'POST');
    await waitFor('API do barco', () => http(`${BOAT_URL}/health`), { timeoutMs: 900_000, everyMs: 5000 });
    log('Barco no ar; aguardando a primeira confirmação da Central pelo proxy...');
    // Na coleta acelerada o barco gera mais rápido do que drena; o link é dado como
    // operacional pelo ACK confirmado, e o acúmulo pré-corte entra no manifesto.
    await waitFor('link gRPC operacional', async () => {
      const status = await boatStatus();
      return status.last_ack_at !== null &&
        status.state !== 'blocked' && status.state !== 'storage_error' && status;
    }, { timeoutMs: 600_000, everyMs: 3000 });
    const boatBaseline = await procMemory('ferry-boat');
    log(`Link operacional. RSS do barco: ${kibToMib(boatBaseline.rssKiB)} MiB`);

    // 2. Partição durante a navegação.
    const latestBeforeCut = await boatLatest();
    await cutLink(options.mode);
    const cutAt = Date.now();
    evidence.partition = { cut: true, cutAt: new Date(cutAt).toISOString(), sequenceAtCut: latestBeforeCut.sequence_number };
    log(`Rota gRPC cortada (${options.mode}) após sequence_number=${latestBeforeCut.sequence_number}.`);

    // 3. Acúmulo contínuo: janela de RAM limitada, excedente em disco.
    const statesSeen = new Set();
    const circuitDuringPartition = new Set();
    const accumulationSamples = [];
    let maxMemoryCount = 0;
    let memoryLimit = 0;
    let rssAtWindow = null;
    let maxRssAfterWindow = null;
    let lastStatus;
    let lastRssAt = 0;
    const accumulationDeadline = Date.now() + options.packets * options.intervalMs * 4 + 600_000;
    while (true) {
      if (Date.now() > accumulationDeadline) throw new Error('Tempo esgotado no acúmulo do buffer.');
      lastStatus = await boatStatus();
      statesSeen.add(lastStatus.state);
      if (lastStatus.circuit_state) circuitDuringPartition.add(lastStatus.circuit_state);
      memoryLimit = lastStatus.memory_limit;
      maxMemoryCount = Math.max(maxMemoryCount, lastStatus.memory_count);
      const sample = { t: Date.now() - cutAt, pending: lastStatus.pending_count,
        memory: lastStatus.memory_count, disk: lastStatus.disk_count, state: lastStatus.state,
        circuit: lastStatus.circuit_state ?? null };
      if (Date.now() - lastRssAt > 5000) {
        lastRssAt = Date.now();
        const memory = await procMemory('ferry-boat');
        sample.rssMib = kibToMib(memory.rssKiB);
        if (lastStatus.pending_count >= memoryLimit) {
          rssAtWindow ??= memory.rssKiB;
          maxRssAfterWindow = Math.max(maxRssAfterWindow ?? 0, memory.rssKiB);
        }
      }
      accumulationSamples.push(sample);
      if (accumulationSamples.length % 15 === 1) {
        log(`Buffer: ${lastStatus.pending_count}/${options.packets} pendentes ` +
          `(RAM ${lastStatus.memory_count}, disco ${lastStatus.disk_count}, estado ${lastStatus.state})`);
      }
      if (lastStatus.state === 'storage_error' || lastStatus.state === 'blocked') {
        throw new Error(`Buffer entrou em ${lastStatus.state}: ${JSON.stringify(lastStatus.last_error)}`);
      }
      if (lastStatus.pending_count >= options.packets) break;
      await sleep(2000);
    }
    const boatAfterAccumulation = await procMemory('ferry-boat');
    if (rssAtWindow !== null) maxRssAfterWindow = Math.max(maxRssAfterWindow, boatAfterAccumulation.rssKiB);
    evidence.accumulation = {
      seconds: Math.round((Date.now() - cutAt) / 1000),
      statesSeen: [...statesSeen],
      circuitStatesSeen: [...circuitDuringPartition],
      memoryLimit,
      maxMemoryCount,
      finalPending: lastStatus.pending_count,
      finalDiskCount: lastStatus.disk_count,
      rssBaselineMib: kibToMib(boatBaseline.rssKiB),
      rssAtWindowMib: rssAtWindow === null ? null : kibToMib(rssAtWindow),
      rssFinalMib: kibToMib(boatAfterAccumulation.rssKiB),
      rssPeakMib: kibToMib(boatAfterAccumulation.hwmKiB),
      rssGrowthAfterWindowMib: rssAtWindow === null ? null : kibToMib(maxRssAfterWindow - rssAtWindow),
      samples: downsample(accumulationSamples),
    };
    log(`Meta atingida: ${lastStatus.pending_count} pendentes (RAM ${lastStatus.memory_count}, ` +
      `disco ${lastStatus.disk_count}); RSS ${evidence.accumulation.rssFinalMib} MiB.`);

    // 4. Congela a coleta acelerada e fotografa o buffer persistido.
    await compose(['stop', 'ferry-boat']);
    const manifest = await extractManifest();
    const manifestCheck = verifyManifest(manifest, { expectedMinimum: options.packets });
    evidence.manifest = {
      size: manifest.length,
      firstSequence: manifest[0]?.sequence_number ?? null,
      lastSequence: manifest.at(-1)?.sequence_number ?? null,
      firstTimestamp: manifest[0]?.timestamp_coleta ?? null,
      lastTimestamp: manifest.at(-1)?.timestamp_coleta ?? null,
      ...manifestCheck,
    };
    log(`Manifesto do SQLite: ${manifest.length} pacotes, seq ${evidence.manifest.firstSequence}..` +
      `${evidence.manifest.lastSequence}${manifestCheck.ok ? '' : ` — ${manifestCheck.problems[0]}`}`);
    if (manifest.length === 0) throw new Error('Manifesto vazio: buffer não reteve pacotes.');
    const manifestMaxTs = maxTimestamp(manifest);

    // 5. Barco volta na cadência real (5s), ainda sem rede: o buffer deve sobreviver ao reinício.
    intervalMs = REAL_INTERVAL_MS;
    await compose(['up', '-d', '--no-deps', 'ferry-boat']);
    const restarted = await waitFor('barco após reinício', async () => {
      const status = await boatStatus();
      return status.pending_count > 0 && status;
    }, { timeoutMs: 600_000, everyMs: 3000 });
    evidence.restart = {
      pendingAfterRestart: restarted.pending_count,
      ok: restarted.pending_count >= manifest.length &&
        restarted.oldest_timestamp === String(manifest[0].timestamp_coleta),
    };
    log(`Barco reiniciado: ${restarted.pending_count} pendentes preservados (cabeça ${restarted.oldest_timestamp}).`);

    // 6. Restaura o link e mede a drenagem ordenada; Central/SQS amostrados em paralelo.
    const centralBaseline = await procMemory('ferry-central');
    await restoreLink(options.mode);
    const restoredAt = Date.now();
    evidence.partition.restored = true;
    evidence.partition.restoredAt = new Date(restoredAt).toISOString();
    log('Link restaurado; drenando...');

    const sqsSamples = [];
    const centralSamples = [];
    let peakDepth = 0;
    let sampling = true;
    const sampler = (async () => {
      while (sampling) {
        try {
          const [depth, central, worker] = await Promise.all([
            queueDepth(QUEUE_URL), procMemory('ferry-central'), procMemory('ferry-worker'),
          ]);
          peakDepth = Math.max(peakDepth, depth);
          const t = Date.now() - restoredAt;
          sqsSamples.push({ t, depth });
          centralSamples.push({ t, centralMib: kibToMib(central.rssKiB), workerMib: kibToMib(worker.rssKiB) });
        } catch (error) { centralSamples.push({ t: Date.now() - restoredAt, error: error.message }); }
        await sleep(3000);
      }
    })();

    const drainSamples = [];
    const drainDeadline = restoredAt + options.drainTimeoutMin * 60_000;
    let drainedAt = null;
    let drainError = null;
    let circuitClosedAt = null;
    while (Date.now() < drainDeadline) {
      const status = await boatStatus().catch(() => null);
      if (status) {
        drainSamples.push({ t: Date.now() - restoredAt, pending: status.pending_count,
          oldest: status.oldest_timestamp, state: status.state, circuit: status.circuit_state ?? null });
        // SCRUM-31: tempo até o circuit breaker voltar a CLOSED após a restauração.
        if (circuitClosedAt === null && status.circuit_state === 'CLOSED' && status.last_ack_at !== null &&
          Number(status.last_ack_at) >= restoredAt) circuitClosedAt = Date.now();
        if (drainSamples.length % 30 === 1) log(`Drenagem: ${status.pending_count} pendentes (${status.state})`);
        if (status.state === 'blocked' || status.state === 'storage_error') {
          drainError = `${status.state}: ${JSON.stringify(status.last_error)}`;
          break;
        }
        if (status.pending_count === 0 ||
          (status.oldest_timestamp !== null && BigInt(status.oldest_timestamp) > manifestMaxTs)) {
          drainedAt = Date.now();
          break;
        }
      }
      await sleep(1000);
    }
    const drainSummary = summarizeDrain({
      manifestSize: manifest.length, restoredAt, drainedAt: drainedAt ?? Date.now(),
    });
    evidence.drain = { completed: drainedAt !== null, error: drainError, ...drainSummary,
      circuitClosedAfterSeconds: circuitClosedAt === null ? null : Math.round((circuitClosedAt - restoredAt) / 100) / 10,
      samples: downsample(drainSamples) };
    log(drainedAt ? `Buffer drenado em ${drainSummary.seconds}s (${drainSummary.packetsPerSecond} pacotes/s).`
      : `Drenagem incompleta: ${drainError ?? 'tempo esgotado'}.`);

    // 7. Aguarda o worker esvaziar a fila SQS antes de auditar o banco.
    const sqsStart = Date.now();
    let finalDepth = await queueDepth(QUEUE_URL);
    let zeroStreak = 0;
    while (Date.now() - sqsStart < 600_000) {
      finalDepth = await queueDepth(QUEUE_URL);
      zeroStreak = finalDepth === 0 ? zeroStreak + 1 : 0;
      if (zeroStreak >= 3) break;
      await sleep(2000);
    }
    sampling = false;
    await sampler;
    const dlq = await queueDepth(DLQ_URL);
    evidence.sqs = {
      peakDepth, finalDepth, dlq, drained: finalDepth === 0,
      seconds: Math.round((Date.now() - sqsStart) / 1000), samples: downsample(sqsSamples),
    };
    log(`Fila SQS: pico ${peakDepth}, final ${finalDepth}, DLQ ${dlq}.`);

    // 8. Ordem FIFO observada nos ACKs do barco.
    const { stdout: boatLogs } = await compose(['logs', '--no-log-prefix', '--no-color', 'ferry-boat'], { quiet: true });
    evidence.order = verifyDeliveryOrder(extractDeliveredIds(boatLogs), manifest);

    // 9. Auditoria de integridade no PostgreSQL.
    evidence.audit = await auditDatabase(manifest);
    log(`Auditoria: ${evidence.audit.found}/${evidence.audit.expected} pacotes; ` +
      `seq≠ ${evidence.audit.sequence_mismatch}, ts≠ ${evidence.audit.timestamp_mismatch}, ` +
      `payload≠ ${evidence.audit.payload_mismatch}.`);

    // 10. Saúde de memória da Central e do worker durante a drenagem.
    evidence.central = [];
    for (const [service, baseline] of [['ferry-central', centralBaseline], ['ferry-worker', null]]) {
      const health = await containerHealth(service);
      const memory = health.running ? await procMemory(service) : null;
      const sampled = centralSamples.map((s) => (service === 'ferry-central' ? s.centralMib : s.workerMib))
        .filter((value) => typeof value === 'number');
      evidence.central.push({
        name: service, ...health,
        baselineMib: baseline ? kibToMib(baseline.rssKiB) : sampled[0] ?? null,
        peakMib: memory ? kibToMib(memory.hwmKiB) : Math.max(0, ...sampled),
        sampledPeakMib: sampled.length ? Math.max(...sampled) : null,
      });
    }
    evidence.centralSamples = downsample(centralSamples);

    const criteria = evaluateCriteria(evidence, options);
    const result = {
      ticket: 'SCRUM-26', startedAt: new Date(startedAt).toISOString(),
      durationMinutes: Math.round((Date.now() - startedAt) / 6000) / 10,
      options, criteria, evidence,
    };
    const stamp = result.startedAt.replace(/[:.]/g, '-');
    const reportDir = resolve(ROOT, options.reportDir, stamp);
    mkdirSync(reportDir, { recursive: true });
    writeFileSync(join(reportDir, 'resultado.json'), JSON.stringify(result, null, 2));
    writeFileSync(join(reportDir, 'relatorio.md'), markdownReport(result));
    writeFileSync(join(reportDir, 'manifesto.csv'),
      'ordinal,message_id,boat_id,sequence_number,timestamp_coleta,latitude,longitude,velocidade_nos,rumo_graus\n' +
      manifestToCsv(manifest));

    console.log('');
    for (const item of criteria.criteria) console.log(`${item.ok ? '✔' : '✘'} ${item.title}\n    ${item.detail}`);
    console.log(`\n${criteria.ok ? 'APROVADO' : 'REPROVADO'} — relatório em ${reportDir}`);
    return criteria.ok ? 0 : 1;
  } finally {
    if (options.keep) {
      log(`Projeto mantido. Para remover: docker ${COMPOSE.join(' ')} down -v`);
    } else {
      log('Removendo projeto isolado...');
      await compose(['down', '-v', '--remove-orphans'], { allowFail: true });
    }
  }
}

main().then((code) => { process.exitCode = code; }).catch((error) => {
  console.error(`\nEnsaio interrompido: ${error.message}`);
  process.exitCode = 2;
});
