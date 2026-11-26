"""
Distills 25,000 balanced Egyptian colloquial contrast sentences from gen_egyptian_1m.py
into tool/corpus/egyptian_general_distill.jsonl so train_nlu_model.py sharpens IDF
and distinguishes real ERP intents from everyday non-ERP chatter.
"""
import json
import random
from pathlib import Path

import gen_egyptian_1m as g

OUT_PATH = Path(__file__).resolve().parent / "corpus" / "egyptian_general_distill.jsonl"
OUT_PATH.parent.mkdir(parents=True, exist_ok=True)

ERP_GUARD = {
    "محل", "المحل", "مخزن", "المخزن", "كاشير", "الكاشير", "مورد", "المورد",
    "فاتورة", "الفاتورة", "قسط", "اقساط", "القسط", "الاقساط", "مصاريف", "المصاريف",
    "شحنة", "الشحنة", "بضاعة", "البضاعة", "زكاة", "الزكاة", "ميزانية", "الميزانية",
    "شريك", "الشريك", "ديون", "الديون", "مرتب", "المرتبات", "ايجار", "الايجار",
}


def main() -> None:
    random.seed(2026)
    seen = set()
    records = []

    # 1. Sample general non-ERP everyday sentences -> out_of_scope (20,000)
    non_erp_fns = [g.fam_feeling, g.fam_motion, g.fam_time, g.fam_object, g.fam_verbal, g.fam_question]
    while len(records) < 20000:
        s = g.R(non_erp_fns)()
        kk = g.key(s)
        if not kk or kk in seen:
            continue
        words = set(kk.split())
        if words & ERP_GUARD:
            continue
        seen.add(kk)
        records.append({"text": s, "intent": "out_of_scope", "split": "train"})

    # 2. Sample social chitchat expressions -> chitchat (5,000)
    chitchat_count = 0
    while chitchat_count < 5000:
        s = g.fam_expr()
        kk = g.key(s)
        if not kk or kk in seen:
            continue
        if set(kk.split()) & ERP_GUARD:
            continue
        seen.add(kk)
        records.append({"text": s, "intent": "chitchat", "split": "train"})
        chitchat_count += 1

    with OUT_PATH.open("w", encoding="utf-8") as f:
        for rec in records:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    print(f"Wrote {len(records)} distilled Egyptian sentences to {OUT_PATH}")


if __name__ == "__main__":
    main()

