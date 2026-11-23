"""Ferramenta de Engenharia do Caos e Teste de Carga gRPC até a Saturação.

Uso rápido na AWS (lê endpoints e certificados direto do Terraform local):
    python scripts/chaos_load_test.py --stages 10:15,50:20,150:30,300:60,500:120
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import statistics
import subprocess
import sys
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import grpc

REPO_ROOT = Path(__file__).resolve().parent.parent
CENTRAL_DIR = REPO_ROOT / "ferry-central"
if str(CENTRAL_DIR) not in sys.path:
    sys.path.insert(0, str(CENTRAL_DIR))

from src.proto import telemetry_pb2, telemetry_pb2_grpc  # noqa: E402


@dataclass
class StageStats:
    concurrency: int
    duration_s: float
    total: int = 0
    accepted: int = 0
    duplicated: int = 0
    errors: dict[str, int] = field(default_factory=dict)
    latencies_ms: list[float] = field(default_factory=list)

    @property
    def ok_count(self) -> int:
        return self.accepted + self.duplicated

    @property
    def error_count(self) -> int:
        return sum(self.errors.values())

    def percentile(self, p: float) -> float:
        if not self.latencies_ms:
            return 0.0
        ordered = sorted(self.latencies_ms)
        idx = min(len(ordered) - 1, max(0, math.ceil((p / 100.0) * len(ordered)) - 1))
        return ordered[idx]


def tf_output(name: str) -> str:
    return subprocess.check_output(
        ["terraform", "-chdir=terraform", "output", "-raw", name],
        cwd=REPO_ROOT,
        text=True,
    ).strip()


def build_packet(boat_id: str, seq: int) -> telemetry_pb2.TelemetryPacket:
    now_ms = int(time.time() * 1000)
    kwargs: dict[str, Any] = {}
    pkt_fields = {f.name for f in telemetry_pb2.TelemetryPacket.DESCRIPTOR.fields}
    if "sequence_number" in pkt_fields:
        kwargs["sequence_number"] = seq

    return telemetry_pb2.TelemetryPacket(
        message_id=str(uuid.uuid4()),
        boat_id=boat_id,
        timestamp_coleta=now_ms,
        passageiros=120,
        navegacao=telemetry_pb2.NavigationData(
            latitude=-12.9550,
            longitude=-38.5250,
            velocidade_nos=12.5,
            rumo_graus=245.0,
            status_navegacao=telemetry_pb2.NAVIGATION_STATUS_EM_TRAVESSIA,
        ),
        propulsao=telemetry_pb2.PropulsionData(
            rpm_motor=1700.0,
            temperatura_motor_celsius=84.5,
            pressao_oleo_bar=4.1,
            nivel_combustivel_percentual=78.0,
            consumo_instantaneo_lph=95.0,
        ),
        rede=telemetry_pb2.NetworkDiagnostics(
            rssi_dbm=-72,
            latencia_rtt_ms=110.0,
            perda_pacotes_percentual=0.0,
            tamanho_buffer_local=0,
            tentativa_envio=1,
            tipo_enlace=telemetry_pb2.LINK_TYPE_4G_5G_COSTEIRO,
        ),
        **kwargs,
    )


async def run_stage(
    channels: list[grpc.aio.Channel],
    boat_id: str,
    concurrency: int,
    duration_s: float,
    deadline_ms: int,
    seq_counter: list[int],
) -> StageStats:
    stubs = [telemetry_pb2_grpc.TelemetryServiceStub(ch) for ch in channels]
    stats = StageStats(concurrency=concurrency, duration_s=duration_s)
    stop_at = time.monotonic() + duration_s
    timeout_s = deadline_ms / 1000.0

    async def worker(worker_id: int) -> None:
        stub = stubs[worker_id % len(stubs)]
        while time.monotonic() < stop_at:
            seq_counter[0] += 1
            seq = seq_counter[0]
            pkt = build_packet(boat_id, seq)
            t0 = time.perf_counter()
            try:
                ack = await stub.EnviarTelemetria(
                    pkt,
                    timeout=timeout_s,
                    metadata=(("x-sequence-number", str(seq)),),
                )
                elapsed_ms = (time.perf_counter() - t0) * 1000.0
                stats.total += 1
                stats.latencies_ms.append(elapsed_ms)
                if ack.status == telemetry_pb2.ACK_STATUS_ACEITO:
                    stats.accepted += 1
                elif ack.status == telemetry_pb2.ACK_STATUS_DUPLICADO_IGNORADO:
                    stats.duplicated += 1
                else:
                    code_name = f"ACK_{ack.status}"
                    stats.errors[code_name] = stats.errors.get(code_name, 0) + 1
            except grpc.aio.AioRpcError as exc:
                elapsed_ms = (time.perf_counter() - t0) * 1000.0
                stats.total += 1
                stats.latencies_ms.append(elapsed_ms)
                name = exc.code().name
                stats.errors[name] = stats.errors.get(name, 0) + 1

    t_start = time.perf_counter()
    await asyncio.gather(*(worker(i) for i in range(concurrency)))
    stats.duration_s = time.perf_counter() - t_start
    return stats


def poll_aws_snapshot(sqs_url: str, cluster: str) -> dict[str, Any]:
    ecs_raw = subprocess.check_output(
        [
            "aws",
            "ecs",
            "describe-services",
            "--cluster",
            cluster,
            "--services",
            "ferry-central-ingestion-prod",
            "ferry-central-worker-prod",
            "--query",
            "services[].{name:serviceName,desired:desiredCount,running:runningCount,pending:pendingCount}",
        ],
        text=True,
    )
    sqs_raw = subprocess.check_output(
        [
            "aws",
            "sqs",
            "get-queue-attributes",
            "--queue-url",
            sqs_url,
            "--attribute-names",
            "ApproximateNumberOfMessages",
            "ApproximateNumberOfMessagesNotVisible",
            "--query",
            "Attributes",
        ],
        text=True,
    )
    return {
        "ts": time.strftime("%H:%M:%S"),
        "ecs": json.loads(ecs_raw),
        "sqs": json.loads(sqs_raw),
    }


async def main_async(args: argparse.Namespace) -> int:
    if args.insecure:
        channels = [grpc.aio.insecure_channel(args.target) for _ in range(args.channels)]
    else:
        ca_bytes = Path(args.ca).read_bytes() if args.ca else tf_output("tls_ca_cert_pem").encode()
        cert_bytes = Path(args.cert).read_bytes() if args.cert else tf_output("tls_boat_cert_pem").encode()
        key_bytes = Path(args.key).read_bytes() if args.key else tf_output("tls_boat_key_pem").encode()
        creds = grpc.ssl_channel_credentials(
            root_certificates=ca_bytes,
            private_key=key_bytes,
            certificate_chain=cert_bytes,
        )
        channels = [grpc.aio.secure_channel(args.target, creds) for _ in range(args.channels)]

    stages: list[tuple[int, float]] = []
    for item in args.stages.split(","):
        c_str, d_str = item.strip().split(":")
        stages.append((int(c_str), float(d_str)))

    sqs_url = args.sqs_url
    if args.monitor_aws and not sqs_url:
        sqs_url = tf_output("sqs_db_writer_queue_url")

    seq_counter = [0]
    stop_poller = asyncio.Event()

    async def periodic_poller() -> None:
        while not stop_poller.is_set():
            try:
                snap = await asyncio.to_thread(poll_aws_snapshot, sqs_url, args.cluster)
                print(f"  [AWS {snap['ts']}] SQS={snap['sqs']} | ECS={snap['ecs']}", flush=True)
            except Exception as exc:
                print(f"  [AWS poll erro] {exc}", flush=True)
            try:
                await asyncio.wait_for(stop_poller.wait(), timeout=args.poll_interval)
            except TimeoutError:
                pass

    poller_task = asyncio.create_task(periodic_poller()) if args.monitor_aws and args.poll_interval > 0 else None
    try:
        for conc, dur in stages:
            print(f"\n=== Estágio: concorrência={conc}, duração={dur:.0f}s, deadline={args.deadline_ms}ms ===", flush=True)
            stats = await run_stage(
                channels=channels,
                boat_id=args.boat_id,
                concurrency=conc,
                duration_s=dur,
                deadline_ms=args.deadline_ms,
                seq_counter=seq_counter,
            )
            rps = stats.total / max(0.001, stats.duration_s)
            ok_rps = stats.ok_count / max(0.001, stats.duration_s)
            err_pct = (stats.error_count / max(1, stats.total)) * 100.0
            mean_ms = statistics.mean(stats.latencies_ms) if stats.latencies_ms else 0.0
            print(
                f"Total={stats.total} | OK={stats.ok_count} ({ok_rps:.1f} req/s) | "
                f"TotalRPS={rps:.1f} | Erros={stats.error_count} ({err_pct:.2f}%) {stats.errors}",
                flush=True,
            )
            print(
                f"Latência (ms): média={mean_ms:.1f} | p50={stats.percentile(50):.1f} | "
                f"p95={stats.percentile(95):.1f} | p99={stats.percentile(99):.1f}",
                flush=True,
            )
            if args.monitor_aws:
                snap = await asyncio.to_thread(poll_aws_snapshot, sqs_url, args.cluster)
                print(f"AWS [{snap['ts']}]: SQS={snap['sqs']} | ECS={snap['ecs']}", flush=True)
    finally:
        stop_poller.set()
        if poller_task is not None:
            await poller_task
        await asyncio.gather(*(ch.close() for ch in channels))
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Teste de carga e engenharia do caos gRPC.")
    parser.add_argument("--target", default="", help="host:porta gRPC (padrão: output alb_dns_name:50051)")
    parser.add_argument("--stages", default="10:15,50:20,150:30,300:60", help="Lista conc:seg")
    parser.add_argument("--channels", type=int, default=8, help="Quantidade de canais HTTP/2")
    parser.add_argument("--deadline-ms", type=int, default=2500, help="Deadline gRPC por chamada (ms)")
    parser.add_argument("--boat-id", default="ferry-chaos-test", help="boat_id sintético para o teste")
    parser.add_argument("--ca", default="", help="Caminho para ca.crt")
    parser.add_argument("--cert", default="", help="Caminho para boat.crt")
    parser.add_argument("--key", default="", help="Caminho para boat.key")
    parser.add_argument("--insecure", action="store_true", help="Usa canal sem TLS (apenas dev local)")
    parser.add_argument("--monitor-aws", action="store_true", help="Consulta ECS e SQS durante os estágios")
    parser.add_argument("--poll-interval", type=float, default=30.0, help="Intervalo de polling AWS em segundos (0 desativa)")
    parser.add_argument("--sqs-url", default="", help="URL da fila SQS do worker")
    parser.add_argument("--cluster", default="ferry-cluster-prod", help="Nome do cluster ECS")
    args = parser.parse_args()
    if not args.target:
        args.target = f"{tf_output('alb_dns_name')}:50051"
    return args


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main_async(parse_args())))
