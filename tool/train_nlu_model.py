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
            if "numbers" in name:
                continue
            files.append(p)
    return files


def _iter_records(path: Path):
    if path.suffix.lower() == ".jsonl":
        with path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    yield json.loads(line)
    else:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, list):
                for item in data:
                    if isinstance(item, dict):
                        yield item


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

    # Keep top 5000 features with df >= 3 for compact JSON size
    vocab = [
        ft
        for ft, df in feat_df.most_common(6000)
        if df >= 3
    ][:5000]
    vocab_set = set(vocab)
    vocab_size = len(vocab)
    labels = sorted(class_counts.keys())
    total_docs = sum(class_counts.values())
    alpha = 0.25

    # Use balanced (uniform) priors so high-frequency classes don't drown out rare intents
    priors = {lbl: 0.0 for lbl in labels}

    # Compute IDF weighting and log-probabilities
    idf = {
        ft: math.log((1 + total_docs) / (1 + feat_df[ft])) + 1.0
        for ft in vocab
    }

    baselines = {}
    weights: dict[str, dict[str, float]] = {}
    for lbl in labels:
        denom = class_total_feats[lbl] + alpha * vocab_size
        base = math.log(alpha / denom)
        baselines[lbl] = round(base, 4)
        lbl_weights: dict[str, float] = {}
        counts = class_feat_counts[lbl]
        for ft, cnt in counts.items():
            if ft in vocab_set and cnt > 0:
                delta = (math.log((cnt + alpha) / denom) - base) * idf[ft]
                lbl_weights[ft] = round(delta, 4)
        weights[lbl] = lbl_weights

    # Evaluate on held-out test set
    correct = 0
    for true_lbl, feats in test_docs:
        in_vocab = [ft for ft in feats if ft in vocab_set]
        n_hits = len(in_vocab)
        scores = {lbl: baselines[lbl] * n_hits for lbl in labels}
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

