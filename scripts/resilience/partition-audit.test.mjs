import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  AUDIT_SQL, PACKETS_24H, evaluateAudit, evaluateCriteria, extractDeliveredIds, manifestToCsv, maxTimestamp,
  parseArgs, parseProcStatus, summarizeDrain, verifyDeliveryOrder, verifyManifest,
} from './lib/partition-audit.mjs';

const row = (index, overrides = {}) => ({
  ordinal: 100 + index,
  message_id: `id-${index}`,
  boat_id: 'ferry-ivete-sangalo',
  sequence_number: String(500 + index),
  timestamp_coleta: String(1_763_640_000_000 + index * 20),
  latitude: -12.97 + index / 1e6,
  longitude: -38.5,
  velocidade_nos: 12.5,
  rumo_graus: 270,
  ...overrides,
});

test('24h a cada 5s equivalem a 17.280 pacotes', () => {
  assert.equal(PACKETS_24H, (24 * 3600) / 5);
});

test('parseArgs aplica padrões e valida opções', () => {
  const defaults = parseArgs([]);
  assert.equal(defaults.packets, 17280);
  assert.equal(defaults.mode, 'blackhole');
  assert.equal(defaults.build, true);

  const custom = parseArgs(['--packets', '1000', '--interval-ms', '10', '--mode', 'refuse', '--keep', '--no-build']);
  assert.deepEqual(
    [custom.packets, custom.intervalMs, custom.mode, custom.keep, custom.build],
    [1000, 10, 'refuse', true, false],
  );
  assert.throws(() => parseArgs(['--mode', 'cut']), /blackhole ou refuse/);
  assert.throws(() => parseArgs(['--packets', '0']), /positivo/);
  assert.throws(() => parseArgs(['--packets']), /exige um valor/);
  assert.throws(() => parseArgs(['--central-mem-ratio', '1.5']), /\(0, 1\]/);
  assert.throws(() => parseArgs(['--foo']), /desconhecida/);
});

test('parseProcStatus lê RSS atual e pico', () => {
  const status = 'Name:\tnode\nVmHWM:\t  204800 kB\nVmRSS:\t  102400 kB\nThreads:\t11\n';
  assert.deepEqual(parseProcStatus(status), { rssKiB: 102400, hwmKiB: 204800 });
  assert.throws(() => parseProcStatus('Name: node'), /VmRSS/);
});

test('verifyManifest aceita sequência contígua e ordenada', () => {
  const rows = Array.from({ length: 5 }, (_, index) => row(index));
  assert.deepEqual(verifyManifest(rows, { expectedMinimum: 5 }), { ok: true, problems: [], clockRegressions: [] });
});

test('verifyManifest acusa perda, duplicidade, desordem e volume insuficiente', () => {
  const gap = [row(0), row(1), row(3)];
  assert.match(verifyManifest(gap, { expectedMinimum: 3 }).problems[0], /lacuna de sequência entre 501 e 503/);

  const duplicate = [row(0), row(1, { message_id: 'id-0' })];
  assert.match(verifyManifest(duplicate, { expectedMinimum: 2 }).problems.join(), /duplicado/);

  const unordered = [row(0), row(1, { ordinal: 99 })];
  assert.match(verifyManifest(unordered, { expectedMinimum: 2 }).problems.join(), /ordinal fora de ordem/);

  assert.match(verifyManifest([row(0)], { expectedMinimum: 17280 }).problems[0], /esperado >= 17280/);
});

test('verifyManifest registra retrocesso do relógio de parede sem reprovar', () => {
  // Caso real do ensaio de 17.280 pacotes: o relógio recuou 5ms entre duas coletas.
  const rows = [row(0), row(1), row(2, { timestamp_coleta: String(1_763_640_000_000 + 15) }), row(3)];
  const result = verifyManifest(rows, { expectedMinimum: 4 });
  assert.equal(result.ok, true);
  assert.deepEqual(result.clockRegressions, [{ sequence_number: '502', deltaMs: -5 }]);
  assert.equal(maxTimestamp(rows), 1_763_640_000_060n);
});

test('extractDeliveredIds lê eventos do log do Nest, com ou sem ANSI', () => {
  const logs = [
    '[Nest] 1  - 11/20/2026 LOG [FifoBufferService] {"event":"buffer.delivered","message_id":"a","pending_count":2}',
    '\u001b[32m{"event":"buffer.delivered","message_id":"b","pending_count":1}\u001b[39m',
    '[Nest] 1  - LOG [GpsSimulatorService] {"event":"telemetry.generated","packet_id":"z"}',
  ].join('\n');
  assert.deepEqual(extractDeliveredIds(logs), ['a', 'b']);
});

test('verifyDeliveryOrder exige todos os pacotes do manifesto em ordem FIFO', () => {
  const manifest = [row(0), row(1), row(2)];
  assert.equal(verifyDeliveryOrder(['x', 'id-0', 'id-1', 'id-1', 'id-2', 'y'], manifest).ok, true);

  const swapped = verifyDeliveryOrder(['id-1', 'id-0', 'id-2'], manifest);
  assert.equal(swapped.ok, false);
  assert.equal(swapped.outOfOrder, 1);
  assert.equal(swapped.firstViolation, 'id-0');

  const missing = verifyDeliveryOrder(['id-0', 'id-2'], manifest);
  assert.deepEqual([missing.ok, missing.delivered, missing.expected], [false, 2, 3]);
});

test('summarizeDrain mede a taxa de drenagem', () => {
  assert.deepEqual(summarizeDrain({ manifestSize: 17280, restoredAt: 1000, drainedAt: 865_000 }),
    { seconds: 864, packetsPerSecond: 20 });
});

test('manifestToCsv segue a ordem de colunas do COPY da auditoria', () => {
  const csv = manifestToCsv([row(0, { rumo_graus: null })]);
  assert.equal(csv, '100,id-0,ferry-ivete-sangalo,500,1763640000000,-12.97,-38.5,12.5,\n');
  const columns = AUDIT_SQL[0].match(/\(([\s\S]*)\)/)[1].split(',').map((column) => column.trim().split(/\s+/)[0]);
  assert.deepEqual(columns, ['ordinal', 'packet_id', 'boat_id', 'sequence_number', 'timestamp_ms',
    'latitude', 'longitude', 'velocidade_nos', 'rumo_graus']);
});

test('evaluateAudit só aprova correspondência integral', () => {
  const perfect = { expected: 10, found: 10, missing: 0, boat_mismatch: 0, sequence_mismatch: 0,
    timestamp_mismatch: 0, payload_mismatch: 0 };
  assert.deepEqual(evaluateAudit(perfect), { ok: true, failures: [] });
  assert.deepEqual(evaluateAudit({ ...perfect, found: 9, missing: 1 }).failures, ['missing']);
  assert.deepEqual(evaluateAudit({ ...perfect, sequence_mismatch: 10 }).failures, ['sequence_mismatch']);
  assert.equal(evaluateAudit({ ...perfect, expected: 0, found: 0 }).ok, false);
});

function passingEvidence() {
  return {
    partition: { cut: true, restored: true },
    accumulation: { statesSeen: ['idle', 'draining', 'offline'], memoryLimit: 5000, maxMemoryCount: 5000,
      finalDiskCount: 12280, rssGrowthAfterWindowMib: 12 },
    manifest: { ok: true, size: 17280 },
    restart: { ok: true, pendingAfterRestart: 17281 },
    drain: { completed: true, packetsPerSecond: 20, seconds: 864 },
    order: { ok: true, delivered: 17280, expected: 17280, outOfOrder: 0 },
    audit: { expected: 17280, found: 17280, missing: 0, boat_mismatch: 0, sequence_mismatch: 0,
      timestamp_mismatch: 0, payload_mismatch: 0 },
    central: [
      { name: 'ferry-central', oomKilled: false, restarts: 0, limitMib: 512, peakMib: 140 },
      { name: 'ferry-worker', oomKilled: false, restarts: 0, limitMib: 512, peakMib: 120 },
    ],
    sqs: { drained: true, dlq: 0, peakDepth: 40, finalDepth: 0 },
  };
}

test('evaluateCriteria aprova os cinco critérios de aceite', () => {
  const result = evaluateCriteria(passingEvidence(), parseArgs([]));
  assert.equal(result.ok, true);
  assert.deepEqual(result.criteria.map((item) => item.id),
    ['particao', 'acumulo', 'drenagem', 'integridade', 'central']);
});

test('evaluateCriteria reprova cada desvio no critério correspondente', () => {
  const options = parseArgs([]);
  const failing = (mutate) => {
    const evidence = passingEvidence();
    mutate(evidence);
    return evaluateCriteria(evidence, options).criteria.filter((item) => !item.ok).map((item) => item.id);
  };
  assert.deepEqual(failing((e) => { e.accumulation.statesSeen.push('blocked'); }), ['particao']);
  assert.deepEqual(failing((e) => { e.accumulation.maxMemoryCount = 5001; }), ['acumulo']);
  assert.deepEqual(failing((e) => { e.accumulation.rssGrowthAfterWindowMib = 200; }), ['acumulo']);
  assert.deepEqual(failing((e) => { e.accumulation.finalDiskCount = 0; }), ['acumulo']);
  assert.deepEqual(failing((e) => { e.restart.ok = false; }), ['acumulo']);
  assert.deepEqual(failing((e) => { e.order.ok = false; }), ['drenagem']);
  assert.deepEqual(failing((e) => { e.drain.completed = false; }), ['drenagem']);
  assert.deepEqual(failing((e) => { e.audit.sequence_mismatch = 3; }), ['integridade']);
  assert.deepEqual(failing((e) => { e.central[0].oomKilled = true; }), ['central']);
  assert.deepEqual(failing((e) => { e.central[1].peakMib = 450; }), ['central']);
  assert.deepEqual(failing((e) => { e.sqs.dlq = 1; }), ['central']);
});
