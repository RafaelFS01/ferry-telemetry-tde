// Regras puras do ensaio de partição (SCRUM-26): sem Docker, rede ou relógio.
// O script orquestrador coleta evidências; este módulo decide se elas aprovam.

export const PACKETS_24H = 17280; // 24h x 3600s / 5s de cadência nominal

const DEFAULTS = {
  packets: PACKETS_24H,
  intervalMs: 20,
  mode: 'blackhole',
  boatMemGrowthMib: 64,
  centralMemRatio: 0.8,
  drainTimeoutMin: 90,
  keep: false,
  build: true,
  reportDir: 'reports/scrum-26',
};

export function parseArgs(argv) {
  const options = { ...DEFAULTS };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const next = () => {
      const value = argv[index + 1];
      if (value === undefined || value.startsWith('--')) throw new Error(`${flag} exige um valor.`);
      index += 1;
      return value;
    };
    const positive = (value) => {
      const number = Number(value);
      if (!Number.isFinite(number) || number <= 0) throw new Error(`${flag} deve ser um número positivo.`);
      return number;
    };
    switch (flag) {
      case '--packets': options.packets = Math.trunc(positive(next())); break;
      case '--interval-ms': options.intervalMs = Math.trunc(positive(next())); break;
      case '--mode': {
        const mode = next();
        if (mode !== 'blackhole' && mode !== 'refuse') throw new Error('--mode aceita blackhole ou refuse.');
        options.mode = mode;
        break;
      }
      case '--boat-mem-growth-mib': options.boatMemGrowthMib = positive(next()); break;
      case '--central-mem-ratio': {
        const ratio = positive(next());
        if (ratio > 1) throw new Error('--central-mem-ratio deve estar em (0, 1].');
        options.centralMemRatio = ratio;
        break;
      }
      case '--drain-timeout-min': options.drainTimeoutMin = positive(next()); break;
      case '--report-dir': options.reportDir = next(); break;
      case '--keep': options.keep = true; break;
      case '--no-build': options.build = false; break;
      case '--help': case '-h': options.help = true; break;
      default: throw new Error(`Opção desconhecida: ${flag}`);
    }
  }
  return options;
}

// /proc/<pid>/status informa VmRSS (atual) e VmHWM (pico) em KiB.
export function parseProcStatus(text) {
  const read = (key) => {
    const match = new RegExp(`^${key}:\\s+(\\d+)\\s+kB$`, 'm').exec(text);
    return match ? Number(match[1]) : null;
  };
  const rssKiB = read('VmRSS');
  const hwmKiB = read('VmHWM');
  if (rssKiB === null || hwmKiB === null) throw new Error('VmRSS/VmHWM ausentes em /proc/1/status.');
  return { rssKiB, hwmKiB };
}

// Memória limite do cgroup (docker inspect HostConfig.Memory, em bytes; 0 = sem limite).
export function kibToMib(kib) { return Math.round((kib / 1024) * 10) / 10; }

// O manifesto é a fotografia do SQLite do barco ao fim da partição, em ordem de ordinal.
// A ordem FIFO é a do ordinal/sequência. timestamp_coleta vem do relógio de parede, que
// pode retroceder alguns ms em ressincronizações (NTP, VM do Docker Desktop): isso é
// registrado como observação, pois o critério é preservar o carimbo, não sua monotonicidade.
export function verifyManifest(rows, { expectedMinimum }) {
  const problems = [];
  const clockRegressions = [];
  if (rows.length < expectedMinimum) {
    problems.push(`manifesto com ${rows.length} pacotes; esperado >= ${expectedMinimum}`);
  }
  const ids = new Set();
  for (let index = 0; index < rows.length; index += 1) {
    const row = rows[index];
    if (ids.has(row.message_id)) problems.push(`message_id duplicado no buffer: ${row.message_id}`);
    ids.add(row.message_id);
    if (index === 0) continue;
    const previous = rows[index - 1];
    if (row.ordinal <= previous.ordinal) problems.push(`ordinal fora de ordem em ${row.message_id}`);
    if (BigInt(row.sequence_number) !== BigInt(previous.sequence_number) + 1n) {
      problems.push(`lacuna de sequência entre ${previous.sequence_number} e ${row.sequence_number}`);
    }
    const deltaMs = Number(BigInt(row.timestamp_coleta) - BigInt(previous.timestamp_coleta));
    if (deltaMs < 0 && clockRegressions.length < 20) {
      clockRegressions.push({ sequence_number: String(row.sequence_number), deltaMs });
    }
    if (problems.length >= 20) break;
  }
  return { ok: problems.length === 0, problems, clockRegressions };
}

export function maxTimestamp(rows) {
  return rows.reduce((max, row) => {
    const value = BigInt(row.timestamp_coleta);
    return value > max ? value : max;
  }, 0n);
}

// Ordem de entrega observada nos logs `buffer.delivered` do barco.
export function extractDeliveredIds(logText) {
  const ids = [];
  const pattern = /\{"event":"buffer\.delivered"[^}]*\}/g;
  for (const match of logText.matchAll(pattern)) {
    try {
      const event = JSON.parse(match[0]);
      if (typeof event.message_id === 'string') ids.push(event.message_id);
    } catch { /* linha truncada: ignorada, a contagem final acusa a falta */ }
  }
  return ids;
}

export function verifyDeliveryOrder(deliveredIds, manifest) {
  const position = new Map(manifest.map((row, index) => [row.message_id, index]));
  const seen = new Set();
  let last = -1;
  let outOfOrder = 0;
  let firstViolation = null;
  for (const id of deliveredIds) {
    const index = position.get(id);
    if (index === undefined || seen.has(id)) continue;
    seen.add(id);
    if (index < last) {
      outOfOrder += 1;
      firstViolation ??= id;
    }
    last = Math.max(last, index);
  }
  return {
    ok: outOfOrder === 0 && seen.size === manifest.length,
    delivered: seen.size,
    expected: manifest.length,
    outOfOrder,
    firstViolation,
  };
}

// Taxa de drenagem; a ordem é auditada pelos ACKs (verifyDeliveryOrder), não por timestamps.
export function summarizeDrain({ manifestSize, restoredAt, drainedAt }) {
  const seconds = Math.max(0.001, (drainedAt - restoredAt) / 1000);
  return {
    seconds: Math.round(seconds * 10) / 10,
    packetsPerSecond: Math.round((manifestSize / seconds) * 100) / 100,
  };
}

export function manifestToCsv(rows) {
  const value = (item) => (item === null || item === undefined ? '' : String(item));
  return rows.map((row) => [
    row.ordinal, row.message_id, row.boat_id, row.sequence_number, row.timestamp_coleta,
    row.latitude, row.longitude, row.velocidade_nos, row.rumo_graus,
  ].map(value).join(',')).join('\n') + '\n';
}

// SQL executado no psql: carrega o manifesto via COPY e compara cada pacote com a tabela telemetria.
export const AUDIT_SQL = [
  `CREATE TEMP TABLE manifesto (
     ordinal bigint, packet_id uuid, boat_id text, sequence_number bigint, timestamp_ms bigint,
     latitude double precision, longitude double precision,
     velocidade_nos double precision, rumo_graus double precision)`,
  'COPY manifesto FROM STDIN WITH (FORMAT csv)',
  `WITH auditoria AS (
     SELECT m.*, t.packet_id AS db_id, t.boat_id AS db_boat, t.sequence_number AS db_seq,
            round(extract(epoch FROM t."timestamp") * 1000)::bigint AS db_ts,
            t.latitude AS db_lat, t.longitude AS db_lon, t.speed_knots AS db_speed,
            t.course_heading AS db_heading
       FROM manifesto m LEFT JOIN telemetria t ON t.packet_id = m.packet_id)
   SELECT json_build_object(
     'expected', count(*),
     'found', count(db_id),
     'missing', count(*) FILTER (WHERE db_id IS NULL),
     'boat_mismatch', count(*) FILTER (WHERE db_id IS NOT NULL AND db_boat <> boat_id),
     'sequence_mismatch', count(*) FILTER (WHERE db_id IS NOT NULL AND db_seq <> sequence_number),
     'timestamp_mismatch', count(*) FILTER (WHERE db_id IS NOT NULL AND db_ts <> timestamp_ms),
     'payload_mismatch', count(*) FILTER (WHERE db_id IS NOT NULL AND (
         db_lat IS DISTINCT FROM latitude OR db_lon IS DISTINCT FROM longitude OR
         db_speed IS DISTINCT FROM velocidade_nos OR db_heading IS DISTINCT FROM rumo_graus)),
     'samples', (SELECT coalesce(json_agg(s), '[]'::json) FROM (
         SELECT packet_id, sequence_number, db_seq, timestamp_ms, db_ts
           FROM auditoria
          WHERE db_id IS NULL OR db_seq <> sequence_number OR db_ts <> timestamp_ms
             OR db_boat <> boat_id
          ORDER BY ordinal LIMIT 10) s))
   FROM auditoria`,
];

export function evaluateAudit(audit) {
  const failures = ['missing', 'boat_mismatch', 'sequence_mismatch', 'timestamp_mismatch', 'payload_mismatch']
    .filter((key) => Number(audit[key]) !== 0);
  return {
    ok: failures.length === 0 && Number(audit.found) === Number(audit.expected) && Number(audit.expected) > 0,
    failures,
  };
}

// Critérios de aceite da SCRUM-26, na ordem do ticket.
export function evaluateCriteria(evidence, options) {
  const criteria = [];
  const add = (id, title, ok, detail) => criteria.push({ id, title, ok: Boolean(ok), detail });

  const { partition, accumulation, manifest, restart, drain, order, audit, central, sqs } = evidence;

  add('particao', 'Partição da rota gRPC durante a navegação',
    partition.cut && partition.restored && accumulation.statesSeen.includes('offline') &&
      !accumulation.statesSeen.some((state) => state === 'blocked' || state === 'storage_error'),
    `modo=${options.mode}; estados observados: ${accumulation.statesSeen.join(', ')}`);

  const windowRespected = accumulation.maxMemoryCount <= accumulation.memoryLimit;
  const spilled = accumulation.finalDiskCount > 0 || options.packets <= accumulation.memoryLimit;
  const growthOk = accumulation.rssGrowthAfterWindowMib === null ||
    accumulation.rssGrowthAfterWindowMib <= options.boatMemGrowthMib;
  add('acumulo', 'Acúmulo contínuo em disco sem consumo excessivo de RAM',
    manifest.ok && restart.ok && windowRespected && spilled && growthOk,
    `${manifest.size} pacotes retidos; RAM <= ${accumulation.memoryLimit} itens (máx. ${accumulation.maxMemoryCount}); ` +
      `disco=${accumulation.finalDiskCount}; RSS após janela cheia +${accumulation.rssGrowthAfterWindowMib ?? 'n/d'} MiB ` +
      `(limite ${options.boatMemGrowthMib}); reinício preservou ${restart.pendingAfterRestart}`);

  add('drenagem', 'Reativação do link e drenagem ordenada',
    drain.completed && order.ok,
    `${drain.packetsPerSecond} pacotes/s em ${drain.seconds}s; ` +
      `${order.delivered}/${order.expected} ACKs em ordem FIFO (fora de ordem: ${order.outOfOrder})`);

  const auditResult = evaluateAudit(audit);
  add('integridade', '100% dos pacotes na Central com sequência e timestamp preservados',
    auditResult.ok,
    `${audit.found}/${audit.expected} no PostgreSQL; divergências: seq=${audit.sequence_mismatch}, ` +
      `ts=${audit.timestamp_mismatch}, payload=${audit.payload_mismatch}, boat=${audit.boat_mismatch}`);

  const centralOk = central.every((service) => !service.oomKilled && service.restarts === 0 &&
    (service.limitMib === null || service.peakMib <= service.limitMib * options.centralMemRatio));
  add('central', 'Drenagem sem estouro de memória na Central (proteção SQS)',
    centralOk && sqs.drained && sqs.dlq === 0,
    central.map((service) => `${service.name}: pico ${service.peakMib} MiB / limite ${service.limitMib ?? '∞'} MiB` +
      `${service.oomKilled ? ' OOM' : ''}${service.restarts ? ` reinícios=${service.restarts}` : ''}`).join('; ') +
      `; backlog SQS máx. ${sqs.peakDepth}, final ${sqs.finalDepth}, DLQ ${sqs.dlq}`);

  return { ok: criteria.every((criterion) => criterion.ok), criteria };
}
