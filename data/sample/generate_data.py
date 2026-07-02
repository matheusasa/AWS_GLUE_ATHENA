#!/usr/bin/env python3
"""
generate_data.py
Gera dados sintéticos (vendas, clientes, produtos) para os laboratórios do
treinamento, usando a biblioteca Faker (locale pt_BR).

Os arquivos gerados seguem EXATAMENTE o schema esperado pelos jobs Glue
(bronze_ingest / silver_transform / gold_aggregate):

    clientes.csv : id_cliente, nome, regiao
    produtos.csv : id_produto, categoria, marca
    vendas.csv   : id_venda, id_cliente, id_produto, quantidade, valor_unit,
                   data_venda, canal

Uso típico:
    pip install faker
    python generate_data.py --clientes 200 --produtos 50 --vendas 5000

Opções úteis para os exercícios de QUALIDADE DE DADOS:
    --dirty 0.02   -> injeta ~2% de registros sujos (valor negativo, nulos,
                      duplicidade de id_venda) para testar dedup/is_valid.

Opcional (PII):
    --with-pii     -> gera também clientes_pii.csv com CPF/e-mail/telefone
                      (para o exercício de mascaramento do Módulo 09).
"""

from __future__ import annotations

import argparse
import csv
import os
import random
from datetime import datetime, timedelta

try:
    from faker import Faker
except ImportError:
    raise SystemExit(
        "Biblioteca 'faker' não encontrada. Instale com:\n  pip install faker"
    )


CANAIS = ["online", "loja", "app", "telefone", "marketplace"]
CATEGORIAS = [
    ("Eletronicos", ["TechBrand", "Pixel", "OmegaTech", "NovaEletronics"]),
    ("Vestuario", ["ModaBR", "Estilo+", "Urbano Wear"]),
    ("Casa", ["CasaMais", "LarDoce", "Confortar"]),
    ("Livros", ["LerMais", "PapelariaBR"]),
    ("Beleza", ["Bella", "Essencia"]),
]
REGIOES = ["Sudeste", "Sul", "Nordeste", "Norte", "Centro-Oeste"]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Gera dados sintéticos para o data lake.")
    p.add_argument("--outdir", default=".", help="Pasta de saída (default: .)")
    p.add_argument("--clientes", type=int, default=100, help="Nº de clientes")
    p.add_argument("--produtos", type=int, default=40, help="Nº de produtos")
    p.add_argument("--vendas", type=int, default=2000, help="Nº de vendas")
    p.add_argument("--dias", type=int, default=90,
                   help="Janela de tempo (dias para trás) para data_venda")
    p.add_argument("--seed", type=int, default=42, help="Semente (reprodutível)")
    p.add_argument("--dirty", type=float, default=0.0,
                   help="Fração de registros sujos [0..1] (default: 0)")
    p.add_argument("--with-pii", action="store_true",
                   help="Gera clientes_pii.csv (CPF/e-mail/telefone) p/ exercício de PII")
    return p.parse_args()


def escrever_csv(path: str, header: list[str], rows: list[list]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"  -> {path}  ({len(rows)} linhas)")


def gerar_clientes(fake: Faker, n: int) -> list[list]:
    """id_cliente, nome, regiao"""
    return [
        [i + 1, fake.name(), random.choice(REGIOES)]
        for i in range(n)
    ]


def _cidade(fake: Faker) -> str:
    """Retorna uma cidade usando o método disponível no locale (robusto)."""
    for attr in ("municipality", "city", "city_name", "administrative_unit"):
        fn = getattr(fake, attr, None)
        if callable(fn):
            try:
                return fn()
            except Exception:
                continue
    return "Sao Paulo"


def gerar_clientes_pii(fake: Faker, clientes: list[list]) -> list[list]:
    """Adiciona CPF, email, telefone, cidade aos clientes (exercício de PII)."""
    out = []
    for cid, nome, regiao in clientes:
        out.append([
            cid, nome, regiao,
            fake.cpf(),
            fake.ascii_safe_email(),
            fake.phone_number(),
            _cidade(fake),
        ])
    return out


def gerar_produtos(fake: Faker, n: int) -> list[list]:
    """id_produto, categoria, marca"""
    out = []
    for i in range(n):
        categoria, marcas = random.choice(CATEGORIAS)
        out.append([i + 1, categoria, random.choice(marcas)])
    return out


def gerar_vendas(fake: Faker, n: int, n_clientes: int, n_produtos: int,
                 dias: int, dirty: float) -> list[list]:
    """id_venda, id_cliente, id_produto, quantidade, valor_unit, data_venda, canal"""
    agora = datetime(2026, 7, 1, 0, 0, 0)  # data "atual" de referência do dataset
    out = []
    # Alguns ids podem se repetir propositalmente (duplicidade p/ lab de dedup)
    for i in range(n):
        id_venda = i + 1
        # 1) Caso normal
        id_cliente = random.randint(1, n_clientes)
        id_produto = random.randint(1, n_produtos)
        quantidade = random.choices([1, 1, 1, 2, 2, 3, 4, 5, 10], k=1)[0]
        valor_unit = round(random.choices(
            [49.90, 89.90, 129.90, 199.00, 459.00, 1500.00, 2100.00, 3200.00],
            k=1)[0], 2)
        data = agora - timedelta(
            days=random.randint(0, dias),
            seconds=random.randint(0, 86400),
        )
        canal = random.choice(CANAIS)

        # 2) Sujidade controlada (data quality lab)
        r = random.random()
        if r < dirty:
            # valor negativo ou zero -> is_valid=false
            valor_unit = round(-abs(random.uniform(1, 50)), 2)
        elif r < dirty * 2:
            # cliente/produto nulo (ausente) -> preenche com vazio
            if random.random() < 0.5:
                id_cliente = ""
            else:
                valor_unit = ""  # valor ausente
        elif r < dirty * 2.5:
            # duplica um id_venda anterior (reaproveita) -> cai na dedup
            id_venda = random.randint(1, max(1, i)) if i > 0 else id_venda

        out.append([
            id_venda, id_cliente, id_produto, quantidade, valor_unit,
            data.strftime("%Y-%m-%d %H:%M:%S"), canal,
        ])

    # Garante pelo menos 1 duplicata explícita quando dirty > 0
    if dirty > 0 and len(out) > 1:
        out.append(list(out[0]))  # cópia exata da 1ª linha (mesmo id_venda)
    return out


def main() -> None:
    args = parse_args()
    if not (0.0 <= args.dirty <= 1.0):
        raise SystemExit("--dirty deve estar entre 0 e 1")

    fake = Faker("pt_BR")
    Faker.seed(args.seed)
    random.seed(args.seed)

    os.makedirs(args.outdir, exist_ok=True)

    print(f"Gerando dados (seed={args.seed}, dirty={args.dirty}):")
    clientes = gerar_clientes(fake, args.clientes)
    produtos = gerar_produtos(fake, args.produtos)
    vendas = gerar_vendas(
        fake, args.vendas, args.clientes, args.produtos, args.dias, args.dirty
    )

    escrever_csv(os.path.join(args.outdir, "clientes.csv"),
                 ["id_cliente", "nome", "regiao"], clientes)
    escrever_csv(os.path.join(args.outdir, "produtos.csv"),
                 ["id_produto", "categoria", "marca"], produtos)
    escrever_csv(os.path.join(args.outdir, "vendas.csv"),
                 ["id_venda", "id_cliente", "id_produto", "quantidade",
                  "valor_unit", "data_venda", "canal"], vendas)

    if args.with_pii:
        escrever_csv(os.path.join(args.outdir, "clientes_pii.csv"),
                     ["id_cliente", "nome", "regiao", "cpf", "email",
                      "telefone", "cidade"],
                     gerar_clientes_pii(fake, clientes))

    print("Pronto! Arquivos prontos para subir ao S3 (bronze/landing/).")


if __name__ == "__main__":
    main()
