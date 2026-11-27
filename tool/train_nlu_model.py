"""
Trains a lightweight Arabic/Egyptian NLU classifier (Word Unigrams/Bigrams + Char 3-4 grams,
Multinomial Naive Bayes with log-likelihood ratios) from tool/assistant_egyptian_corpus_v2.jsonl
and exports a compact JSON model to assets/assistant_nlu_model.json.
"""

import collections
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOL_DIR = ROOT / "tool"
CORPUS_DIR = TOOL_DIR / "corpus"
OUT_PATH = ROOT / "assets" / "assistant_nlu_model.json"

# Map corpus v1/v2 intents (and direct Dart enum names) to Dart AssistantNluIntent enum names
INTENT_MAP = {
    "addProduct": "addProduct",
    "recordPurchase": "recordPurchase",
    "recordExpense": "recordExpense",
    "paySupplier": "paySupplier",
    "addCustomer": "addCustomer",
    "collectInstallment": "collectInstallment",
    "updateProductPriceOrStock": "updatePrice",
    "calculateZakat": "calculateZakat",
    "getLateInstallmentsInsight": "overdueInstallments",
    "getMarketingPostInsight": "promoPost",
    "getSalesDiagnosisInsight": "salesDiagnosis",
    "getTodayProfitInsight": "todayProfit",
    "fu_yesterday": "yesterdayFollowup",
    "getWhatIfPricingInsight": "whatIfPricing",
    "getCustomerObjectionRepliesInsight": "objectionReplies",
    "getGoalPlannerInsight": "goalPlanner",
    "getStoreHealthScoreInsight": "storeHealthScore",
    "getSmartReorderListInsight": "smartReorderList",
    "getSupplierDuesInsight": "suppliersDues",
    "getStagnantProductsInsight": "stagnantStock",
    "getStorePulseInsight": "storePulse",
    "getTopProfitProductsInsight": "topProfitProducts",
    "getEndOfDayReportInsight": "endOfDayReport",
    "getTopVariantsByProductInsight": "topVariants",
    "getCheapestSupplierForProductInsight": "cheapestSupplier",
    "searchByBarcodeOrSkuInsight": "searchByBarcodeOrSku",
    "getMarginLeakInsight": "marginLeak",
    "getBreakEvenInsight": "breakEven",
    "getCashierPerformanceInsight": "cashierPerformance",
    "getBudgetComparisonInsight": "budgetComparison",
    "getTodayAuditsAndCancellationsInsight": "todayAudits",
    "getWinBackCustomersInsight": "winBackCustomers",
    "getInstallmentReminderMessageInsight": "installmentReminderMessage",
    "getSeasonPlanInsight": "seasonPlan",
    "getInflationCalculatorInsight": "inflationCalculator",
    "getLiquidityStrategyInsight": "liquidityStrategy",
    "getVisualMerchandisingInsight": "visualMerchandising",
    "toggleBlindShiftClosing": "toggleBlindShiftClosing",
    "toggleManagerPinProtection": "toggleManagerPinProtection",
    "toggleAllowManualDiscount": "toggleAllowManualDiscount",
    "toggleAutoBackup": "toggleAutoBackup",
    "updateStoreName": "updateStoreName",
    "updateStorePhone": "updateStorePhone",
    "backupNow": "backupNow",
    "shiftSummary": "shiftSummary",
    "preOrderQuery": "preOrderQuery",
    "preOrderCreate": "preOrderCreate",
    "deliveryQuery": "deliveryQuery",
    "repairQuery": "repairQuery",
    "walletQuery": "walletQuery",
    "walletTransfer": "walletTransfer",
    "partnerShares": "partnerShares",
    "partnerWithdraw": "partnerWithdraw",
    "undoLast": "undoLast",
    "howToGuide": "howToGuide",
    "knowledge": "knowledge",
    "confirm": "confirm",
    "cancel": "cancel",
    "chitchat": "chitchat",
    "out_of_scope": "outOfScope",
    "reject_or_fix": "rejectOrFix",
    "help": "help",
    "fu_same_supplier": "fuSameSupplier",
    "fu_one_more": "fuOneMore",
    "fu_change_value": "fuChangeValue",
    "fu_details": "fuDetails",
    "fu_tone": "fuTone",
    "fu_copy": "fuCopy",
}

ARABIC_INDIC = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")
PUNCT_RE = re.compile(r"[؟?!\.,،:;_\-\"\(\)\[\]\{\}\\/+=*&^%$#@~`><|]")
DIACRITICS_RE = re.compile(r"[\u064B-\u065F\u0670]")
NUM_RE = re.compile(r"\b\d+(?:\.\d+)?\b")


def normalize_text(text: str) -> str:
    s = text.translate(ARABIC_INDIC).lower().strip()
    s = s.replace("ـ", "")
    s = DIACRITICS_RE.sub("", s)
    s = (
        s.replace("أ", "ا")
        .replace("إ", "ا")
        .replace("آ", "ا")
        .replace("ى", "ي")
        .replace("ة", "ه")
    )
    s = PUNCT_RE.sub(" ", s)
    s = NUM_RE.sub(" <NUM> ", s)
    return " ".join(s.split())


def extract_features(norm: str) -> list[str]:
    words = norm.split()
    feats: list[str] = []
    for w in words:
        feats.append(f"w:{w}")
    for i in range(len(words) - 1):
        feats.append(f"b:{words[i]}_{words[i + 1]}")
    # Char 3-4 grams for dialect & typo robustness
    for w in words:
        if w == "<NUM>" or len(w) < 3:
            continue
        padded = f"^{w}$"
        for n in (3, 4):
            if len(padded) >= n:
                for j in range(len(padded) - n + 1):
                    feats.append(f"c:{padded[j:j + n]}")
    return feats


def _resolve_intent(raw_intent: str | None) -> str | None:
    if not raw_intent:
        return None
    if raw_intent in INTENT_MAP:
        return INTENT_MAP[raw_intent]
    if raw_intent in INTENT_MAP.values():
        return raw_intent
    return None


def _discover_corpus_files() -> list[Path]:
    files: list[Path] = []
    search_dirs = [TOOL_DIR] + ([CORPUS_DIR] if CORPUS_DIR.exists() else [])
    for d in search_dirs:
        for p in sorted(d.iterdir()):
            if not p.is_file():
                continue
            if p.suffix.lower() not in (".jsonl", ".json"):
                continue
            name = p.name.lower()
            if "numbers" in name or "nlu_model" in name or "knowledge" in name:
                continue
            files.append(p)
    return files


_CATEGORY_INTENT_MAP = {
    "greetings_and_chitchat": "chitchat",
    "bills_and_shop_utilities": "recordExpense",
    "out_of_scope_daily_life": "out_of_scope",
}


def _iter_records(path: Path):
    if path.suffix.lower() == ".jsonl":
        with path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    yield json.loads(line)
    else:
        raw = path.read_text(encoding="utf-8").strip()
        if not raw:
            return
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            # Fallback for JSONL files saved with a .json extension
            for line in raw.splitlines():
                line = line.strip()
                if line:
                    yield json.loads(line)
            return
        if isinstance(data, list):
            for item in data:
                if isinstance(item, dict):
                    yield item
        elif isinstance(data, dict) and isinstance(data.get("categories"), dict):
            for cat_name, cat_obj in data["categories"].items():
                mapped_intent = _CATEGORY_INTENT_MAP.get(cat_name)
                if not mapped_intent or not isinstance(cat_obj, dict):
                    continue
                for term in cat_obj.get("terms", []):
                    if isinstance(term, str) and term.strip():
                        yield {"text": term.strip(), "intent": mapped_intent, "split": "train"}


def main() -> None:
    train_docs: list[tuple[str, list[str]]] = []
    test_docs: list[tuple[str, list[str]]] = []

    corpus_files = _discover_corpus_files()
    print(f"Discovered {len(corpus_files)} corpus files: {[p.name for p in corpus_files]}")

    for path in corpus_files:
        for row in _iter_records(path):
            split = row.get("split", "train")
            # Dialogue format with 'turns'
            if "turns" in row and isinstance(row["turns"], list):
                for idx, turn in enumerate(row["turns"]):
                    if turn.get("role") != "user":
                        continue
                    raw_lbl = turn.get("label")
                    if idx == 0 and raw_lbl not in INTENT_MAP and row.get("intent"):
                        raw_lbl = row.get("intent")
                    mapped = _resolve_intent(raw_lbl)
                    if not mapped:
                        continue
                    norm = normalize_text(turn.get("text", ""))
                    if not norm:
                        continue
                    feats = extract_features(norm)
                    if split == "test":
                        test_docs.append((mapped, feats))
                    else:
                        train_docs.append((mapped, feats))
                continue

            # Standard sentence format with 'text' + 'intent'
            mapped = _resolve_intent(row.get("intent"))
            if not mapped:
                continue
            norm = normalize_text(row.get("text", ""))
            if not norm:
                continue
            feats = extract_features(norm)
            if split == "test":
                test_docs.append((mapped, feats))
            else:
                train_docs.append((mapped, feats))

    print(f"Loaded train={len(train_docs)}, test={len(test_docs)}")

    # Count feature frequencies
    feat_df = collections.Counter()
    class_counts = collections.Counter()
    class_feat_counts: dict[str, collections.Counter] = collections.defaultdict(
        collections.Counter
    )
    class_total_feats = collections.Counter()

    for label, feats in train_docs:
        class_counts[label] += 1
        unique_feats = set(feats)
        for ft in unique_feats:
            feat_df[ft] += 1
        for ft in feats:
            class_feat_counts[label][ft] += 1
            class_total_feats[label] += 1

    # Keep top 4500 features with df >= 3 for compact JSON size & strong coverage
    vocab = [
        ft
        for ft, df in feat_df.most_common(6000)
        if df >= 3
    ][:4500]
    vocab_idx = {ft: i for i, ft in enumerate(vocab)}
    vocab_size = len(vocab)
    labels = sorted(class_counts.keys())
    lbl_idx = {lbl: i for i, lbl in enumerate(labels)}
    num_classes = len(labels)

    # Encode docs as integer feature lists + class-balanced sample weights
    encoded_train: list[tuple[int, list[int], float]] = []
    median_cnt = sorted(class_counts.values())[num_classes // 2]
    class_sample_w = {
        lbl: min(4.0, max(0.35, math.sqrt(median_cnt / max(1, class_counts[lbl]))))
        for lbl in labels
    }
    for lbl, feats in train_docs:
        f_ids = [vocab_idx[ft] for ft in feats if ft in vocab_idx]
        if f_ids:
            encoded_train.append((lbl_idx[lbl], f_ids, class_sample_w[lbl]))

    # Train Multinomial Logistic Regression (Softmax + AdaGrad + L2) in pure Python
    import random
    rng = random.Random(42)

    W = [[0.0] * num_classes for _ in range(vocab_size)]
    G_W = [[1e-6] * num_classes for _ in range(vocab_size)]
    B = [0.0] * num_classes
    G_B = [1e-6] * num_classes

    lr = 0.35
    l1 = 5e-5
    l2 = 1e-5
    epochs = 3

    for epoch in range(epochs):
        rng.shuffle(encoded_train)
        total_loss = 0.0
        for y, f_ids, sw in encoded_train:
            scores = B[:]
            for fid in f_ids:
                wf = W[fid]
                for c in range(num_classes):
                    scores[c] += wf[c]

            m_s = max(scores)
            exps = [math.exp(s - m_s) for s in scores]
            inv_sum = 1.0 / sum(exps)

            total_loss -= sw * math.log(max(exps[y] * inv_sum, 1e-12))

            # Sparse active-class gradient update (skips near-zero probabilities for ~10x speedup)
            active_c: list[tuple[int, float]] = []
            for c in range(num_classes):
                g = (exps[c] * inv_sum - (1.0 if c == y else 0.0)) * sw
                if abs(g) > 1e-4:
                    G_B[c] += g * g
                    B[c] -= (lr / math.sqrt(G_B[c])) * g
                    active_c.append((c, g))

            for fid in f_ids:
                wf = W[fid]
                gf = G_W[fid]
                for c, g_base in active_c:
                    w_val = wf[c]
                    g = g_base + l2 * w_val + (l1 if w_val > 0.0 else (-l1 if w_val < 0.0 else 0.0))
                    gf[c] += g * g
                    wf[c] -= (lr / math.sqrt(gf[c])) * g

        avg_loss = total_loss / max(1, len(encoded_train))
        print(f"Epoch {epoch + 1}/{epochs} - loss: {avg_loss:.4f}", flush=True)

    # Export in Dart-compatible format (baselines = 0.0, priors = B, pruned small weights)
    priors = {labels[c]: round(B[c], 3) for c in range(num_classes)}
    baselines = {lbl: 0.0 for lbl in labels}
    weights: dict[str, dict[str, float]] = {lbl: {} for lbl in labels}
    for fid, ft in enumerate(vocab):
        wf = W[fid]
        for c, lbl in enumerate(labels):
            val = wf[c]
            if abs(val) >= 0.05:
                weights[lbl][ft] = round(val, 3)

    # Evaluate on held-out test set using exact Dart scoring logic
    correct = 0
    for true_lbl, feats in test_docs:
        in_vocab = [ft for ft in feats if ft in vocab_idx]
        scores = {lbl: priors[lbl] for lbl in labels}
        for ft in in_vocab:
            for lbl in labels:
                w = weights[lbl].get(ft)
                if w is not None:
                    scores[lbl] += w
        pred = max(scores, key=scores.__getitem__)
        if pred == true_lbl:
            correct += 1

    acc = (correct / len(test_docs) * 100.0) if test_docs else 0.0
    print(f"Test accuracy: {correct}/{len(test_docs)} ({acc:.2f}%)")

    model = {
        "version": 2,
        "vocabSize": vocab_size,
        "labels": labels,
        "priors": priors,
        "baselines": baselines,
        "weights": weights,
    }
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(model, f, ensure_ascii=False, separators=(",", ":"))
    size_kb = OUT_PATH.stat().st_size / 1024.0
    print(f"Exported {OUT_PATH} ({size_kb:.1f} KB)")


if __name__ == "__main__":
    main()

